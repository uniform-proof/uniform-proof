# Proof: No auth/session IP persistence in app DB (and signup auth data minimization)

Claim:
Auth/session and account-auth records are structured without stored IP/fingerprint fields, and signup account records are created without personal identity fields.

Evidence snippets:

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260222203341_create_zk_schema.sql:11-27
CREATE TABLE accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handle text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE account_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_public_key text NOT NULL,
  signing_public_key text NOT NULL,
  device_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz
);
```

```js
// apps/web/src/app/auth/register/route.js:175-182,405-410,440-446
const { handle, publicKey, signingPublicKey } = formDataObj;
if (!handle) return NextResponse.json({ error: "Handle is required" }, { status: 400 });
if (!publicKey || !signingPublicKey) {
  return NextResponse.json({ error: "Public keys are required" }, { status: 400 });
}

await supabase.from("accounts").insert({
  handle: handleLower,
  status: "active",
});

await supabase.from("account_devices").insert({
  account_id: account.id,
  device_public_key: publicKey.toString(),
  signing_public_key: signingPublicKey.toString(),
  device_label: formDataObj.signup_platform || "mobile",
});
```

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260305010000_hard_cut_app_sessions.sql:3-12,65-66
CREATE TABLE IF NOT EXISTS public.account_session_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  device_public_key text NOT NULL,
  signing_public_key text NOT NULL,
  challenge_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

DROP TABLE IF EXISTS public.account_auth_identities;
```

```js
// apps/web/src/server/auth/session-challenge.js:99-107
await supabase
  .from("account_session_challenges")
  .insert({
    account_id: account.id,
    device_public_key: devicePublicKey,
    signing_public_key: signingPublicKey,
    challenge_hash: sha256Hex(challenge),
    expires_at: expiresAt,
  });
```

```js
// apps/web/src/server/domains/auth-domain.js:254-257
const body = await request.json().catch(() => ({}));
const challengeId = String(body?.challenge_id || body?.challengeId || "").trim();
const challenge = String(body?.challenge || "").trim();
const signature = String(body?.signature || "").trim();
```

```toml
# apps/web/uniform-zk-db/supabase/config.toml:172,174,207,245
[auth]
enable_signup = false
enable_anonymous_sign_ins = false

[auth.email]
enable_signup = false

[auth.sms]
enable_signup = false
```

```bash
# Verification command run March 7, 2026
npm run check:auth-metadata-guardrails --workspace=apps/web
# Output:
# [auth-metadata-guardrails] OK
```

What this proves:
- Signup auth records use `handle` + device keys, not real-name/personal-email/phone columns.
- Session challenge rows store key/challenge metadata without IP/fingerprint columns.
- Legacy auth identity coupling table is explicitly removed.
- Built-in Supabase email/sms signup paths are disabled in this runtime profile.

Scope note:
- This proof is for application-controlled runtime records.
- It does not claim anything about external provider/network edge logs outside Uniform app DB.

Last verified against code: March 7, 2026.
