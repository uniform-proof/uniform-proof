# Proof: Actor-ID content identity mode

Claim:
Content payloads use scoped actor IDs and redact direct account IDs in active content responses.

Evidence snippets:

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260304110000_actor_identity_backfill_hard_cut.sql
ALTER TABLE public.posts ALTER COLUMN actor_id SET NOT NULL;
ALTER TABLE public.comments ALTER COLUMN actor_id SET NOT NULL;
ALTER TABLE public.dm_messages ALTER COLUMN actor_id SET NOT NULL;
```

```sql
-- apps/web/uniform-zk-db/supabase/migrations/20260304153000_actor_only_content_and_billing_unlink.sql
UPDATE public.posts SET author_account_id = NULL WHERE author_account_id IS NOT NULL;
UPDATE public.comments SET author_account_id = NULL WHERE author_account_id IS NOT NULL;
UPDATE public.dm_messages SET sender_account_id = NULL WHERE sender_account_id IS NOT NULL;
```

```js
// apps/web/src/server/domains/contexts-domain.js
author_account_id: actorModeEnabled ? null : resolvedAuthorAccountId,
author_actor_id: authorActorId,
```

What this proves:
- Actor IDs are mandatory and account IDs are redacted in actor mode response payloads.
