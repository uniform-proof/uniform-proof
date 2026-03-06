# Proof: No auth/session IP persistence in app DB

Claim:
Auth/session records are designed without IP or fingerprint columns.

Evidence snippet:

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260305010000_hard_cut_app_sessions.sql
CREATE TABLE IF NOT EXISTS public.account_session_challenges (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  device_public_key text NOT NULL,
  signing_public_key text NOT NULL,
  challenge_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

What this proves:
- The active auth challenge table stores challenge and key references, not IP/fingerprint fields.
