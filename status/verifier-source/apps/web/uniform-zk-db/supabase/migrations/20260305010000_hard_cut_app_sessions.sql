BEGIN;

CREATE TABLE IF NOT EXISTS public.account_session_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  device_public_key text NOT NULL,
  signing_public_key text NOT NULL,
  challenge_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_session_challenges_account
  ON public.account_session_challenges(account_id);

CREATE INDEX IF NOT EXISTS idx_account_session_challenges_expires
  ON public.account_session_challenges(expires_at);

REVOKE ALL ON TABLE public.account_session_challenges FROM anon;
REVOKE ALL ON TABLE public.account_session_challenges FROM authenticated;
GRANT ALL ON TABLE public.account_session_challenges TO service_role;

ALTER TABLE public.account_session_challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS account_session_challenges_service_role_only
  ON public.account_session_challenges;
CREATE POLICY account_session_challenges_service_role_only
  ON public.account_session_challenges
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.current_account_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claim text;
BEGIN
  v_claim := NULLIF(current_setting('request.jwt.claim.account_id', true), '');
  IF v_claim IS NULL THEN
    v_claim := NULLIF(current_setting('request.jwt.claim.sub', true), '');
  END IF;

  IF v_claim IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    RETURN v_claim::uuid;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_account_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_account_id() TO service_role;

DROP POLICY IF EXISTS account_auth_identities_select_self ON public.account_auth_identities;
DROP TABLE IF EXISTS public.account_auth_identities;

COMMIT;
