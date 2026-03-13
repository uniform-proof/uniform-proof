describe("privacy hardening QA smoke", () => {
  const originalEnv = { ...process.env };

  function createAdminSupabaseNoSuppressionsMock() {
    return {
      from: jest.fn(() => {
        const query = {
          select: jest.fn(() => query),
          eq: jest.fn(() => query),
          in: jest.fn().mockResolvedValue({ data: [], error: null }),
          maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
        };
        return query;
      }),
    };
  }

  afterEach(() => {
    jest.clearAllMocks();
    jest.restoreAllMocks();
    jest.resetModules();
    process.env = { ...originalEnv };
  });

  test("signup payment path returns billing claim + recovery when vault is enabled", async () => {
    process.env.STRIPE_SECRET_KEY = "sk_test_123";
    process.env.STRIPE_B2C_PRICE_ID = "price_test_123";

    const listMock = jest.fn().mockResolvedValue({
      data: [
        {
          id: "sub_existing",
          status: "active",
          current_period_end: 1767225600,
        },
      ],
    });

    const updateMock = jest.fn().mockResolvedValue({});
    const createMock = jest.fn().mockResolvedValue({
      id: "sub_new",
      status: "active",
      current_period_end: 1767225600,
    });

    const stripeCtorMock = jest.fn().mockImplementation(() => ({
      subscriptions: {
        list: listMock,
        create: createMock,
      },
      customers: {
        update: updateMock,
      },
    }));

    const createStripeClaimAndRecoveryMock = jest.fn().mockResolvedValue({
      claimToken: "claim_123",
      recoveryCode: "URC-AAAA-BBBB",
    });

    jest.doMock("stripe", () => ({
      __esModule: true,
      default: stripeCtorMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createStripeClaimAndRecovery: createStripeClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/create-subscription/route");

    const response = await POST(
      new Request("http://localhost/api/payment/create-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customerId: "cus_123",
          paymentMethodId: "pm_123",
          email: "test@example.com",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.subscriptionId).toBe("sub_existing");
    expect(payload.billingClaimToken).toBe("claim_123");
    expect(payload.billingRecoveryCode).toBe("URC-AAAA-BBBB");
    expect(createStripeClaimAndRecoveryMock).toHaveBeenCalledTimes(1);
    expect(createMock).not.toHaveBeenCalled();
    expect(updateMock).not.toHaveBeenCalled();
  });

  test("signup payment path mints claim for existing subscription without payment method id", async () => {
    process.env.STRIPE_SECRET_KEY = "sk_test_123";
    process.env.STRIPE_B2C_PRICE_ID = "price_test_123";

    const listMock = jest.fn().mockResolvedValue({
      data: [
        {
          id: "sub_existing",
          status: "active",
          current_period_end: 1767225600,
        },
      ],
    });

    const updateMock = jest.fn().mockResolvedValue({});
    const createMock = jest.fn().mockResolvedValue({
      id: "sub_new",
      status: "active",
      current_period_end: 1767225600,
    });

    const stripeCtorMock = jest.fn().mockImplementation(() => ({
      subscriptions: {
        list: listMock,
        create: createMock,
      },
      customers: {
        update: updateMock,
      },
    }));

    const createStripeClaimAndRecoveryMock = jest.fn().mockResolvedValue({
      claimToken: "claim_existing",
      recoveryCode: "URC-EXIST-1234",
    });

    jest.doMock("stripe", () => ({
      __esModule: true,
      default: stripeCtorMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createStripeClaimAndRecovery: createStripeClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/create-subscription/route");

    const response = await POST(
      new Request("http://localhost/api/payment/create-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customerId: "cus_123",
          email: "test@example.com",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.subscriptionId).toBe("sub_existing");
    expect(payload.billingClaimToken).toBe("claim_existing");
    expect(payload.billingRecoveryCode).toBe("URC-EXIST-1234");
    expect(createStripeClaimAndRecoveryMock).toHaveBeenCalledTimes(1);
    expect(createMock).not.toHaveBeenCalled();
    expect(updateMock).not.toHaveBeenCalled();
  });

  test("signup payment path fails closed when billing vault claim generation fails", async () => {
    process.env.STRIPE_SECRET_KEY = "sk_test_123";
    process.env.STRIPE_B2C_PRICE_ID = "price_test_123";

    const listMock = jest.fn().mockResolvedValue({
      data: [
        {
          id: "sub_existing",
          status: "active",
          current_period_end: 1767225600,
        },
      ],
    });

    const updateMock = jest.fn().mockResolvedValue({});
    const createMock = jest.fn().mockResolvedValue({
      id: "sub_new",
      status: "active",
      current_period_end: 1767225600,
    });

    const stripeCtorMock = jest.fn().mockImplementation(() => ({
      subscriptions: {
        list: listMock,
        create: createMock,
      },
      customers: {
        update: updateMock,
      },
    }));

    const createStripeClaimAndRecoveryMock = jest
      .fn()
      .mockRejectedValue(new Error("vault unavailable"));

    jest.doMock("stripe", () => ({
      __esModule: true,
      default: stripeCtorMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createStripeClaimAndRecovery: createStripeClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/create-subscription/route");

    const response = await POST(
      new Request("http://localhost/api/payment/create-subscription", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customerId: "cus_123",
          paymentMethodId: "pm_123",
          email: "test@example.com",
        }),
      }),
    );

    expect(response.status).toBe(502);
    const payload = await response.json();
    expect(payload.error).toMatch(/secure billing claim/i);
    expect(createStripeClaimAndRecoveryMock).toHaveBeenCalledTimes(1);
    expect(createMock).not.toHaveBeenCalled();
    expect(updateMock).not.toHaveBeenCalled();
  });

  test("setup-intent returns resumable existing-subscription payload", async () => {
    process.env.STRIPE_SECRET_KEY = "sk_test_123";

    const customersListMock = jest.fn().mockResolvedValue({
      data: [{ id: "cus_existing", email: "test@example.com" }],
    });
    const subscriptionsListMock = jest.fn().mockImplementation(({ status }) => {
      if (status === "incomplete") {
        return Promise.resolve({ data: [] });
      }
      if (status === "active") {
        return Promise.resolve({
          data: [{ id: "sub_existing", status: "active" }],
        });
      }
      if (status === "trialing") {
        return Promise.resolve({ data: [] });
      }
      return Promise.resolve({ data: [] });
    });
    const setupIntentCreateMock = jest.fn();
    const customerCreateMock = jest.fn();

    const stripeCtorMock = jest.fn().mockImplementation(() => ({
      customers: {
        list: customersListMock,
        create: customerCreateMock,
      },
      subscriptions: {
        list: subscriptionsListMock,
      },
      setupIntents: {
        create: setupIntentCreateMock,
      },
    }));

    jest.doMock("stripe", () => ({
      __esModule: true,
      default: stripeCtorMock,
    }));

    const { POST } = await import("@/app/api/payment/setup-intent/route");

    const response = await POST(
      new Request("http://localhost/api/payment/setup-intent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "test@example.com",
          fullName: "Anonymous",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.hasActiveSubscription).toBe(true);
    expect(payload.customerId).toBe("cus_existing");
    expect(payload.subscriptionId).toBe("sub_existing");
    expect(setupIntentCreateMock).not.toHaveBeenCalled();
    expect(customerCreateMock).not.toHaveBeenCalled();
  });

  test("crypto verify path returns billing claim + recovery when invoice is settled", async () => {
    const createProviderClaimAndRecoveryMock = jest.fn().mockResolvedValue({
      claimToken: "claim_crypto_123",
      recoveryCode: "URC-CRYPTO-1234",
    });

    jest.doMock("@/lib/crypto-payment-provider", () => ({
      isCryptoBillingEnabled: jest.fn(() => true),
      getCryptoInvoice: jest.fn().mockResolvedValue({
        id: "inv_123",
        orderId: "order_123",
        status: "settled",
      }),
      getCryptoInvoicePaymentMethods: jest.fn().mockResolvedValue([]),
      isCryptoInvoiceSettled: jest.fn((status) => status === "settled"),
      getCryptoEntitlementUntilIso: jest.fn(() => "2026-04-04T00:00:00.000Z"),
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createProviderClaimAndRecovery: createProviderClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/crypto/verify-invoice/route");

    const response = await POST(
      new Request("http://localhost/api/payment/crypto/verify-invoice", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          invoiceId: "inv_123",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.settled).toBe(true);
    expect(payload.provider).toBe("crypto");
    expect(payload.subscriptionId).toBe("inv_123");
    expect(payload.billingClaimToken).toBe("claim_crypto_123");
    expect(payload.billingRecoveryCode).toBeUndefined();
    expect(createProviderClaimAndRecoveryMock).toHaveBeenCalledWith({
      provider: "crypto",
      customerId: "order_123",
      subscriptionId: "inv_123",
      status: "active",
      currentPeriodEnd: "2026-04-04T00:00:00.000Z",
    });
  });

  test("crypto verify path supports settled plan checkout sessions", async () => {
    const createProviderClaimAndRecoveryMock = jest.fn().mockResolvedValue({
      claimToken: "claim_crypto_checkout",
      recoveryCode: "URC-CHECK-1234",
    });

    jest.doMock("@/lib/crypto-payment-provider", () => ({
      isCryptoBillingEnabled: jest.fn(() => true),
      getCryptoPlanCheckout: jest.fn().mockResolvedValue({
        id: "checkout_123",
        invoiceId: "inv_plan_123",
        status: "settled",
        isExpired: false,
        planStarted: true,
        subscriber: {
          isActive: true,
          periodEnd: "2026-05-01T00:00:00.000Z",
          customerId: "cust_plan_123",
          customerEmail: "anon_1@uniform.local",
        },
      }),
      isCryptoPlanCheckoutSettled: jest.fn(() => true),
      getCryptoInvoice: jest.fn().mockResolvedValue({
        id: "inv_plan_123",
        status: "settled",
        orderId: "order_plan_123",
      }),
      getCryptoInvoicePaymentMethods: jest.fn().mockResolvedValue([]),
      isCryptoInvoiceSettled: jest.fn((status) => status === "settled"),
      getCryptoEntitlementUntilIso: jest.fn(() => "2026-04-04T00:00:00.000Z"),
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createProviderClaimAndRecovery: createProviderClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/crypto/verify-invoice/route");

    const response = await POST(
      new Request("http://localhost/api/payment/crypto/verify-invoice", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          checkoutId: "checkout_123",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.settled).toBe(true);
    expect(payload.mode).toBe("subscription_checkout");
    expect(payload.subscriptionId).toBe("inv_plan_123");
    expect(payload.billingClaimToken).toBe("claim_crypto_checkout");
    expect(payload.billingRecoveryCode).toBeUndefined();
    expect(createProviderClaimAndRecoveryMock).toHaveBeenCalledWith({
      provider: "crypto",
      customerId: "cust_plan_123",
      subscriptionId: "subscriber:cust_plan_123",
      status: "active",
      currentPeriodEnd: "2026-05-01T00:00:00.000Z",
    });
  });

  test("crypto verify path settles checkout when lightning invoice is settled but checkout is still pending", async () => {
    const createProviderClaimAndRecoveryMock = jest.fn().mockResolvedValue({
      claimToken: "claim_crypto_lightning",
      recoveryCode: "URC-LN-1234",
    });

    jest.doMock("@/lib/crypto-payment-provider", () => ({
      isCryptoBillingEnabled: jest.fn(() => true),
      getCryptoPlanCheckout: jest.fn().mockResolvedValue({
        id: "checkout_ln_123",
        invoiceId: "inv_ln_123",
        status: "pending_payment",
        isExpired: false,
        planStarted: false,
        subscriber: {
          isActive: false,
          periodEnd: null,
          customerId: "cust_ln_123",
          customerEmail: "anon_ln@uniform.local",
        },
      }),
      isCryptoPlanCheckoutSettled: jest.fn(() => false),
      getCryptoInvoice: jest.fn().mockResolvedValue({
        id: "inv_ln_123",
        status: "settled",
        orderId: "order_ln_123",
      }),
      getCryptoInvoicePaymentMethods: jest.fn().mockResolvedValue([
        {
          paymentMethodId: "BTC-LN",
          activated: true,
          destination: "lnbc1testinvoice",
          paymentLink: "lightning:lnbc1testinvoice",
          amount: "0.00001",
          due: "0.00001",
          currency: "BTC",
          copyValue: "lnbc1testinvoice",
        },
      ]),
      isCryptoInvoiceSettled: jest.fn((status) => status === "settled"),
      getCryptoEntitlementUntilIso: jest.fn(() => "2026-06-01T00:00:00.000Z"),
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createProviderClaimAndRecovery: createProviderClaimAndRecoveryMock,
    }));

    const { POST } = await import("@/app/api/payment/crypto/verify-invoice/route");

    const response = await POST(
      new Request("http://localhost/api/payment/crypto/verify-invoice", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          checkoutId: "checkout_ln_123",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.settled).toBe(true);
    expect(payload.mode).toBe("subscription_checkout");
    expect(payload.subscriptionId).toBe("inv_ln_123");
    expect(payload.status).toBe("settled");
    expect(payload.billingClaimToken).toBe("claim_crypto_lightning");
    expect(createProviderClaimAndRecoveryMock).toHaveBeenCalledWith({
      provider: "crypto",
      customerId: "cust_ln_123",
      subscriptionId: "subscriber:cust_ln_123",
      status: "active",
      currentPeriodEnd: "2026-06-01T00:00:00.000Z",
    });
  });

  test("register path requires billing claim token for Stripe when vault is enabled", async () => {
    const singleMock = jest.fn().mockResolvedValue({ data: null, error: null });
    const eqMock = jest.fn(() => ({ single: singleMock }));
    const selectMock = jest.fn(() => ({ eq: eqMock }));
    const fromMock = jest.fn(() => ({ select: selectMock }));

    const getSupabaseAdminClientMock = jest.fn(() => ({
      from: fromMock,
    }));

    const consumeBillingClaimTokenMock = jest.fn();

    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: getSupabaseAdminClientMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      consumeBillingClaimToken: consumeBillingClaimTokenMock,
      syncMobileSubscriptionToVault: jest.fn(),
    }));

    const { POST } = await import("@/app/auth/register/route");

    const body = new FormData();
    body.append("handle", "strict_claim_user");
    body.append("publicKey", "enc_pub");
    body.append("signingPublicKey", "sign_pub");
    body.append("organization", "new-b2c-org");
    body.append("organizationName", "Test Employer");
    body.append("b2cOrganizationData", JSON.stringify({ name: "Test Employer" }));
    body.append("birthday", "1990-01-01");
    body.append("age_attestation", "true");
    body.append("policy_version", "2026-03-11-16plus-v1");
    body.append("iap_provider", "stripe");
    body.append("iap_transaction_id", "sub_test_123");

    const response = await POST(
      new Request("http://localhost/auth/register", {
        method: "POST",
        body,
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.error).toMatch(/secure payment claim missing/i);
    expect(consumeBillingClaimTokenMock).not.toHaveBeenCalled();
  });

  test("register path requires billing claim token for crypto when vault is enabled", async () => {
    const singleMock = jest.fn().mockResolvedValue({ data: null, error: null });
    const eqMock = jest.fn(() => ({ single: singleMock }));
    const selectMock = jest.fn(() => ({ eq: eqMock }));
    const fromMock = jest.fn(() => ({ select: selectMock }));

    const getSupabaseAdminClientMock = jest.fn(() => ({
      from: fromMock,
    }));

    const consumeBillingClaimTokenMock = jest.fn();

    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: getSupabaseAdminClientMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      consumeBillingClaimToken: consumeBillingClaimTokenMock,
      syncMobileSubscriptionToVault: jest.fn(),
    }));

    const { POST } = await import("@/app/auth/register/route");

    const body = new FormData();
    body.append("handle", "strict_claim_crypto");
    body.append("publicKey", "enc_pub");
    body.append("signingPublicKey", "sign_pub");
    body.append("organization", "new-b2c-org");
    body.append("organizationName", "Crypto Employer");
    body.append("b2cOrganizationData", JSON.stringify({ name: "Crypto Employer" }));
    body.append("birthday", "1990-01-01");
    body.append("age_attestation", "true");
    body.append("policy_version", "2026-03-11-16plus-v1");
    body.append("iap_provider", "crypto");
    body.append("iap_transaction_id", "inv_123");

    const response = await POST(
      new Request("http://localhost/auth/register", {
        method: "POST",
        body,
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.error).toMatch(/secure payment claim missing/i);
    expect(consumeBillingClaimTokenMock).not.toHaveBeenCalled();
  });

  test("register enforces Stripe claim for b2c flag even without b2c org payload", async () => {
    const singleMock = jest.fn().mockResolvedValue({ data: null, error: null });
    const eqMock = jest.fn(() => ({ single: singleMock }));
    const selectMock = jest.fn(() => ({ eq: eqMock }));
    const fromMock = jest.fn(() => ({ select: selectMock }));

    const getSupabaseAdminClientMock = jest.fn(() => ({
      from: fromMock,
    }));

    const consumeBillingClaimTokenMock = jest.fn();

    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: getSupabaseAdminClientMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      consumeBillingClaimToken: consumeBillingClaimTokenMock,
      syncMobileSubscriptionToVault: jest.fn(),
    }));

    const { POST } = await import("@/app/auth/register/route");

    const body = new FormData();
    body.append("handle", "strict_claim_flag");
    body.append("publicKey", "enc_pub");
    body.append("signingPublicKey", "sign_pub");
    body.append("organization", "existing-employer-id");
    body.append("organizationName", "Existing Employer");
    body.append("birthday", "1990-01-01");
    body.append("age_attestation", "true");
    body.append("policy_version", "2026-03-11-16plus-v1");
    body.append("is_b2c_signup", "true");
    body.append("iap_provider", "stripe");
    body.append("iap_transaction_id", "sub_test_456");

    const response = await POST(
      new Request("http://localhost/auth/register", {
        method: "POST",
        body,
      }),
    );

    expect(response.status).toBe(402);
    const payload = await response.json();
    expect(payload.error).toMatch(/secure payment claim missing/i);
    expect(consumeBillingClaimTokenMock).not.toHaveBeenCalled();
  });

  test("recovery-code portal path returns Stripe portal URL", async () => {
    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_123",
    });
    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({
      from: jest.fn((table) => {
        if (table === "account_devices") {
          return {
            select: jest.fn(() => ({
              eq: jest.fn(() => ({
                order: jest.fn().mockResolvedValue({
                  data: [{ device_label: "web-desktop", created_at: "2026-03-01T00:00:00.000Z" }],
                }),
              })),
            })),
          };
        }

        throw new Error(`Unexpected table: ${table}`);
      }),
    });
    const createStripePortalByRecoveryCodeMock = jest.fn().mockResolvedValue(
      "https://billing.stripe.test/portal-session",
    );

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));

    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));

    jest.doMock("@/lib/billing-vault-client", () => ({
      isBillingVaultEnabled: jest.fn(() => true),
      createStripePortalByRecoveryCode: createStripePortalByRecoveryCodeMock,
    }));

    const { handleCreateCustomerPortal } = await import("@/server/domains/billing-domain");

    const response = await handleCreateCustomerPortal(
      new Request("http://localhost/api/app/customer-portal", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          recoveryCode: "URC-AAAA-BBBB",
          returnUrl: "http://localhost/app/settings/billing",
        }),
      }),
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.url).toBe("https://billing.stripe.test/portal-session");
    expect(createStripePortalByRecoveryCodeMock).toHaveBeenCalledWith({
      recoveryCode: "URC-AAAA-BBBB",
      returnUrl: "http://localhost/app/settings/billing",
    });
  });

  test("anonymous card receipt token + submission flow uses RPC endpoints", async () => {
    process.env.ANON_CARD_RECEIPTS = "true";

    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_123",
    });
    const rpcMock = jest
      .fn()
      .mockResolvedValueOnce({
        data: [{ token: "receipt-token-123", expires_at: "2026-03-03T01:00:00.000Z" }],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [{ id: "receipt-id-1", created_at: "2026-03-03T00:00:00.000Z" }],
        error: null,
      });

    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({
      rpc: rpcMock,
    });

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));
    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));

    const { handleIssueCardReceiptToken, handleCreateCardReceipt } = await import(
      "@/server/domains/account-domain"
    );

    const tokenResponse = await handleIssueCardReceiptToken(
      new Request("http://localhost/api/card-receipt/token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          location_id: "10000000-0000-0000-0000-000000000001",
        }),
      }),
    );
    expect(tokenResponse.status).toBe(200);
    const tokenPayload = await tokenResponse.json();
    expect(tokenPayload.token).toBe("receipt-token-123");
    expect(rpcMock).toHaveBeenNthCalledWith(1, "issue_card_receipt_submission_token", {
      p_location_id: "10000000-0000-0000-0000-000000000001",
      p_ttl_seconds: 900,
    });

    const receiptResponse = await handleCreateCardReceipt(
      new Request("http://localhost/api/card-receipt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          location_id: "10000000-0000-0000-0000-000000000001",
          receipt_hash: "hash-1",
          nullifier_hash: "nullifier-1",
          submission_token: "receipt-token-123",
        }),
      }),
    );

    expect(receiptResponse.status).toBe(200);
    const receiptPayload = await receiptResponse.json();
    expect(receiptPayload.id).toBe("receipt-id-1");
    expect(rpcMock).toHaveBeenNthCalledWith(2, "submit_card_receipt_with_token", {
      p_location_id: "10000000-0000-0000-0000-000000000001",
      p_receipt_hash: "hash-1",
      p_nullifier_hash: "nullifier-1",
      p_submission_token: "receipt-token-123",
    });
  });

  test("push wake-only mode strips metadata down to action + ref hints", async () => {
    process.env.PUSH_WAKE_ONLY = "true";

    const supabaseMock = {
      from: jest.fn((table) => {
        if (table === "user_notification_preferences") {
          return {
            select: jest.fn(() => ({
              eq: jest.fn(() => ({
                in: jest.fn().mockResolvedValue({
                  data: null,
                  error: { code: "42P01" },
                }),
              })),
            })),
          };
        }

        if (table === "device_push_tokens") {
          return {
            select: jest.fn(() => ({
              in: jest.fn(() => ({
                is: jest.fn().mockResolvedValue({
                  data: [
                    {
                      id: "token-row-1",
                      account_id: "acct_123",
                      push_token: "ExponentPushToken[abc]",
                    },
                  ],
                  error: null,
                }),
              })),
            })),
            update: jest.fn(() => ({
              in: jest.fn().mockResolvedValue({ error: null }),
            })),
          };
        }

        throw new Error(`Unexpected table: ${table}`);
      }),
    };

    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: jest.fn(() => supabaseMock),
    }));

    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: [{ status: "ok" }],
      }),
    });
    global.fetch = fetchMock;

    const { sendPushToAccounts } = await import("@/lib/expo-push");

    const result = await sendPushToAccounts({
      accountIds: ["acct_123"],
      title: "New message",
      body: "You got a new message",
      data: {
        source_type: "message",
        source_id: "msg_123",
        tenantId: "tenant_123",
        source_metadata: {
          conversation_id: "thread_123",
          message_id: "msg_123",
          context_id: "ctx_123",
          sender_handle: "should-not-leak",
        },
      },
      preference: {
        sourceType: "message",
        tenantId: "tenant_123",
      },
    });

    expect(result.success).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [, options] = fetchMock.mock.calls[0];
    const sentBatch = JSON.parse(options.body);
    expect(sentBatch).toHaveLength(1);

    const sentPayload = sentBatch[0].data;
    expect(sentPayload).toEqual({
      source_type: "message",
      source_id: "msg_123",
      ref_hint: {
        message_id: "msg_123",
        conversation_id: "thread_123",
        context_id: "ctx_123",
      },
      wake_only: true,
    });
    expect(sentPayload.tenantId).toBeUndefined();
    expect(sentPayload.source_metadata).toBeUndefined();
  });

  test("actor mode redacts author_account_id in context post responses", async () => {
    process.env.ACTOR_ID_MODE = "true";

    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_me",
    });
    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({});

    const getContextMembershipMock = jest.fn().mockResolvedValue({
      data: { context_id: "ctx_1" },
    });
    const getPostsByContextIdsMock = jest.fn().mockResolvedValue({
      data: [
        {
          id: "post_1",
          ciphertext: "ciphertext",
          ciphertext_version: 2,
          author_signature: null,
          key_epoch: 1,
          author_account_id: "acct_other",
          actor_id: "actor_other",
          post_type: "text",
          image_url: null,
          poll_options: null,
          poll_votes: {},
          poll_expires_at: null,
          like_count: 0,
          comment_count: 0,
          share_count: 0,
          created_at: "2026-03-03T00:00:00.000Z",
          context_id: "ctx_1",
          accounts: { handle: "worker_one" },
        },
      ],
      error: null,
    });
    const getPostLikesForAccountMock = jest.fn().mockResolvedValue({ data: [] });
    const getBlockedAccountRowsMock = jest.fn().mockResolvedValue({ data: [] });

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));
    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));
    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: jest.fn(() => createAdminSupabaseNoSuppressionsMock()),
    }));
    jest.doMock("@/server/repositories/contexts-repository", () => ({
      getContextMembership: getContextMembershipMock,
      getPostsByContextIds: getPostsByContextIdsMock,
      getPostLikesForAccount: getPostLikesForAccountMock,
      getBlockedAccountRows: getBlockedAccountRowsMock,
    }));
    jest.doMock("@/server/cache/runtime-cache", () => ({
      getCachedValue: jest.fn().mockResolvedValue(null),
      invalidateCacheByPrefixes: jest.fn().mockResolvedValue(undefined),
      makeCacheKey: jest.fn(() => "cache:key"),
      setCachedValue: jest.fn().mockResolvedValue(undefined),
    }));
    jest.doMock("@/server/e2ee/envelope", () => ({
      requireE2eeCapability: jest.fn(() => null),
      validateEnvelopeCiphertext: jest.fn(),
    }));
    jest.doMock("@/lib/expo-push", () => ({
      sendPushToAccounts: jest.fn().mockResolvedValue({ success: true }),
    }));
    jest.doMock("@/server/repositories/account-devices-repository", () => ({
      getLatestDeviceKeysForAccountIds: jest.fn().mockResolvedValue({ data: [], error: null }),
    }));
    jest.doMock("@/server/identity/actor-identity", () => ({
      actorIdentityKey: jest.fn((ctx, acct) => `${ctx}:${acct}`),
      getOrCreateContextActorIdentity: jest.fn().mockResolvedValue({
        actorId: "actor_me",
        displayHandle: "anon_me",
      }),
      isActorIdModeEnabled: jest.fn(() => true),
      resolveContextAccountIdsByActorPairs: jest
        .fn()
        .mockResolvedValue(new Map([["ctx_1:actor_other", "acct_other"]])),
      resolveContextAccountIdByActorId: jest.fn().mockResolvedValue("acct_other"),
      resolveContextActorIdentityMap: jest.fn().mockImplementation(async (_supabase, pairs) => {
        if (!Array.isArray(pairs) || pairs.length === 0) {
          return new Map();
        }

        const includesAuthor = pairs.some(
          (pair) => String(pair?.account_id || "").trim() === "acct_other",
        );
        if (!includesAuthor) {
          return new Map();
        }

        return new Map([["ctx_1:acct_other", { actor_id: "actor_other", display_handle: "anon_worker" }]]);
      }),
    }));

    const { handleGetContextPosts } = await import("@/server/domains/contexts-domain");

    const response = await handleGetContextPosts(
      new Request("http://localhost/api/contexts/ctx_1/posts"),
      "ctx_1",
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.posts).toHaveLength(1);
    expect(payload.posts[0]).not.toHaveProperty("author_account_id");
    expect(payload.posts[0].author_actor_id).toBe("actor_other");
    expect(payload.posts[0].author_display_handle).toBe("anon_worker");
  });

  test("actor mode does not fall back to account id for single post actor identity", async () => {
    process.env.ACTOR_ID_MODE = "true";

    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_me",
    });
    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({});
    const getContextMembershipMock = jest.fn().mockResolvedValue({
      data: { context_id: "ctx_1" },
    });
    const getDetailedPostByContextAndIdMock = jest.fn().mockResolvedValue({
      data: {
        id: "post_1",
        ciphertext: "ciphertext",
        ciphertext_version: 2,
        author_signature: null,
        key_epoch: 1,
        author_account_id: "acct_other",
        actor_id: null,
        post_type: "text",
        image_url: null,
        poll_options: null,
        poll_votes: {},
        poll_expires_at: null,
        like_count: 0,
        comment_count: 0,
        share_count: 0,
        created_at: "2026-03-03T00:00:00.000Z",
        context_id: "ctx_1",
        accounts: { handle: "worker_one" },
      },
      error: null,
    });
    const getPostLikeByAccountMock = jest.fn().mockResolvedValue({ data: null });

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));
    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));
    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: jest.fn(() => createAdminSupabaseNoSuppressionsMock()),
    }));
    jest.doMock("@/server/repositories/contexts-repository", () => ({
      getContextMembership: getContextMembershipMock,
      getDetailedPostByContextAndId: getDetailedPostByContextAndIdMock,
      getPostLikeByAccount: getPostLikeByAccountMock,
    }));
    jest.doMock("@/server/cache/runtime-cache", () => ({
      getCachedValue: jest.fn().mockResolvedValue(null),
      invalidateCacheByPrefixes: jest.fn().mockResolvedValue(undefined),
      makeCacheKey: jest.fn(() => "cache:key"),
      setCachedValue: jest.fn().mockResolvedValue(undefined),
    }));
    jest.doMock("@/server/e2ee/envelope", () => ({
      requireE2eeCapability: jest.fn(() => null),
      validateEnvelopeCiphertext: jest.fn(),
    }));
    jest.doMock("@/lib/expo-push", () => ({
      sendPushToAccounts: jest.fn().mockResolvedValue({ success: true }),
    }));
    jest.doMock("@/server/repositories/account-devices-repository", () => ({
      getLatestDeviceKeysForAccountIds: jest.fn().mockResolvedValue({ data: [], error: null }),
    }));
    jest.doMock("@/server/identity/actor-identity", () => ({
      actorIdentityKey: jest.fn((ctx, acct) => `${ctx}:${acct}`),
      getOrCreateContextActorIdentity: jest.fn().mockResolvedValue({
        actorId: "actor_me",
        displayHandle: "anon_me",
      }),
      isActorIdModeEnabled: jest.fn(() => true),
      resolveContextAccountIdsByActorPairs: jest.fn().mockResolvedValue(new Map()),
      resolveContextAccountIdByActorId: jest.fn().mockResolvedValue(null),
      resolveContextActorIdentityMap: jest.fn().mockResolvedValue(new Map()),
    }));

    const { handleGetContextPost } = await import("@/server/domains/contexts-domain");

    const response = await handleGetContextPost(
      new Request("http://localhost/api/contexts/ctx_1/posts/post_1"),
      "ctx_1",
      "post_1",
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.post).not.toHaveProperty("author_account_id");
    expect(payload.post.author_actor_id).toBeNull();
    expect(payload.post.author_display_handle).toBe("unknown");
    expect(getDetailedPostByContextAndIdMock).toHaveBeenCalledTimes(1);
  });

  test("context key bulk upsert accepts actor_id entries without account_id", async () => {
    process.env.ACTOR_ID_MODE = "true";

    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_requester",
    });
    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({});
    const adminSupabaseClient = {
      from: jest.fn(() => ({
        update: jest.fn(() => ({
          eq: jest.fn().mockResolvedValue({ error: null }),
        })),
      })),
    };
    const getContextMembershipMock = jest.fn().mockResolvedValue({
      data: { context_id: "ctx_1" },
    });
    const getContextMembersByAccountIdsMock = jest.fn().mockResolvedValue({
      data: [{ account_id: "acct_target" }],
    });
    const upsertContextKeyMock = jest.fn().mockResolvedValue({ error: null });
    const resolveContextAccountIdsByActorIdsMock = jest
      .fn()
      .mockResolvedValue(new Map([["actor_target", "acct_target"]]));

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));
    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));
    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: jest.fn(() => adminSupabaseClient),
    }));
    jest.doMock("@/server/repositories/contexts-repository", () => ({
      getContextMembership: getContextMembershipMock,
      getContextMembersByAccountIds: getContextMembersByAccountIdsMock,
      upsertContextKey: upsertContextKeyMock,
    }));
    jest.doMock("@/server/cache/runtime-cache", () => ({
      getCachedValue: jest.fn().mockResolvedValue(null),
      invalidateCacheByPrefixes: jest.fn().mockResolvedValue(undefined),
      makeCacheKey: jest.fn(() => "cache:key"),
      setCachedValue: jest.fn().mockResolvedValue(undefined),
    }));
    jest.doMock("@/server/e2ee/envelope", () => ({
      requireE2eeCapability: jest.fn(() => null),
      validateEnvelopeCiphertext: jest.fn(),
    }));
    jest.doMock("@/lib/expo-push", () => ({
      sendPushToAccounts: jest.fn().mockResolvedValue({ success: true }),
    }));
    jest.doMock("@/server/repositories/account-devices-repository", () => ({
      getLatestDeviceKeysForAccountIds: jest.fn().mockResolvedValue({ data: [], error: null }),
    }));
    jest.doMock("@/server/identity/actor-identity", () => ({
      actorIdentityKey: jest.fn((ctx, acct) => `${ctx}:${acct}`),
      getOrCreateContextActorIdentity: jest.fn().mockResolvedValue({
        actorId: "actor_requester",
        displayHandle: "anon_me",
      }),
      isActorIdModeEnabled: jest.fn(() => true),
      resolveContextAccountIdsByActorPairs: jest.fn().mockResolvedValue(new Map()),
      resolveContextAccountIdsByActorIds: resolveContextAccountIdsByActorIdsMock,
      resolveContextAccountIdByActorId: jest.fn(),
      resolveContextActorIdentityMap: jest.fn().mockResolvedValue(new Map()),
    }));

    const { handleBulkUpsertContextKeys } = await import("@/server/domains/contexts-domain");

    const response = await handleBulkUpsertContextKeys(
      new Request("http://localhost/api/contexts/ctx_1/keys/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          epoch: 2,
          entries: [
            {
              actor_id: "actor_target",
              encrypted_context_key: "wrapped-key",
            },
          ],
        }),
      }),
      "ctx_1",
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.success).toBe(true);
    expect(payload.count).toBe(1);
    expect(payload.epoch).toBe(2);
    expect(resolveContextAccountIdsByActorIdsMock).toHaveBeenCalledWith(
      adminSupabaseClient,
      "ctx_1",
      ["actor_target"],
    );
    expect(upsertContextKeyMock).toHaveBeenCalledWith(
      adminSupabaseClient,
      expect.objectContaining({
        context_id: "ctx_1",
        account_id: "acct_target",
        epoch: 2,
        encrypted_context_key: "wrapped-key",
      }),
    );
  });

  test("context key lookup supports all=1 key history for member", async () => {
    process.env.ACTOR_ID_MODE = "true";

    const getAuthFromRequestMock = jest.fn().mockResolvedValue({
      accountId: "acct_member",
    });
    const getSupabaseClientForRequestMock = jest.fn().mockResolvedValue({});
    const getContextMembershipMock = jest.fn().mockResolvedValue({
      data: { context_id: "ctx_1" },
    });
    const getAllContextKeysForMemberMock = jest.fn().mockResolvedValue({
      data: [
        { encrypted_context_key: "wrapped-epoch-3", epoch: 3 },
        { encrypted_context_key: "wrapped-epoch-2", epoch: 2 },
        { encrypted_context_key: "wrapped-epoch-1", epoch: 1 },
      ],
      error: null,
    });

    jest.doMock("@/lib/auth", () => ({
      getAuthFromRequest: getAuthFromRequestMock,
    }));
    jest.doMock("@/supabase-utils/serverClient", () => ({
      getSupabaseClientForRequest: getSupabaseClientForRequestMock,
    }));
    jest.doMock("@/supabase-utils/adminClient", () => ({
      getSupabaseAdminClient: jest.fn(() => createAdminSupabaseNoSuppressionsMock()),
    }));
    jest.doMock("@/server/repositories/contexts-repository", () => ({
      getContextMembership: getContextMembershipMock,
      getAllContextKeysForMember: getAllContextKeysForMemberMock,
    }));
    jest.doMock("@/server/cache/runtime-cache", () => ({
      getCachedValue: jest.fn().mockResolvedValue(null),
      invalidateCacheByPrefixes: jest.fn().mockResolvedValue(undefined),
      makeCacheKey: jest.fn(() => "cache:key"),
      setCachedValue: jest.fn().mockResolvedValue(undefined),
    }));
    jest.doMock("@/server/e2ee/envelope", () => ({
      requireE2eeCapability: jest.fn(() => null),
      validateEnvelopeCiphertext: jest.fn(),
    }));
    jest.doMock("@/lib/expo-push", () => ({
      sendPushToAccounts: jest.fn().mockResolvedValue({ success: true }),
    }));
    jest.doMock("@/server/repositories/account-devices-repository", () => ({
      getLatestDeviceKeysForAccountIds: jest.fn().mockResolvedValue({ data: [], error: null }),
    }));
    jest.doMock("@/server/identity/actor-identity", () => ({
      actorIdentityKey: jest.fn((ctx, acct) => `${ctx}:${acct}`),
      getOrCreateContextActorIdentity: jest.fn().mockResolvedValue({
        actorId: "actor_member",
        displayHandle: "anon_member",
      }),
      isActorIdModeEnabled: jest.fn(() => true),
      resolveContextAccountIdsByActorPairs: jest.fn().mockResolvedValue(new Map()),
      resolveContextAccountIdsByActorIds: jest.fn().mockResolvedValue(new Map()),
      resolveContextAccountIdByActorId: jest.fn(),
      resolveContextActorIdentityMap: jest.fn().mockResolvedValue(new Map()),
    }));

    const { handleGetContextKey } = await import("@/server/domains/contexts-domain");

    const response = await handleGetContextKey(
      new Request("http://localhost/api/contexts/ctx_1/keys?all=1"),
      "ctx_1",
    );

    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.keys).toEqual([
      { encrypted_context_key: "wrapped-epoch-3", epoch: 3 },
      { encrypted_context_key: "wrapped-epoch-2", epoch: 2 },
      { encrypted_context_key: "wrapped-epoch-1", epoch: 1 },
    ]);
    expect(getAllContextKeysForMemberMock).toHaveBeenCalledWith({}, "ctx_1", "acct_member");
  });
});
