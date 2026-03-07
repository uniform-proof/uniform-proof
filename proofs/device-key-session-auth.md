# Proof: Device-key session authentication

Claim:
Session setup requires a registered device signing key + signed one-time challenge, then issues a short-lived app JWT.

Evidence snippets:

```js
// apps/web/src/server/auth/session-challenge.js:60-87
async function requireMatchingDevice(supabase, accountId, devicePublicKey, signingPublicKey) {
  const { data, error } = await supabase
    .from("account_devices")
    .select("id")
    .eq("account_id", accountId)
    .eq("device_public_key", normalizedDeviceKey)
    .eq("signing_public_key", normalizedSigningKey)
    .maybeSingle();

  if (!data?.id) {
    throw createHttpError(403, "DEVICE_NOT_REGISTERED", "Device key is not registered");
  }
}
```

```js
// apps/web/src/server/auth/session-challenge.js:4,96-107
const CHALLENGE_TTL_SECONDS = 120;

const challenge = generateChallenge();
const expiresAt = new Date(Date.now() + CHALLENGE_TTL_SECONDS * 1000).toISOString();

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
// apps/web/src/server/auth/session-challenge.js:162-193
if (data.used_at) throw createHttpError(401, "CHALLENGE_USED", "Challenge already used");
if (new Date(data.expires_at).getTime() <= Date.now()) {
  throw createHttpError(401, "CHALLENGE_EXPIRED", "Challenge expired");
}
if (sha256Hex(challenge) !== data.challenge_hash) {
  throw createHttpError(401, "CHALLENGE_MISMATCH", "Challenge mismatch");
}
const validSignature = await verifyChallengeSignature(challenge, signature, data.signing_public_key);
if (!validSignature) throw createHttpError(401, "INVALID_SIGNATURE", "Invalid challenge signature");

const { data: consumed } = await supabase
  .from("account_session_challenges")
  .update({ used_at: new Date().toISOString() })
  .eq("id", data.id)
  .is("used_at", null)
  .select("id")
  .maybeSingle();

if (!consumed?.id) throw createHttpError(401, "CHALLENGE_USED", "Challenge already used");
```

```js
// apps/web/src/server/domains/auth-domain.js:259-345
const verified = await consumeSessionChallenge(supabase, {
  challengeId,
  challenge,
  signature,
});

const session = issueAppSessionToken(verified.account.id, {
  ttlSeconds: 15 * 60,
});
```

```js
// apps/web/src/lib/app-session-jwt.js:3,56-66
const APP_SESSION_TTL_SECONDS = 15 * 60;

export function issueAppSessionToken(accountId, options = {}) {
  const ttlSeconds = Number.isFinite(Number(options.ttlSeconds))
    ? Math.max(60, Number(options.ttlSeconds))
    : APP_SESSION_TTL_SECONDS;
  // ... signs JWT with exp = now + ttlSeconds
}
```

What this proves:
- Session auth is bound to registered device keys, not password-only login.
- Challenge replay is blocked via expiry + one-time `used_at` consume.
- JWT sessions are intentionally short-lived (15 minutes default).

Scope note:
- This proves app auth/session logic and persistence behavior; it does not claim anything about external infrastructure logs.

Last verified against code: March 7, 2026.
