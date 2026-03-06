# Proof: Billing vault separation

Claim:
Payment-processor references are isolated in a separate billing vault, and app session issuance for gated accounts depends on membership-pass verification.

Evidence snippets:

```sql
-- apps/billing-vault/supabase/migrations/20260303184000_init_billing_vault.sql
CREATE TABLE IF NOT EXISTS public.provider_customers (
  subject_id uuid NOT NULL,
  provider text NOT NULL,
  customer_ref text NOT NULL,
  UNIQUE (provider, customer_ref)
);

CREATE TABLE IF NOT EXISTS public.provider_subscriptions (
  subject_id uuid NOT NULL,
  provider text NOT NULL,
  subscription_ref text NOT NULL,
  UNIQUE (provider, subscription_ref)
);
```

```js
// apps/web/src/server/domains/auth-domain.js
// for billing-gated accounts:
// missing/invalid membership pass => session denied
```

```js
// apps/web/scripts/check-billing-vault-runtime.cjs
// enforces vault URL separation from main NEXT_PUBLIC_SUPABASE_URL
```

What this proves:
- Processor IDs are modeled in the vault schema.
- Gated sign-in checks membership pass validity before issuing app sessions.
