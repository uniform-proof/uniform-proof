describe("auth-domain billing gate", () => {
  const originalBillingMode = process.env.BILLING_MODE;

  afterEach(() => {
    jest.clearAllMocks();
    jest.restoreAllMocks();
    jest.resetModules();
    if (typeof originalBillingMode === "string") {
      process.env.BILLING_MODE = originalBillingMode;
    } else {
      delete process.env.BILLING_MODE;
    }
  });

  function createSupabaseAdminClientMock({ gated = true, gateError = null } = {}) {
    const maybeSingle = jest.fn().mockResolvedValue({
      data: gated ? { account_id: "acct_123" } : null,
      error: gateError,
    });
    const eq = jest.fn(() => ({ maybeSingle }));
    const select = jest.fn(() => ({ eq }));
    const from = jest.fn((table) => {
      if (table === "billing_gated_accounts") {
        return { select };
      }
      return {
        select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle: jest.fn() })) })),
      };
    });
    return { from };
  }

  function mockSharedAuthDependencies({
    gated = true,
    gateError = null,
    vaultEnabled = true,
    passState = null,
    sessionToken = null,
  } = {}) {
    const getSupabaseAdminClientMock = jest
      .fn()
      .mockReturnValue(createSupabaseAdminClientMock({ gated, gateError }));
    const consumeSessionChallengeMock = jest.fn().mockResolvedValue({
      account: {
        id: "acct_123",
        handle: "tester",
        status: "active",
      },
      signingPublicKey: "sign_pub_abc",
    });
    const verifyMembershipPassMock = jest
      .fn()
      .mockResolvedValue(
        passState || {
          valid: false,
          entitlementStatus: "inactive",
          provider: "unknown",
          status: "inactive",
          reason: "PASS_INVALID",
          effectiveUntil: null,
        },
      );
    const issueAppSessionTokenMock = jest.fn().mockReturnValue(
      sessionToken || {
        token: "jwt_token",
        payload: { exp: 1767225600 },
      },
    );

    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: getSupabaseAdminClientMock,
    }));
    jest.doMock("@/server/auth/session-challenge", () => ({
      consumeSessionChallenge: consumeSessionChallengeMock,
      issueSessionChallenge: jest.fn(),
    }));
    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled:
        typeof vaultEnabled === "function" ? vaultEnabled : jest.fn(() => vaultEnabled),
      verifyMembershipPass: verifyMembershipPassMock,
    }));
    jest.doMock("@/lib/app-session-jwt", () => ({
      issueAppSessionToken: issueAppSessionTokenMock,
    }));

    return {
      consumeSessionChallengeMock,
      verifyMembershipPassMock,
      issueAppSessionTokenMock,
    };
  }

  test("returns BILLING_REQUIRED when pass is missing for a gated account", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
        }),
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.code).toBe("BILLING_REQUIRED");
    expect(payload.billing?.reason).toBe("missing_pass");
    expect(payload.billing?.redirectTo).toContain("/billing-required");
    expect(verifyMembershipPassMock).not.toHaveBeenCalled();
    expect(issueAppSessionTokenMock).not.toHaveBeenCalled();
  });

  test("returns BILLING_REQUIRED_OUTAGE when vault is unavailable for gated account", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: false,
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
          membership_pass: "ump_abcdef123456",
        }),
      }),
    );

    expect(response.status).toBe(503);
    const payload = await response.json();
    expect(payload.code).toBe("BILLING_REQUIRED_OUTAGE");
    expect(payload.billing?.reason).toBe("vault_unavailable");
    expect(verifyMembershipPassMock).not.toHaveBeenCalled();
    expect(issueAppSessionTokenMock).not.toHaveBeenCalled();
  });

  test("returns BILLING_REQUIRED when membership pass is invalid for gated account", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
      passState: {
        valid: false,
        entitlementStatus: "inactive",
        provider: "stripe",
        status: "invalid",
        reason: "PASS_INVALID",
        effectiveUntil: null,
      },
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
          membership_pass: "ump_invalid1234567890",
        }),
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.code).toBe("BILLING_REQUIRED");
    expect(payload.billing?.provider).toBe("stripe");
    expect(payload.billing?.status).toBe("invalid");
    expect(payload.billing?.reason).toBe("pass_invalid");
    expect(payload.billing?.redirectTo).toContain("provider=stripe");
    expect(verifyMembershipPassMock).toHaveBeenCalledTimes(1);
    expect(issueAppSessionTokenMock).not.toHaveBeenCalled();
  });

  test("returns BILLING_REQUIRED when entitlement is inactive for gated account", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
      passState: {
        valid: true,
        entitlementStatus: "inactive",
        provider: "stripe",
        status: "inactive",
        reason: "entitlement_inactive",
        effectiveUntil: "2026-01-01T00:00:00.000Z",
      },
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
          membership_pass: "ump_inactive1234567890",
        }),
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.code).toBe("BILLING_REQUIRED");
    expect(payload.billing?.provider).toBe("stripe");
    expect(payload.billing?.status).toBe("inactive");
    expect(payload.billing?.reason).toBe("entitlement_inactive");
    expect(payload.billing?.effectiveUntil).toBe("2026-01-01T00:00:00.000Z");
    expect(verifyMembershipPassMock).toHaveBeenCalledTimes(1);
    expect(issueAppSessionTokenMock).not.toHaveBeenCalled();
  });

  test("returns BILLING_REQUIRED_OUTAGE when membership verification throws", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
    });
    verifyMembershipPassMock.mockRejectedValueOnce(new Error("vault unreachable"));

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
          membership_pass: "ump_error1234567890",
        }),
      }),
    );

    expect(response.status).toBe(503);
    const payload = await response.json();
    expect(payload.code).toBe("BILLING_REQUIRED_OUTAGE");
    expect(payload.billing?.reason).toBe("vault_unreachable");
    expect(verifyMembershipPassMock).toHaveBeenCalledTimes(1);
    expect(issueAppSessionTokenMock).not.toHaveBeenCalled();
  });

  test("issues session token for gated account when billing mode is free", async () => {
    process.env.BILLING_MODE = "free";
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.access_token).toBe("jwt_token");
    expect(verifyMembershipPassMock).not.toHaveBeenCalled();
    expect(issueAppSessionTokenMock).toHaveBeenCalledWith("acct_123", {
      ttlSeconds: 15 * 60,
    });
  });

  test("issues session token when pass is valid and entitlement is active", async () => {
    const { verifyMembershipPassMock, issueAppSessionTokenMock } = mockSharedAuthDependencies({
      gated: true,
      vaultEnabled: true,
      passState: {
        valid: true,
        entitlementStatus: "active",
        provider: "stripe",
        status: "active",
        reason: null,
        effectiveUntil: "2026-06-01T00:00:00.000Z",
      },
      sessionToken: {
        token: "jwt_active_token",
        payload: { exp: 1767225600 },
      },
    });

    const { handleVerifySessionChallenge } = await import("@/server/domains/auth-domain");

    const response = await handleVerifySessionChallenge(
      new Request("http://localhost/api/auth/session/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          challenge_id: "challenge_1",
          challenge: "challenge_payload",
          signature: "signature_payload",
          membership_pass: "ump_valid1234567890",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.access_token).toBe("jwt_active_token");
    expect(payload.account?.id).toBe("acct_123");
    expect(verifyMembershipPassMock).toHaveBeenCalledWith({
      membershipPass: "ump_valid1234567890",
      deviceBinding: "sign_pub_abc",
    });
    expect(issueAppSessionTokenMock).toHaveBeenCalledWith("acct_123", {
      ttlSeconds: 15 * 60,
    });
  });
});
