BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.posts WHERE actor_id IS NULL) THEN
    RAISE EXCEPTION 'posts.actor_id must be backfilled before actor hard cut cleanup';
  END IF;

  IF EXISTS (SELECT 1 FROM public.comments WHERE actor_id IS NULL) THEN
    RAISE EXCEPTION 'comments.actor_id must be backfilled before actor hard cut cleanup';
  END IF;

  IF EXISTS (SELECT 1 FROM public.dm_messages WHERE actor_id IS NULL) THEN
    RAISE EXCEPTION 'dm_messages.actor_id must be backfilled before actor hard cut cleanup';
  END IF;
END
$$;

DROP POLICY IF EXISTS posts_insert_author_member ON public.posts;
CREATE POLICY posts_insert_actor_member
  ON public.posts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = posts.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = posts.actor_id
    )
  );

DROP POLICY IF EXISTS posts_update_member ON public.posts;
CREATE POLICY posts_update_actor
  ON public.posts
  FOR UPDATE
  TO authenticated
  USING (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = posts.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = posts.actor_id
    )
  )
  WITH CHECK (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = posts.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = posts.actor_id
    )
  );

DROP POLICY IF EXISTS posts_delete_author ON public.posts;
CREATE POLICY posts_delete_actor
  ON public.posts
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = posts.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = posts.actor_id
    )
  );

DROP POLICY IF EXISTS comments_insert_author_member ON public.comments;
CREATE POLICY comments_insert_actor_member
  ON public.comments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = comments.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = comments.actor_id
    )
  );

DROP POLICY IF EXISTS comments_update_member ON public.comments;
CREATE POLICY comments_update_actor
  ON public.comments
  FOR UPDATE
  TO authenticated
  USING (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = comments.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = comments.actor_id
    )
  )
  WITH CHECK (
    public.is_context_member(context_id)
    AND EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = comments.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = comments.actor_id
    )
  );

DROP POLICY IF EXISTS comments_delete_author ON public.comments;
CREATE POLICY comments_delete_actor
  ON public.comments
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.context_actor_identities AS cai
      WHERE cai.context_id = comments.context_id
        AND cai.account_id = public.current_account_id()
        AND cai.actor_id = comments.actor_id
    )
  );

DROP POLICY IF EXISTS post_likes_delete_self_or_author ON public.post_likes;
CREATE POLICY post_likes_delete_self_or_actor
  ON public.post_likes
  FOR DELETE
  TO authenticated
  USING (
    account_id = public.current_account_id()
    OR EXISTS (
      SELECT 1
      FROM public.posts AS p
      JOIN public.context_actor_identities AS cai
        ON cai.context_id = p.context_id
       AND cai.actor_id = p.actor_id
      WHERE p.id = post_likes.post_id
        AND cai.account_id = public.current_account_id()
    )
  );

DROP POLICY IF EXISTS comment_likes_delete_self_or_author ON public.comment_likes;
CREATE POLICY comment_likes_delete_self_or_actor
  ON public.comment_likes
  FOR DELETE
  TO authenticated
  USING (
    account_id = public.current_account_id()
    OR EXISTS (
      SELECT 1
      FROM public.comments AS c
      JOIN public.context_actor_identities AS cai
        ON cai.context_id = c.context_id
       AND cai.actor_id = c.actor_id
      WHERE c.id = comment_likes.comment_id
        AND cai.account_id = public.current_account_id()
    )
  );

DROP POLICY IF EXISTS dm_messages_insert_sender_member ON public.dm_messages;
CREATE POLICY dm_messages_insert_actor_member
  ON public.dm_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_thread_member(thread_id)
    AND EXISTS (
      SELECT 1
      FROM public.thread_actor_identities AS tai
      WHERE tai.thread_id = dm_messages.thread_id
        AND tai.account_id = public.current_account_id()
        AND tai.actor_id = dm_messages.actor_id
    )
  );

ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_author_account_id_fkey,
  DROP COLUMN IF EXISTS author_account_id CASCADE;

ALTER TABLE public.comments
  DROP CONSTRAINT IF EXISTS comments_author_account_id_fkey,
  DROP COLUMN IF EXISTS author_account_id CASCADE;

ALTER TABLE public.dm_messages
  DROP CONSTRAINT IF EXISTS dm_messages_sender_account_id_fkey,
  DROP COLUMN IF EXISTS sender_account_id CASCADE;

DROP TABLE IF EXISTS public.account_member_links CASCADE;
DROP TABLE IF EXISTS public.member_profiles CASCADE;
DROP TABLE IF EXISTS public.account_entitlements CASCADE;
DROP TABLE IF EXISTS public.entitlements CASCADE;
DROP TABLE IF EXISTS public.account_auth_identities CASCADE;

COMMIT;
