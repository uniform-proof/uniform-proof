# Proof: Billing vault separation

Claim:
Payment-processor identifiers are stored in a separate billing-vault DB, while app session issuance for gated accounts requires valid membership-pass verification.

Evidence snippets:

```sql
-- apps/billing-vault/supabase/migrations/20260303184000_init_billing_vault.sql:24-46
CREATE TABLE IF NOT EXISTS public.provider_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES public.billing_subjects(id) ON DELETE CASCADE,
  provider text NOT NULL,
  customer_ref text NOT NULL,
  UNIQUE (provider, customer_ref)
);

CREATE TABLE IF NOT EXISTS public.provider_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES public.billing_subjects(id) ON DELETE CASCADE,
  provider text NOT NULL,
  subscription_ref text NOT NULL,
  status text NOT NULL DEFAULT 'none',
  UNIQUE (provider, subscription_ref)
);
```

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260306011000_add_billing_gated_accounts.sql:3-6
CREATE TABLE IF NOT EXISTS public.billing_gated_accounts (
  account_id uuid PRIMARY KEY REFERENCES public.accounts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260306012000_drop_account_subscription_states_hard_cut.sql:3
DROP TABLE IF EXISTS public.account_subscription_states CASCADE;
```

```js
// apps/web/src/server/domains/auth-domain.js:265-341
const isGated = await isBillingGatedAccount(supabase, verified.account.id);
if (isGated) {
  if (!vaultAvailable) {
    throw createBillingError(503, "BILLING_REQUIRED_OUTAGE", "Billing verification is temporarily unavailable.");
  }

  const membershipPass = String(
    body?.membership_pass || body?.membershipPass || request.headers.get("x-membership-pass") || "",
  ).trim();
  if (!membershipPass) {
    throw createBillingError(402, "BILLING_REQUIRED", "Active billing entitlement is required before sign-in.");
  }

  passState = await verifyMembershipPass({
    membershipPass,
    deviceBinding: verified.signingPublicKey || "",
  });

  if (!passState?.valid || passState?.entitlementStatus !== "active") {
    throw createBillingError(402, "BILLING_REQUIRED", "Active billing entitlement is required before sign-in.");
  }
}
```

```js
// apps/web/src/lib/billing-vault-client.js:900-944,948-963
const passHash = sha256Hex(normalizedPass);
const { data: passRow } = await supabase
  .from("membership_passes")
  .select("subject_id, expires_at, revoked_at, device_binding_hash")
  .eq("pass_hash", passHash)
  .maybeSingle();

if (!passRow?.subject_id || passRow.revoked_at) {
  return { valid: false, entitlementStatus: "inactive", reason: "PASS_INVALID" };
}

if (expectedBindingHash !== String(passRow.device_binding_hash || "")) {
  return { valid: false, entitlementStatus: "inactive", reason: "PASS_BINDING_MISMATCH" };
}

return {
  valid: true,
  entitlementStatus: hasActiveEntitlement ? "active" : "inactive",
  provider: lifecycle.provider,
  status: lifecycle.status,
};
```

```js
// apps/web/scripts/check-billing-vault-runtime.cjs:34-37
const mainSupabaseUrl = String(process.env.NEXT_PUBLIC_SUPABASE_URL || "").trim();
if (vaultUrl && mainSupabaseUrl && vaultUrl === mainSupabaseUrl) {
  failures.push("BILLING_VAULT_SUPABASE_URL must be separate from NEXT_PUBLIC_SUPABASE_URL");
}
```

```bash
# Verification command run March 7, 2026
npm run test --workspace=apps/web -- src/server/domains/__tests__/auth-domain-billing-gate.test.js
# Result: PASS (3 tests, 0 failures)
```

What this proves:
- Processor customer/subscription refs live in billing-vault tables keyed by `subject_id`.
- Main app runtime uses account-level gating marker and pass verification, not direct processor refs.
- Session issuance is denied for missing/invalid/inactive/outage pass states.
- Vault endpoint separation is enforced by runtime guardrail check.

Last verified against code: March 7, 2026.
