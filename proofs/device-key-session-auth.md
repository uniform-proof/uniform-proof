# Proof: Device-key session authentication

Claim:
Session setup uses a short challenge signed by a registered device signing key, then mints a short-lived app JWT.

Evidence snippets:

```js
// apps/web/src/server/auth/session-challenge.js
const CHALLENGE_TTL_SECONDS = 120;

export async function issueSessionChallenge(supabase, input) {
  // ... validates account + registered device keys
  // inserts challenge hash + expires_at
}

export async function consumeSessionChallenge(supabase, input) {
  // ... verifies challenge hash + signature
  // marks challenge used_at
}
```

```js
// apps/web/src/lib/app-session-jwt.js
const APP_SESSION_TTL_SECONDS = 15 * 60;

export function issueAppSessionToken(accountId, options = {}) {
  // issues short-lived app JWT
}
```

What this proves:
- Authentication depends on device keys and signed challenge verification.
- Session tokens are short-lived by default.
