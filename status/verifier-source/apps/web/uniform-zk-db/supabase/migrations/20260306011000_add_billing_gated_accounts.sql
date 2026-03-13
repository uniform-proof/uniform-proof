BEGIN;

CREATE TABLE IF NOT EXISTS public.billing_gated_accounts (
  account_id uuid PRIMARY KEY REFERENCES public.accounts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.billing_gated_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_gated_accounts FROM anon;
REVOKE ALL ON TABLE public.billing_gated_accounts FROM authenticated;
GRANT ALL ON TABLE public.billing_gated_accounts TO service_role;

INSERT INTO public.billing_gated_accounts (account_id)
SELECT DISTINCT account_id
FROM public.account_subscription_states
ON CONFLICT (account_id) DO NOTHING;

COMMIT;
