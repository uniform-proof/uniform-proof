# Proof: Actor-ID content identity mode

Claim:
Content APIs expose actor IDs and redact direct account IDs in active content payloads.

Evidence snippets:

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260304110000_actor_identity_backfill_hard_cut.sql:70-78
ALTER TABLE public.posts
  ALTER COLUMN actor_id SET NOT NULL;

ALTER TABLE public.comments
  ALTER COLUMN actor_id SET NOT NULL;

ALTER TABLE public.dm_messages
  ALTER COLUMN actor_id SET NOT NULL;
```

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260304153000_actor_only_content_and_billing_unlink.sql:18-29
UPDATE public.posts
SET author_account_id = NULL
WHERE author_account_id IS NOT NULL;

UPDATE public.comments
SET author_account_id = NULL
WHERE author_account_id IS NOT NULL;

UPDATE public.dm_messages
SET sender_account_id = NULL
WHERE sender_account_id IS NOT NULL;
```

```js
// apps/web/src/lib/privacy-flags.js:17-22
export const ACTOR_ID_MODE = true;
```

```js
// apps/web/src/server/domains/contexts-domain.js:889-890
author_account_id: actorModeEnabled ? null : resolvedAuthorAccountId,
author_actor_id: authorActorId,
```

```js
// apps/web/src/server/domains/dm-domain.js:629-630
sender_account_id: actorModeEnabled ? null : resolvedSenderAccountId,
sender_actor_id: senderActorId,
```

```js
// apps/web/src/server/domains/__tests__/privacy-hardening-qa.test.js:871-873
expect(payload.posts[0].author_account_id).toBeNull();
expect(payload.posts[0].author_actor_id).toBe("actor_other");
expect(payload.posts[0].author_display_handle).toBe("anon_worker");
```

```bash
# Verification command run March 7, 2026
npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js -t "actor mode redacts author_account_id in context post responses"
# Result: PASS (1 test, 0 failures)
```

What this proves:
- Actor IDs are mandatory at schema level for active content records.
- Historical direct account link fields are hard-cut to null.
- Runtime response mappers redact account IDs when actor mode is enabled.
- Redaction behavior is exercised by automated test.

Last verified against code: March 7, 2026.
