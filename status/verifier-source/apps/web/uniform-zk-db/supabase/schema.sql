


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."current_account_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_claim text;
  v_claims_json text;
BEGIN
  -- Legacy GUC keys (PostgREST <= legacy claim mode)
  v_claim := NULLIF(current_setting('request.jwt.claim.account_id', true), '');
  IF v_claim IS NULL THEN
    v_claim := NULLIF(current_setting('request.jwt.claim.sub', true), '');
  END IF;

  -- Modern PostgREST claim envelope (`request.jwt.claims` JSON)
  IF v_claim IS NULL THEN
    v_claims_json := NULLIF(current_setting('request.jwt.claims', true), '');
    IF v_claims_json IS NOT NULL THEN
      BEGIN
        v_claim := NULLIF((v_claims_json::jsonb ->> 'account_id'), '');
        IF v_claim IS NULL THEN
          v_claim := NULLIF((v_claims_json::jsonb ->> 'sub'), '');
        END IF;
      EXCEPTION WHEN others THEN
        v_claim := NULL;
      END;
    END IF;
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


ALTER FUNCTION "public"."current_account_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_context_member"("p_context_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.context_members AS cm
    WHERE cm.context_id = p_context_id
      AND cm.account_id = public.current_account_id()
  )
$$;


ALTER FUNCTION "public"."is_context_member"("p_context_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_global_admin"("p_account_id" "uuid" DEFAULT "public"."current_account_id"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.global_admins AS ga
    WHERE ga.account_id = COALESCE(p_account_id, public.current_account_id())
      AND ga.is_active = true
      AND ga.role IN ('admin', 'moderator', 'viewer')
  )
$$;


ALTER FUNCTION "public"."is_global_admin"("p_account_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_location_member"("p_location_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.context_members AS cm
    JOIN public.contexts AS c
      ON c.id = cm.context_id
    WHERE cm.account_id = public.current_account_id()
      AND c.scope_type = 'LOCATION'
      AND c.location_id = p_location_id
  )
$$;


ALTER FUNCTION "public"."is_location_member"("p_location_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_thread_member"("p_thread_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.dm_thread_members AS tm
    WHERE tm.thread_id = p_thread_id
      AND tm.account_id = public.current_account_id()
  )
$$;


ALTER FUNCTION "public"."is_thread_member"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_card_receipt_submission_token"("p_location_id" "uuid", "p_ttl_seconds" integer DEFAULT 900) RETURNS TABLE("token" "text", "expires_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_account_id uuid;
  v_token text;
  v_expires timestamptz;
BEGIN
  v_account_id := public.current_account_id();
  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.is_location_member(p_location_id) THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_expires := now() + make_interval(secs => GREATEST(COALESCE(p_ttl_seconds, 900), 60));

  INSERT INTO public.card_receipt_submission_tokens (
    location_id,
    token_hash,
    expires_at
  )
  VALUES (
    p_location_id,
    encode(digest(v_token, 'sha256'), 'hex'),
    v_expires
  );

  RETURN QUERY
  SELECT v_token, v_expires;
END;
$$;


ALTER FUNCTION "public"."issue_card_receipt_submission_token"("p_location_id" "uuid", "p_ttl_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_notification_preferences_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_user_notification_preferences_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."shares_context_with_current"("p_account_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.context_members AS self_cm
    JOIN public.context_members AS other_cm
      ON other_cm.context_id = self_cm.context_id
    WHERE self_cm.account_id = public.current_account_id()
      AND other_cm.account_id = p_account_id
  )
$$;


ALTER FUNCTION "public"."shares_context_with_current"("p_account_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_card_receipt_with_token"("p_location_id" "uuid", "p_receipt_hash" "text", "p_nullifier_hash" "text", "p_submission_token" "text") RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_token_row public.card_receipt_submission_tokens%ROWTYPE;
  v_inserted public.card_receipts%ROWTYPE;
BEGIN
  SELECT *
  INTO v_token_row
  FROM public.card_receipt_submission_tokens AS tokens
  WHERE tokens.token_hash = encode(digest(p_submission_token, 'sha256'), 'hex')
    AND tokens.location_id = p_location_id
    AND tokens.consumed_at IS NULL
    AND tokens.expires_at > now()
  ORDER BY tokens.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_token_row.id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired submission token';
  END IF;

  INSERT INTO public.card_receipts (location_id, receipt_hash, nullifier_hash)
  VALUES (p_location_id, p_receipt_hash, p_nullifier_hash)
  RETURNING * INTO v_inserted;

  -- Qualify table columns to avoid conflict with RETURN TABLE output arg names.
  UPDATE public.card_receipt_submission_tokens AS tokens
  SET consumed_at = now()
  WHERE tokens.id = v_token_row.id;

  RETURN QUERY
  SELECT v_inserted.id, v_inserted.created_at;
END;
$$;


ALTER FUNCTION "public"."submit_card_receipt_with_token"("p_location_id" "uuid", "p_receipt_hash" "text", "p_nullifier_hash" "text", "p_submission_token" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."account_bans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "ban_type" "text" NOT NULL,
    "reason" "text",
    "banned_by" "uuid",
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "account_bans_ban_type_check" CHECK (("ban_type" = ANY (ARRAY['posting'::"text", 'commenting'::"text", 'all'::"text"])))
);


ALTER TABLE "public"."account_bans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "device_public_key" "text" NOT NULL,
    "signing_public_key" "text" NOT NULL,
    "device_label" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone
);


ALTER TABLE "public"."account_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_session_challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "device_public_key" "text" NOT NULL,
    "signing_public_key" "text" NOT NULL,
    "challenge_hash" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "used_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."account_session_challenges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "handle" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "accounts_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'banned'::"text", 'deleted'::"text"])))
);


ALTER TABLE "public"."accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_gated_accounts" (
    "account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."billing_gated_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."blocked_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "blocker_account_id" "uuid" NOT NULL,
    "blocked_account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."blocked_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."card_receipt_submission_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "uuid" NOT NULL,
    "token_hash" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "consumed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."card_receipt_submission_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."card_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "uuid" NOT NULL,
    "receipt_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "nullifier_hash" "text"
);


ALTER TABLE "public"."card_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comment_likes" (
    "comment_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."comment_likes" REPLICA IDENTITY FULL;


ALTER TABLE "public"."comment_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "post_id" "uuid" NOT NULL,
    "context_id" "uuid" NOT NULL,
    "ciphertext" "text" NOT NULL,
    "ciphertext_version" integer DEFAULT 2 NOT NULL,
    "author_signature" "text",
    "parent_comment_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "like_count" integer DEFAULT 0,
    "key_epoch" integer DEFAULT 1 NOT NULL,
    "deleted_at" timestamp with time zone,
    "actor_id" "uuid" NOT NULL
);

ALTER TABLE ONLY "public"."comments" REPLICA IDENTITY FULL;


ALTER TABLE "public"."comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_suppressions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "uuid" NOT NULL,
    "is_suppressed" boolean DEFAULT true NOT NULL,
    "reason" "text",
    "created_by_account_id" "uuid" NOT NULL,
    "restored_by_account_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "restored_at" timestamp with time zone,
    CONSTRAINT "content_suppressions_target_type_check" CHECK (("target_type" = ANY (ARRAY['post'::"text", 'comment'::"text", 'dm_message'::"text"])))
);


ALTER TABLE "public"."content_suppressions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."context_actor_identities" (
    "context_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "actor_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "display_handle" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."context_actor_identities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."context_keys" (
    "context_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "epoch" integer DEFAULT 1 NOT NULL,
    "encrypted_context_key" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."context_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."context_members" (
    "context_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "context_members_role_check" CHECK (("role" = ANY (ARRAY['member'::"text", 'mod'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."context_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contexts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "scope_type" "text" NOT NULL,
    "employer_id" "uuid" NOT NULL,
    "location_id" "uuid",
    "phase" "text" NOT NULL,
    "visibility" "text" NOT NULL,
    "default_identity" "text" NOT NULL,
    "is_e2ee" boolean DEFAULT true NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "current_epoch" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "contexts_default_identity_check" CHECK (("default_identity" = ANY (ARRAY['ANON'::"text", 'MEMBER'::"text"]))),
    CONSTRAINT "contexts_phase_check" CHECK (("phase" = ANY (ARRAY['ORGANIZING'::"text", 'UNION'::"text"]))),
    CONSTRAINT "contexts_scope_type_check" CHECK (("scope_type" = ANY (ARRAY['EMPLOYER'::"text", 'LOCATION'::"text"]))),
    CONSTRAINT "contexts_visibility_check" CHECK (("visibility" = ANY (ARRAY['ANON_ONLY'::"text", 'MEMBER_ONLY'::"text"])))
);


ALTER TABLE "public"."contexts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_push_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "push_token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "disabled_at" timestamp with time zone,
    CONSTRAINT "device_push_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."device_push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "ciphertext" "text" NOT NULL,
    "ciphertext_version" integer DEFAULT 2 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "key_epoch" integer DEFAULT 1 NOT NULL,
    "actor_id" "uuid" NOT NULL
);

ALTER TABLE ONLY "public"."dm_messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."dm_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_thread_keys" (
    "thread_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "epoch" integer DEFAULT 1 NOT NULL,
    "encrypted_thread_key" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "dm_thread_keys_epoch_check" CHECK (("epoch" >= 1))
);


ALTER TABLE "public"."dm_thread_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_thread_members" (
    "thread_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_read_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."dm_thread_members" REPLICA IDENTITY FULL;


ALTER TABLE "public"."dm_thread_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_threads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "current_epoch" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."dm_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employee_count_submissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "employee_count" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "employee_count_submissions_employee_count_check" CHECK (("employee_count" > 0))
);


ALTER TABLE "public"."employee_count_submissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "slug" "text",
    "company_structure" "text" DEFAULT 'multiple_locations'::"text",
    "company_type" "text",
    "stock_ticker" "text",
    "industry" "text",
    "headquarters_address" "text",
    "headquarters_city" "text",
    "headquarters_state" "text",
    "headquarters_zip_code" "text",
    "headquarters_phone" "text",
    "website_url" "text"
);


ALTER TABLE "public"."employers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."encrypted_media" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "uploader_account_id" "uuid" NOT NULL,
    "media_kind" "text" DEFAULT 'image'::"text" NOT NULL,
    "mime_type" "text" NOT NULL,
    "byte_length" integer NOT NULL,
    "encrypted_blob" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "encrypted_media_byte_length_check" CHECK (("byte_length" >= 0)),
    CONSTRAINT "encrypted_media_media_kind_check" CHECK (("media_kind" = ANY (ARRAY['image'::"text", 'file'::"text"])))
);


ALTER TABLE "public"."encrypted_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."encrypted_media_access" (
    "media_id" "uuid" NOT NULL,
    "scope_type" "text" NOT NULL,
    "scope_id" "uuid" NOT NULL,
    "granted_by_account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "encrypted_media_access_scope_type_check" CHECK (("scope_type" = ANY (ARRAY['context'::"text", 'dm_thread'::"text"])))
);


ALTER TABLE "public"."encrypted_media_access" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "type" "text" DEFAULT 'general'::"text" NOT NULL,
    "message" "text" NOT NULL,
    "response" "text",
    "responded_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "resolved_by_account_id" "uuid",
    "resolved_at" timestamp with time zone,
    "resolution_notes" "text",
    CONSTRAINT "feedback_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'resolved'::"text", 'dismissed'::"text"])))
);


ALTER TABLE "public"."feedback" OWNER TO "postgres";


COMMENT ON COLUMN "public"."feedback"."attachments" IS 'Optional encrypted media attachment metadata (media_id/media_key_b64/mime_type/byte_length).';



CREATE TABLE IF NOT EXISTS "public"."global_admins" (
    "account_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'admin'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by_account_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "global_admins_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'moderator'::"text", 'viewer'::"text"])))
);


ALTER TABLE "public"."global_admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."location_status" (
    "location_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'organizing'::"text" NOT NULL,
    "union_id" "uuid",
    "unionized_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "location_status_status_check" CHECK (("status" = ANY (ARRAY['organizing'::"text", 'unionized'::"text"])))
);


ALTER TABLE "public"."location_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employer_id" "uuid" NOT NULL,
    "location_code" "text",
    "location_name" "text",
    "city" "text",
    "state" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "employee_count" integer,
    "address" "text",
    "zip_code" "text",
    "is_headquarters" boolean DEFAULT false,
    "phone_number" "text"
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."moderation_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_account_id" "uuid" NOT NULL,
    "action_type" "text" NOT NULL,
    "target_type" "text" NOT NULL,
    "target_id" "uuid",
    "target_account_id" "uuid",
    "report_id" "uuid",
    "feedback_id" "uuid",
    "appeal_id" "uuid",
    "reason" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "moderation_actions_action_type_check" CHECK (("action_type" = ANY (ARRAY['report_under_review'::"text", 'report_resolved'::"text", 'report_dismissed'::"text", 'suppress_content'::"text", 'restore_content'::"text", 'ban_account'::"text", 'unban_account'::"text", 'feedback_resolved'::"text", 'appeal_resolved'::"text"]))),
    CONSTRAINT "moderation_actions_target_type_check" CHECK (("target_type" = ANY (ARRAY['post'::"text", 'comment'::"text", 'dm_message'::"text", 'account'::"text", 'report'::"text", 'feedback'::"text", 'appeal'::"text"])))
);


ALTER TABLE "public"."moderation_actions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."moderation_appeals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "appellant_account_id" "uuid" NOT NULL,
    "report_id" "uuid",
    "moderation_action_id" "uuid",
    "reason" "text" NOT NULL,
    "details" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "decision" "text",
    "reviewed_by_account_id" "uuid",
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "moderation_appeals_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'under_review'::"text", 'resolved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "moderation_appeals_target_check" CHECK ((("report_id" IS NOT NULL) OR ("moderation_action_id" IS NOT NULL)))
);


ALTER TABLE "public"."moderation_appeals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "ref_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."notification_queue" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notification_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."post_likes" (
    "post_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."post_likes" REPLICA IDENTITY FULL;


ALTER TABLE "public"."post_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."post_shares" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "post_id" "uuid",
    "account_id" "uuid",
    "share_type" "text" DEFAULT 'copy_link'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."post_shares" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "context_id" "uuid" NOT NULL,
    "ciphertext" "text" NOT NULL,
    "ciphertext_version" integer DEFAULT 2 NOT NULL,
    "author_signature" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "post_type" "text" DEFAULT 'text'::"text",
    "image_url" "text",
    "poll_options" "jsonb",
    "poll_votes" "jsonb" DEFAULT '{}'::"jsonb",
    "poll_expires_at" timestamp with time zone,
    "like_count" integer DEFAULT 0,
    "comment_count" integer DEFAULT 0,
    "share_count" integer DEFAULT 0,
    "key_epoch" integer DEFAULT 1 NOT NULL,
    "actor_id" "uuid" NOT NULL,
    CONSTRAINT "posts_post_type_check" CHECK (("post_type" = ANY (ARRAY['text'::"text", 'poll'::"text", 'image'::"text"])))
);

ALTER TABLE ONLY "public"."posts" REPLICA IDENTITY FULL;


ALTER TABLE "public"."posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_account_id" "uuid" NOT NULL,
    "reported_post_id" "uuid",
    "reported_comment_id" "uuid",
    "reason" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "reported_dm_message_id" "uuid",
    "reviewed_by_account_id" "uuid",
    "reviewed_at" timestamp with time zone,
    "resolution_notes" "text",
    "topic" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    CONSTRAINT "report_target" CHECK (((((("reported_post_id" IS NOT NULL))::integer + (("reported_comment_id" IS NOT NULL))::integer) + (("reported_dm_message_id" IS NOT NULL))::integer) = 1)),
    CONSTRAINT "reports_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'under_review'::"text", 'resolved'::"text", 'dismissed'::"text"])))
);


ALTER TABLE "public"."reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."thread_actor_identities" (
    "thread_id" "uuid" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "actor_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."thread_actor_identities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "employer_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."unions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_notification_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "push_enabled" boolean DEFAULT true NOT NULL,
    "posts_scope" "text" DEFAULT 'my_location'::"text" NOT NULL,
    "likes_enabled" boolean DEFAULT true NOT NULL,
    "comments_enabled" boolean DEFAULT true NOT NULL,
    "mentions_enabled" boolean DEFAULT true NOT NULL,
    "poll_responses_enabled" boolean DEFAULT true NOT NULL,
    "poll_results_enabled" boolean DEFAULT true NOT NULL,
    "card_signatures_scope" "text" DEFAULT 'off'::"text" NOT NULL,
    "announcements_my_location_enabled" boolean DEFAULT true NOT NULL,
    "announcements_all_locations_enabled" boolean DEFAULT false NOT NULL,
    "admin_in_app_notifications_enabled" boolean DEFAULT true NOT NULL,
    "messages_enabled" boolean DEFAULT true NOT NULL,
    "organizing_status_enabled" boolean DEFAULT true NOT NULL,
    "product_announcements_enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_notification_preferences_card_signatures_scope_check" CHECK (("card_signatures_scope" = ANY (ARRAY['my_location'::"text", 'all_locations'::"text", 'off'::"text"]))),
    CONSTRAINT "user_notification_preferences_posts_scope_check" CHECK (("posts_scope" = ANY (ARRAY['my_location'::"text", 'all_locations'::"text", 'off'::"text"])))
);


ALTER TABLE "public"."user_notification_preferences" OWNER TO "postgres";


ALTER TABLE ONLY "public"."account_bans"
    ADD CONSTRAINT "account_bans_account_id_ban_type_key" UNIQUE ("account_id", "ban_type");



ALTER TABLE ONLY "public"."account_bans"
    ADD CONSTRAINT "account_bans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."account_devices"
    ADD CONSTRAINT "account_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."account_session_challenges"
    ADD CONSTRAINT "account_session_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_handle_key" UNIQUE ("handle");



ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_gated_accounts"
    ADD CONSTRAINT "billing_gated_accounts_pkey" PRIMARY KEY ("account_id");



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_blocker_account_id_blocked_account_id_key" UNIQUE ("blocker_account_id", "blocked_account_id");



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."card_receipt_submission_tokens"
    ADD CONSTRAINT "card_receipt_submission_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."card_receipt_submission_tokens"
    ADD CONSTRAINT "card_receipt_submission_tokens_token_hash_key" UNIQUE ("token_hash");



ALTER TABLE ONLY "public"."card_receipts"
    ADD CONSTRAINT "card_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."card_receipts"
    ADD CONSTRAINT "card_receipts_receipt_hash_key" UNIQUE ("receipt_hash");



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_pkey" PRIMARY KEY ("comment_id", "account_id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_suppressions"
    ADD CONSTRAINT "content_suppressions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_suppressions"
    ADD CONSTRAINT "content_suppressions_target_type_target_id_key" UNIQUE ("target_type", "target_id");



ALTER TABLE ONLY "public"."context_actor_identities"
    ADD CONSTRAINT "context_actor_identities_context_id_actor_id_key" UNIQUE ("context_id", "actor_id");



ALTER TABLE ONLY "public"."context_actor_identities"
    ADD CONSTRAINT "context_actor_identities_pkey" PRIMARY KEY ("context_id", "account_id");



ALTER TABLE ONLY "public"."context_keys"
    ADD CONSTRAINT "context_keys_pkey" PRIMARY KEY ("context_id", "account_id", "epoch");



ALTER TABLE ONLY "public"."context_members"
    ADD CONSTRAINT "context_members_pkey" PRIMARY KEY ("context_id", "account_id");



ALTER TABLE ONLY "public"."contexts"
    ADD CONSTRAINT "contexts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_push_tokens"
    ADD CONSTRAINT "device_push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_thread_keys"
    ADD CONSTRAINT "dm_thread_keys_pkey" PRIMARY KEY ("thread_id", "account_id", "epoch");



ALTER TABLE ONLY "public"."dm_thread_members"
    ADD CONSTRAINT "dm_thread_members_pkey" PRIMARY KEY ("thread_id", "account_id");



ALTER TABLE ONLY "public"."dm_threads"
    ADD CONSTRAINT "dm_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employee_count_submissions"
    ADD CONSTRAINT "employee_count_submissions_location_id_account_id_key" UNIQUE ("location_id", "account_id");



ALTER TABLE ONLY "public"."employee_count_submissions"
    ADD CONSTRAINT "employee_count_submissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employers"
    ADD CONSTRAINT "employers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."encrypted_media_access"
    ADD CONSTRAINT "encrypted_media_access_pkey" PRIMARY KEY ("media_id", "scope_type", "scope_id");



ALTER TABLE ONLY "public"."encrypted_media"
    ADD CONSTRAINT "encrypted_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."global_admins"
    ADD CONSTRAINT "global_admins_pkey" PRIMARY KEY ("account_id");



ALTER TABLE ONLY "public"."location_status"
    ADD CONSTRAINT "location_status_pkey" PRIMARY KEY ("location_id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moderation_appeals"
    ADD CONSTRAINT "moderation_appeals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_likes"
    ADD CONSTRAINT "post_likes_pkey" PRIMARY KEY ("post_id", "account_id");



ALTER TABLE ONLY "public"."post_shares"
    ADD CONSTRAINT "post_shares_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."thread_actor_identities"
    ADD CONSTRAINT "thread_actor_identities_pkey" PRIMARY KEY ("thread_id", "account_id");



ALTER TABLE ONLY "public"."thread_actor_identities"
    ADD CONSTRAINT "thread_actor_identities_thread_id_actor_id_key" UNIQUE ("thread_id", "actor_id");



ALTER TABLE ONLY "public"."unions"
    ADD CONSTRAINT "unions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_notification_preferences"
    ADD CONSTRAINT "user_notification_preferences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_notification_preferences"
    ADD CONSTRAINT "user_notification_preferences_user_id_tenant_id_key" UNIQUE ("user_id", "tenant_id");



CREATE INDEX "idx_account_bans_account_id" ON "public"."account_bans" USING "btree" ("account_id");



CREATE INDEX "idx_account_bans_expires" ON "public"."account_bans" USING "btree" ("expires_at") WHERE ("expires_at" IS NOT NULL);



CREATE INDEX "idx_account_devices_account_id" ON "public"."account_devices" USING "btree" ("account_id");



CREATE INDEX "idx_account_session_challenges_account" ON "public"."account_session_challenges" USING "btree" ("account_id");



CREATE INDEX "idx_account_session_challenges_expires" ON "public"."account_session_challenges" USING "btree" ("expires_at");



CREATE INDEX "idx_blocked_users_blocked" ON "public"."blocked_users" USING "btree" ("blocked_account_id");



CREATE INDEX "idx_blocked_users_blocker" ON "public"."blocked_users" USING "btree" ("blocker_account_id");



CREATE INDEX "idx_card_receipt_tokens_expires" ON "public"."card_receipt_submission_tokens" USING "btree" ("expires_at");



CREATE INDEX "idx_card_receipt_tokens_location" ON "public"."card_receipt_submission_tokens" USING "btree" ("location_id");



CREATE INDEX "idx_card_receipts_location_id" ON "public"."card_receipts" USING "btree" ("location_id");



CREATE UNIQUE INDEX "idx_card_receipts_nullifier_hash_unique" ON "public"."card_receipts" USING "btree" ("nullifier_hash") WHERE ("nullifier_hash" IS NOT NULL);



CREATE INDEX "idx_comment_likes_comment" ON "public"."comment_likes" USING "btree" ("comment_id");



CREATE INDEX "idx_comments_actor_id" ON "public"."comments" USING "btree" ("actor_id");



CREATE INDEX "idx_comments_deleted_at" ON "public"."comments" USING "btree" ("deleted_at");



CREATE INDEX "idx_comments_parent_comment_id" ON "public"."comments" USING "btree" ("parent_comment_id");



CREATE INDEX "idx_comments_post" ON "public"."comments" USING "btree" ("post_id", "created_at");



CREATE INDEX "idx_comments_post_id" ON "public"."comments" USING "btree" ("post_id");



CREATE INDEX "idx_content_suppressions_active" ON "public"."content_suppressions" USING "btree" ("target_type", "target_id") WHERE ("is_suppressed" = true);



CREATE INDEX "idx_content_suppressions_updated" ON "public"."content_suppressions" USING "btree" ("updated_at" DESC);



CREATE INDEX "idx_context_keys_account_id" ON "public"."context_keys" USING "btree" ("account_id");



CREATE INDEX "idx_context_members_account_id" ON "public"."context_members" USING "btree" ("account_id");



CREATE INDEX "idx_dm_messages_actor_id" ON "public"."dm_messages" USING "btree" ("actor_id");



CREATE INDEX "idx_dm_messages_created_at" ON "public"."dm_messages" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_dm_messages_thread_id" ON "public"."dm_messages" USING "btree" ("thread_id");



CREATE INDEX "idx_dm_thread_keys_account_id" ON "public"."dm_thread_keys" USING "btree" ("account_id");



CREATE INDEX "idx_employee_count_submissions_account_id" ON "public"."employee_count_submissions" USING "btree" ("account_id");



CREATE INDEX "idx_employee_count_submissions_location_id" ON "public"."employee_count_submissions" USING "btree" ("location_id");



CREATE UNIQUE INDEX "idx_employers_name_unique_lower" ON "public"."employers" USING "btree" ("lower"("name"));



CREATE UNIQUE INDEX "idx_employers_slug" ON "public"."employers" USING "btree" ("slug") WHERE ("slug" IS NOT NULL);



CREATE INDEX "idx_encrypted_media_access_media_id" ON "public"."encrypted_media_access" USING "btree" ("media_id");



CREATE INDEX "idx_encrypted_media_access_scope" ON "public"."encrypted_media_access" USING "btree" ("scope_type", "scope_id");



CREATE INDEX "idx_encrypted_media_uploader" ON "public"."encrypted_media" USING "btree" ("uploader_account_id");



CREATE INDEX "idx_feedback_status_created" ON "public"."feedback" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_global_admins_is_active" ON "public"."global_admins" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_global_admins_role" ON "public"."global_admins" USING "btree" ("role");



CREATE INDEX "idx_locations_employer_id" ON "public"."locations" USING "btree" ("employer_id");



CREATE INDEX "idx_moderation_actions_admin" ON "public"."moderation_actions" USING "btree" ("admin_account_id", "created_at" DESC);



CREATE INDEX "idx_moderation_actions_created" ON "public"."moderation_actions" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_moderation_actions_target" ON "public"."moderation_actions" USING "btree" ("target_type", "target_id");



CREATE INDEX "idx_moderation_appeals_action" ON "public"."moderation_appeals" USING "btree" ("moderation_action_id") WHERE ("moderation_action_id" IS NOT NULL);



CREATE INDEX "idx_moderation_appeals_appellant" ON "public"."moderation_appeals" USING "btree" ("appellant_account_id", "created_at" DESC);



CREATE INDEX "idx_moderation_appeals_report" ON "public"."moderation_appeals" USING "btree" ("report_id") WHERE ("report_id" IS NOT NULL);



CREATE INDEX "idx_moderation_appeals_status_created" ON "public"."moderation_appeals" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_notification_queue_account_id" ON "public"."notification_queue" USING "btree" ("account_id");



CREATE INDEX "idx_notification_queue_unsent" ON "public"."notification_queue" USING "btree" ("sent_at") WHERE ("sent_at" IS NULL);



CREATE INDEX "idx_post_likes_account" ON "public"."post_likes" USING "btree" ("account_id");



CREATE INDEX "idx_post_likes_post" ON "public"."post_likes" USING "btree" ("post_id");



CREATE INDEX "idx_post_shares_post" ON "public"."post_shares" USING "btree" ("post_id");



CREATE INDEX "idx_posts_actor_id" ON "public"."posts" USING "btree" ("actor_id");



CREATE INDEX "idx_posts_context_created" ON "public"."posts" USING "btree" ("context_id", "created_at" DESC);



CREATE INDEX "idx_posts_context_id" ON "public"."posts" USING "btree" ("context_id");



CREATE INDEX "idx_posts_created_at" ON "public"."posts" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_reports_dm_message" ON "public"."reports" USING "btree" ("reported_dm_message_id") WHERE ("reported_dm_message_id" IS NOT NULL);



CREATE INDEX "idx_reports_post" ON "public"."reports" USING "btree" ("reported_post_id") WHERE ("reported_post_id" IS NOT NULL);



CREATE INDEX "idx_reports_status" ON "public"."reports" USING "btree" ("status");



CREATE INDEX "idx_reports_status_created" ON "public"."reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_reports_topic" ON "public"."reports" USING "btree" ("topic") WHERE ("topic" IS NOT NULL);



CREATE UNIQUE INDEX "idx_reports_unique_reporter_comment" ON "public"."reports" USING "btree" ("reporter_account_id", "reported_comment_id") WHERE ("reported_comment_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_reports_unique_reporter_dm_message" ON "public"."reports" USING "btree" ("reporter_account_id", "reported_dm_message_id") WHERE ("reported_dm_message_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_reports_unique_reporter_post" ON "public"."reports" USING "btree" ("reporter_account_id", "reported_post_id") WHERE ("reported_post_id" IS NOT NULL);



CREATE INDEX "idx_user_notification_preferences_tenant" ON "public"."user_notification_preferences" USING "btree" ("tenant_id");



CREATE INDEX "idx_user_notification_preferences_user_tenant" ON "public"."user_notification_preferences" USING "btree" ("user_id", "tenant_id");



CREATE OR REPLACE TRIGGER "trg_set_user_notification_preferences_updated_at" BEFORE UPDATE ON "public"."user_notification_preferences" FOR EACH ROW EXECUTE FUNCTION "public"."set_user_notification_preferences_updated_at"();



ALTER TABLE ONLY "public"."account_devices"
    ADD CONSTRAINT "account_devices_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_session_challenges"
    ADD CONSTRAINT "account_session_challenges_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_gated_accounts"
    ADD CONSTRAINT "billing_gated_accounts_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_blocked_account_id_fkey" FOREIGN KEY ("blocked_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocked_users"
    ADD CONSTRAINT "blocked_users_blocker_account_id_fkey" FOREIGN KEY ("blocker_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."card_receipt_submission_tokens"
    ADD CONSTRAINT "card_receipt_submission_tokens_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."card_receipts"
    ADD CONSTRAINT "card_receipts_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_context_id_fkey" FOREIGN KEY ("context_id") REFERENCES "public"."contexts"("id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_parent_comment_id_fkey" FOREIGN KEY ("parent_comment_id") REFERENCES "public"."comments"("id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_suppressions"
    ADD CONSTRAINT "content_suppressions_created_by_account_id_fkey" FOREIGN KEY ("created_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_suppressions"
    ADD CONSTRAINT "content_suppressions_restored_by_account_id_fkey" FOREIGN KEY ("restored_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."context_actor_identities"
    ADD CONSTRAINT "context_actor_identities_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."context_actor_identities"
    ADD CONSTRAINT "context_actor_identities_context_id_fkey" FOREIGN KEY ("context_id") REFERENCES "public"."contexts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."context_keys"
    ADD CONSTRAINT "context_keys_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."context_keys"
    ADD CONSTRAINT "context_keys_context_id_fkey" FOREIGN KEY ("context_id") REFERENCES "public"."contexts"("id");



ALTER TABLE ONLY "public"."context_members"
    ADD CONSTRAINT "context_members_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."context_members"
    ADD CONSTRAINT "context_members_context_id_fkey" FOREIGN KEY ("context_id") REFERENCES "public"."contexts"("id");



ALTER TABLE ONLY "public"."contexts"
    ADD CONSTRAINT "contexts_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."employers"("id");



ALTER TABLE ONLY "public"."contexts"
    ADD CONSTRAINT "contexts_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."device_push_tokens"
    ADD CONSTRAINT "device_push_tokens_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_thread_keys"
    ADD CONSTRAINT "dm_thread_keys_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_thread_keys"
    ADD CONSTRAINT "dm_thread_keys_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_thread_members"
    ADD CONSTRAINT "dm_thread_members_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."dm_thread_members"
    ADD CONSTRAINT "dm_thread_members_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_count_submissions"
    ADD CONSTRAINT "employee_count_submissions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_count_submissions"
    ADD CONSTRAINT "employee_count_submissions_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."encrypted_media_access"
    ADD CONSTRAINT "encrypted_media_access_granted_by_account_id_fkey" FOREIGN KEY ("granted_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."encrypted_media_access"
    ADD CONSTRAINT "encrypted_media_access_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "public"."encrypted_media"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."encrypted_media"
    ADD CONSTRAINT "encrypted_media_uploader_account_id_fkey" FOREIGN KEY ("uploader_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_resolved_by_account_id_fkey" FOREIGN KEY ("resolved_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."global_admins"
    ADD CONSTRAINT "global_admins_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."global_admins"
    ADD CONSTRAINT "global_admins_created_by_account_id_fkey" FOREIGN KEY ("created_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."location_status"
    ADD CONSTRAINT "location_status_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."employers"("id");



ALTER TABLE ONLY "public"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_admin_account_id_fkey" FOREIGN KEY ("admin_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_feedback_id_fkey" FOREIGN KEY ("feedback_id") REFERENCES "public"."feedback"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_target_account_id_fkey" FOREIGN KEY ("target_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_appeals"
    ADD CONSTRAINT "moderation_appeals_appellant_account_id_fkey" FOREIGN KEY ("appellant_account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moderation_appeals"
    ADD CONSTRAINT "moderation_appeals_moderation_action_id_fkey" FOREIGN KEY ("moderation_action_id") REFERENCES "public"."moderation_actions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_appeals"
    ADD CONSTRAINT "moderation_appeals_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_appeals"
    ADD CONSTRAINT "moderation_appeals_reviewed_by_account_id_fkey" FOREIGN KEY ("reviewed_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."post_likes"
    ADD CONSTRAINT "post_likes_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."post_likes"
    ADD CONSTRAINT "post_likes_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_shares"
    ADD CONSTRAINT "post_shares_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."post_shares"
    ADD CONSTRAINT "post_shares_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_context_id_fkey" FOREIGN KEY ("context_id") REFERENCES "public"."contexts"("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reported_comment_id_fkey" FOREIGN KEY ("reported_comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reported_dm_message_id_fkey" FOREIGN KEY ("reported_dm_message_id") REFERENCES "public"."dm_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reported_post_id_fkey" FOREIGN KEY ("reported_post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reporter_account_id_fkey" FOREIGN KEY ("reporter_account_id") REFERENCES "public"."accounts"("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reviewed_by_account_id_fkey" FOREIGN KEY ("reviewed_by_account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."thread_actor_identities"
    ADD CONSTRAINT "thread_actor_identities_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."thread_actor_identities"
    ADD CONSTRAINT "thread_actor_identities_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."unions"
    ADD CONSTRAINT "unions_employer_id_fkey" FOREIGN KEY ("employer_id") REFERENCES "public"."employers"("id");



ALTER TABLE ONLY "public"."user_notification_preferences"
    ADD CONSTRAINT "user_notification_preferences_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."employers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notification_preferences"
    ADD CONSTRAINT "user_notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."accounts"("id") ON DELETE CASCADE;



ALTER TABLE "public"."account_bans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_bans_select_self" ON "public"."account_bans" FOR SELECT TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."account_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_devices_delete_self" ON "public"."account_devices" FOR DELETE TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "account_devices_insert_self" ON "public"."account_devices" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "public"."current_account_id"()));



CREATE POLICY "account_devices_select_self" ON "public"."account_devices" FOR SELECT TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "account_devices_update_self" ON "public"."account_devices" FOR UPDATE TO "authenticated" USING (("account_id" = "public"."current_account_id"())) WITH CHECK (("account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."account_session_challenges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_session_challenges_service_role_only" ON "public"."account_session_challenges" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."accounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "accounts_select_self" ON "public"."accounts" FOR SELECT TO "authenticated" USING (("id" = "public"."current_account_id"()));



CREATE POLICY "accounts_update_self" ON "public"."accounts" FOR UPDATE TO "authenticated" USING (("id" = "public"."current_account_id"())) WITH CHECK (("id" = "public"."current_account_id"()));



ALTER TABLE "public"."billing_gated_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."blocked_users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "blocked_users_delete_self" ON "public"."blocked_users" FOR DELETE TO "authenticated" USING (("blocker_account_id" = "public"."current_account_id"()));



CREATE POLICY "blocked_users_insert_self" ON "public"."blocked_users" FOR INSERT TO "authenticated" WITH CHECK ((("blocker_account_id" = "public"."current_account_id"()) AND ("blocked_account_id" <> "public"."current_account_id"())));



CREATE POLICY "blocked_users_select_self" ON "public"."blocked_users" FOR SELECT TO "authenticated" USING (("blocker_account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."card_receipt_submission_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."card_receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "card_receipts_select_location_member" ON "public"."card_receipts" FOR SELECT TO "authenticated" USING ("public"."is_location_member"("location_id"));



ALTER TABLE "public"."comment_likes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "comment_likes_delete_self_or_actor" ON "public"."comment_likes" FOR DELETE TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM ("public"."comments" "c"
     JOIN "public"."context_actor_identities" "cai" ON ((("cai"."context_id" = "c"."context_id") AND ("cai"."actor_id" = "c"."actor_id"))))
  WHERE (("c"."id" = "comment_likes"."comment_id") AND ("cai"."account_id" = "public"."current_account_id"()))))));



CREATE POLICY "comment_likes_insert_self" ON "public"."comment_likes" FOR INSERT TO "authenticated" WITH CHECK ((("account_id" = "public"."current_account_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."comments" "c"
  WHERE (("c"."id" = "comment_likes"."comment_id") AND "public"."is_context_member"("c"."context_id"))))));



CREATE POLICY "comment_likes_select_member" ON "public"."comment_likes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."comments" "c"
  WHERE (("c"."id" = "comment_likes"."comment_id") AND "public"."is_context_member"("c"."context_id")))));



ALTER TABLE "public"."comments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "comments_delete_actor" ON "public"."comments" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "comments"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "comments"."actor_id")))));



CREATE POLICY "comments_insert_actor_member" ON "public"."comments" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "comments"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "comments"."actor_id"))))));



CREATE POLICY "comments_select_member" ON "public"."comments" FOR SELECT TO "authenticated" USING ("public"."is_context_member"("context_id"));



CREATE POLICY "comments_update_actor" ON "public"."comments" FOR UPDATE TO "authenticated" USING (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "comments"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "comments"."actor_id")))))) WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "comments"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "comments"."actor_id"))))));



ALTER TABLE "public"."content_suppressions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_suppressions_insert_global_admin" ON "public"."content_suppressions" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_global_admin"("public"."current_account_id"()) AND ("created_by_account_id" = "public"."current_account_id"())));



CREATE POLICY "content_suppressions_select_global_admin" ON "public"."content_suppressions" FOR SELECT TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"()));



CREATE POLICY "content_suppressions_update_global_admin" ON "public"."content_suppressions" FOR UPDATE TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"())) WITH CHECK ("public"."is_global_admin"("public"."current_account_id"()));



ALTER TABLE "public"."context_actor_identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."context_keys" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "context_keys_insert_member" ON "public"."context_keys" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_members" "cm"
  WHERE (("cm"."context_id" = "context_keys"."context_id") AND ("cm"."account_id" = "context_keys"."account_id"))))));



CREATE POLICY "context_keys_select_self" ON "public"."context_keys" FOR SELECT TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) AND "public"."is_context_member"("context_id")));



CREATE POLICY "context_keys_update_member" ON "public"."context_keys" FOR UPDATE TO "authenticated" USING ("public"."is_context_member"("context_id")) WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_members" "cm"
  WHERE (("cm"."context_id" = "context_keys"."context_id") AND ("cm"."account_id" = "context_keys"."account_id"))))));



ALTER TABLE "public"."context_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "context_members_delete_self" ON "public"."context_members" FOR DELETE TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "context_members_insert_self" ON "public"."context_members" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "public"."current_account_id"()));



CREATE POLICY "context_members_select_member" ON "public"."context_members" FOR SELECT TO "authenticated" USING ("public"."is_context_member"("context_id"));



ALTER TABLE "public"."contexts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contexts_insert_authenticated" ON "public"."contexts" FOR INSERT TO "authenticated" WITH CHECK (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "contexts_select_member" ON "public"."contexts" FOR SELECT TO "authenticated" USING ("public"."is_context_member"("id"));



CREATE POLICY "contexts_update_member" ON "public"."contexts" FOR UPDATE TO "authenticated" USING ("public"."is_context_member"("id")) WITH CHECK ("public"."is_context_member"("id"));



ALTER TABLE "public"."device_push_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_push_tokens_delete_self" ON "public"."device_push_tokens" FOR DELETE TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "device_push_tokens_insert_self" ON "public"."device_push_tokens" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "public"."current_account_id"()));



CREATE POLICY "device_push_tokens_select_self" ON "public"."device_push_tokens" FOR SELECT TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "device_push_tokens_update_self" ON "public"."device_push_tokens" FOR UPDATE TO "authenticated" USING (("account_id" = "public"."current_account_id"())) WITH CHECK (("account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."dm_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_messages_insert_actor_member" ON "public"."dm_messages" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_thread_member"("thread_id") AND (EXISTS ( SELECT 1
   FROM "public"."thread_actor_identities" "tai"
  WHERE (("tai"."thread_id" = "dm_messages"."thread_id") AND ("tai"."account_id" = "public"."current_account_id"()) AND ("tai"."actor_id" = "dm_messages"."actor_id"))))));



CREATE POLICY "dm_messages_select_member" ON "public"."dm_messages" FOR SELECT TO "authenticated" USING ("public"."is_thread_member"("thread_id"));



ALTER TABLE "public"."dm_thread_keys" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_thread_keys_select_self" ON "public"."dm_thread_keys" FOR SELECT TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) AND "public"."is_thread_member"("thread_id")));



CREATE POLICY "dm_thread_keys_update_member" ON "public"."dm_thread_keys" FOR UPDATE TO "authenticated" USING ("public"."is_thread_member"("thread_id")) WITH CHECK (("public"."is_thread_member"("thread_id") AND (EXISTS ( SELECT 1
   FROM "public"."dm_thread_members" "tm"
  WHERE (("tm"."thread_id" = "dm_thread_keys"."thread_id") AND ("tm"."account_id" = "dm_thread_keys"."account_id"))))));



CREATE POLICY "dm_thread_keys_upsert_member" ON "public"."dm_thread_keys" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_thread_member"("thread_id") AND (EXISTS ( SELECT 1
   FROM "public"."dm_thread_members" "tm"
  WHERE (("tm"."thread_id" = "dm_thread_keys"."thread_id") AND ("tm"."account_id" = "dm_thread_keys"."account_id"))))));



ALTER TABLE "public"."dm_thread_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_thread_members_delete_self" ON "public"."dm_thread_members" FOR DELETE TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "dm_thread_members_insert_member" ON "public"."dm_thread_members" FOR INSERT TO "authenticated" WITH CHECK ((("account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."dm_thread_members" "tm"
  WHERE (("tm"."thread_id" = "dm_thread_members"."thread_id") AND ("tm"."account_id" = "public"."current_account_id"()))))));



CREATE POLICY "dm_thread_members_select_member" ON "public"."dm_thread_members" FOR SELECT TO "authenticated" USING ("public"."is_thread_member"("thread_id"));



CREATE POLICY "dm_thread_members_update_self" ON "public"."dm_thread_members" FOR UPDATE TO "authenticated" USING (("account_id" = "public"."current_account_id"())) WITH CHECK (("account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."dm_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_threads_insert_authenticated" ON "public"."dm_threads" FOR INSERT TO "authenticated" WITH CHECK (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "dm_threads_select_member" ON "public"."dm_threads" FOR SELECT TO "authenticated" USING ("public"."is_thread_member"("id"));



CREATE POLICY "dm_threads_update_member" ON "public"."dm_threads" FOR UPDATE TO "authenticated" USING ("public"."is_thread_member"("id")) WITH CHECK ("public"."is_thread_member"("id"));



ALTER TABLE "public"."employee_count_submissions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "employee_count_submissions_insert_self" ON "public"."employee_count_submissions" FOR INSERT TO "authenticated" WITH CHECK ((("account_id" = "public"."current_account_id"()) AND "public"."is_location_member"("location_id")));



CREATE POLICY "employee_count_submissions_select_member" ON "public"."employee_count_submissions" FOR SELECT TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) OR "public"."is_location_member"("location_id")));



CREATE POLICY "employee_count_submissions_update_self" ON "public"."employee_count_submissions" FOR UPDATE TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) AND "public"."is_location_member"("location_id"))) WITH CHECK ((("account_id" = "public"."current_account_id"()) AND "public"."is_location_member"("location_id")));



ALTER TABLE "public"."encrypted_media" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."encrypted_media_access" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "encrypted_media_access_delete_granter" ON "public"."encrypted_media_access" FOR DELETE TO "authenticated" USING ((("granted_by_account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."encrypted_media" "em"
  WHERE (("em"."id" = "encrypted_media_access"."media_id") AND ("em"."uploader_account_id" = "public"."current_account_id"()))))));



CREATE POLICY "encrypted_media_access_insert_granter" ON "public"."encrypted_media_access" FOR INSERT TO "authenticated" WITH CHECK ((("granted_by_account_id" = "public"."current_account_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."encrypted_media" "em"
  WHERE (("em"."id" = "encrypted_media_access"."media_id") AND ("em"."uploader_account_id" = "public"."current_account_id"())))) AND ((("scope_type" = 'context'::"text") AND "public"."is_context_member"("scope_id")) OR (("scope_type" = 'dm_thread'::"text") AND "public"."is_thread_member"("scope_id")))));



CREATE POLICY "encrypted_media_access_select_accessible" ON "public"."encrypted_media_access" FOR SELECT TO "authenticated" USING ((("granted_by_account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."encrypted_media" "em"
  WHERE (("em"."id" = "encrypted_media_access"."media_id") AND ("em"."uploader_account_id" = "public"."current_account_id"())))) OR ((("scope_type" = 'context'::"text") AND "public"."is_context_member"("scope_id")) OR (("scope_type" = 'dm_thread'::"text") AND "public"."is_thread_member"("scope_id")))));



CREATE POLICY "encrypted_media_delete_self" ON "public"."encrypted_media" FOR DELETE TO "authenticated" USING (("uploader_account_id" = "public"."current_account_id"()));



CREATE POLICY "encrypted_media_insert_self" ON "public"."encrypted_media" FOR INSERT TO "authenticated" WITH CHECK (("uploader_account_id" = "public"."current_account_id"()));



CREATE POLICY "encrypted_media_select_accessible" ON "public"."encrypted_media" FOR SELECT TO "authenticated" USING ((("uploader_account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM "public"."encrypted_media_access" "ema"
  WHERE (("ema"."media_id" = "encrypted_media"."id") AND ((("ema"."scope_type" = 'context'::"text") AND "public"."is_context_member"("ema"."scope_id")) OR (("ema"."scope_type" = 'dm_thread'::"text") AND "public"."is_thread_member"("ema"."scope_id"))))))));



CREATE POLICY "encrypted_media_update_self" ON "public"."encrypted_media" FOR UPDATE TO "authenticated" USING (("uploader_account_id" = "public"."current_account_id"())) WITH CHECK (("uploader_account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."feedback" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_insert_self" ON "public"."feedback" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "public"."current_account_id"()));



CREATE POLICY "feedback_select_self_or_global_admin" ON "public"."feedback" FOR SELECT TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) OR "public"."is_global_admin"("public"."current_account_id"())));



CREATE POLICY "feedback_update_global_admin" ON "public"."feedback" FOR UPDATE TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"())) WITH CHECK ("public"."is_global_admin"("public"."current_account_id"()));



ALTER TABLE "public"."global_admins" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "global_admins_select_self_or_global_admin" ON "public"."global_admins" FOR SELECT TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) OR "public"."is_global_admin"("public"."current_account_id"())));



ALTER TABLE "public"."location_status" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "location_status_select_authenticated" ON "public"."location_status" FOR SELECT TO "authenticated" USING (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "location_status_update_location_member" ON "public"."location_status" FOR UPDATE TO "authenticated" USING ("public"."is_location_member"("location_id")) WITH CHECK ("public"."is_location_member"("location_id"));



CREATE POLICY "location_status_upsert_location_member" ON "public"."location_status" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_location_member"("location_id"));



ALTER TABLE "public"."locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "locations_select_authenticated" ON "public"."locations" FOR SELECT TO "authenticated" USING (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "locations_update_location_member" ON "public"."locations" FOR UPDATE TO "authenticated" USING ("public"."is_location_member"("id")) WITH CHECK ("public"."is_location_member"("id"));



ALTER TABLE "public"."moderation_actions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "moderation_actions_insert_global_admin" ON "public"."moderation_actions" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_global_admin"("public"."current_account_id"()) AND ("admin_account_id" = "public"."current_account_id"())));



CREATE POLICY "moderation_actions_select_own_or_global_admin" ON "public"."moderation_actions" FOR SELECT TO "authenticated" USING (("public"."is_global_admin"("public"."current_account_id"()) OR ("target_account_id" = "public"."current_account_id"())));



CREATE POLICY "moderation_actions_update_global_admin" ON "public"."moderation_actions" FOR UPDATE TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"())) WITH CHECK ("public"."is_global_admin"("public"."current_account_id"()));



ALTER TABLE "public"."moderation_appeals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "moderation_appeals_insert_self" ON "public"."moderation_appeals" FOR INSERT TO "authenticated" WITH CHECK (("appellant_account_id" = "public"."current_account_id"()));



CREATE POLICY "moderation_appeals_select_self_or_global_admin" ON "public"."moderation_appeals" FOR SELECT TO "authenticated" USING ((("appellant_account_id" = "public"."current_account_id"()) OR "public"."is_global_admin"("public"."current_account_id"())));



CREATE POLICY "moderation_appeals_update_global_admin" ON "public"."moderation_appeals" FOR UPDATE TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"())) WITH CHECK ("public"."is_global_admin"("public"."current_account_id"()));



ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_queue_insert_authenticated" ON "public"."notification_queue" FOR INSERT TO "authenticated" WITH CHECK (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "notification_queue_select_self" ON "public"."notification_queue" FOR SELECT TO "authenticated" USING (("account_id" = "public"."current_account_id"()));



CREATE POLICY "notification_queue_update_self" ON "public"."notification_queue" FOR UPDATE TO "authenticated" USING (("account_id" = "public"."current_account_id"())) WITH CHECK (("account_id" = "public"."current_account_id"()));



ALTER TABLE "public"."post_likes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "post_likes_delete_self_or_actor" ON "public"."post_likes" FOR DELETE TO "authenticated" USING ((("account_id" = "public"."current_account_id"()) OR (EXISTS ( SELECT 1
   FROM ("public"."posts" "p"
     JOIN "public"."context_actor_identities" "cai" ON ((("cai"."context_id" = "p"."context_id") AND ("cai"."actor_id" = "p"."actor_id"))))
  WHERE (("p"."id" = "post_likes"."post_id") AND ("cai"."account_id" = "public"."current_account_id"()))))));



CREATE POLICY "post_likes_insert_self" ON "public"."post_likes" FOR INSERT TO "authenticated" WITH CHECK ((("account_id" = "public"."current_account_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."posts" "p"
  WHERE (("p"."id" = "post_likes"."post_id") AND "public"."is_context_member"("p"."context_id"))))));



CREATE POLICY "post_likes_select_member" ON "public"."post_likes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."posts" "p"
  WHERE (("p"."id" = "post_likes"."post_id") AND "public"."is_context_member"("p"."context_id")))));



ALTER TABLE "public"."posts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "posts_delete_actor" ON "public"."posts" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "posts"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "posts"."actor_id")))));



CREATE POLICY "posts_insert_actor_member" ON "public"."posts" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "posts"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "posts"."actor_id"))))));



CREATE POLICY "posts_select_member" ON "public"."posts" FOR SELECT TO "authenticated" USING ("public"."is_context_member"("context_id"));



CREATE POLICY "posts_update_actor" ON "public"."posts" FOR UPDATE TO "authenticated" USING (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "posts"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "posts"."actor_id")))))) WITH CHECK (("public"."is_context_member"("context_id") AND (EXISTS ( SELECT 1
   FROM "public"."context_actor_identities" "cai"
  WHERE (("cai"."context_id" = "posts"."context_id") AND ("cai"."account_id" = "public"."current_account_id"()) AND ("cai"."actor_id" = "posts"."actor_id"))))));



ALTER TABLE "public"."reports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reports_insert_self" ON "public"."reports" FOR INSERT TO "authenticated" WITH CHECK ((("reporter_account_id" = "public"."current_account_id"()) AND ((((("reported_post_id" IS NOT NULL))::integer + (("reported_comment_id" IS NOT NULL))::integer) + (("reported_dm_message_id" IS NOT NULL))::integer) = 1)));



CREATE POLICY "reports_select_self_or_global_admin" ON "public"."reports" FOR SELECT TO "authenticated" USING ((("reporter_account_id" = "public"."current_account_id"()) OR "public"."is_global_admin"("public"."current_account_id"())));



CREATE POLICY "reports_update_global_admin" ON "public"."reports" FOR UPDATE TO "authenticated" USING ("public"."is_global_admin"("public"."current_account_id"())) WITH CHECK ("public"."is_global_admin"("public"."current_account_id"()));



ALTER TABLE "public"."thread_actor_identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."unions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "unions_insert_authenticated" ON "public"."unions" FOR INSERT TO "authenticated" WITH CHECK (("public"."current_account_id"() IS NOT NULL));



CREATE POLICY "unions_select_authenticated" ON "public"."unions" FOR SELECT TO "authenticated" USING (("public"."current_account_id"() IS NOT NULL));



ALTER TABLE "public"."user_notification_preferences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_notification_preferences_insert_self" ON "public"."user_notification_preferences" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "public"."current_account_id"()));



CREATE POLICY "user_notification_preferences_select_self" ON "public"."user_notification_preferences" FOR SELECT TO "authenticated" USING (("user_id" = "public"."current_account_id"()));



CREATE POLICY "user_notification_preferences_update_self" ON "public"."user_notification_preferences" FOR UPDATE TO "authenticated" USING (("user_id" = "public"."current_account_id"())) WITH CHECK (("user_id" = "public"."current_account_id"()));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."current_account_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_account_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_context_member"("p_context_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_context_member"("p_context_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_context_member"("p_context_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_global_admin"("p_account_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_global_admin"("p_account_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_global_admin"("p_account_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_location_member"("p_location_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_location_member"("p_location_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_location_member"("p_location_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_thread_member"("p_thread_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_thread_member"("p_thread_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_thread_member"("p_thread_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."issue_card_receipt_submission_token"("p_location_id" "uuid", "p_ttl_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."issue_card_receipt_submission_token"("p_location_id" "uuid", "p_ttl_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."issue_card_receipt_submission_token"("p_location_id" "uuid", "p_ttl_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_user_notification_preferences_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_notification_preferences_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_notification_preferences_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."shares_context_with_current"("p_account_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."shares_context_with_current"("p_account_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."shares_context_with_current"("p_account_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_card_receipt_with_token"("p_location_id" "uuid", "p_receipt_hash" "text", "p_nullifier_hash" "text", "p_submission_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."submit_card_receipt_with_token"("p_location_id" "uuid", "p_receipt_hash" "text", "p_nullifier_hash" "text", "p_submission_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_card_receipt_with_token"("p_location_id" "uuid", "p_receipt_hash" "text", "p_nullifier_hash" "text", "p_submission_token" "text") TO "service_role";



GRANT ALL ON TABLE "public"."account_bans" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."account_bans" TO "authenticated";



GRANT ALL ON TABLE "public"."account_devices" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."account_devices" TO "authenticated";



GRANT ALL ON TABLE "public"."account_session_challenges" TO "service_role";



GRANT ALL ON TABLE "public"."accounts" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."accounts" TO "authenticated";



GRANT ALL ON TABLE "public"."billing_gated_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."blocked_users" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."blocked_users" TO "authenticated";



GRANT ALL ON TABLE "public"."card_receipt_submission_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."card_receipts" TO "service_role";
GRANT SELECT,DELETE,UPDATE ON TABLE "public"."card_receipts" TO "authenticated";



GRANT ALL ON TABLE "public"."comment_likes" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."comment_likes" TO "authenticated";



GRANT ALL ON TABLE "public"."comments" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."comments" TO "authenticated";



GRANT ALL ON TABLE "public"."content_suppressions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."content_suppressions" TO "authenticated";



GRANT ALL ON TABLE "public"."context_actor_identities" TO "service_role";



GRANT ALL ON TABLE "public"."context_keys" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."context_keys" TO "authenticated";



GRANT ALL ON TABLE "public"."context_members" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."context_members" TO "authenticated";



GRANT ALL ON TABLE "public"."contexts" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."contexts" TO "authenticated";



GRANT ALL ON TABLE "public"."device_push_tokens" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."device_push_tokens" TO "authenticated";



GRANT ALL ON TABLE "public"."dm_messages" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."dm_messages" TO "authenticated";



GRANT ALL ON TABLE "public"."dm_thread_keys" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."dm_thread_keys" TO "authenticated";



GRANT ALL ON TABLE "public"."dm_thread_members" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."dm_thread_members" TO "authenticated";



GRANT ALL ON TABLE "public"."dm_threads" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."dm_threads" TO "authenticated";



GRANT ALL ON TABLE "public"."employee_count_submissions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."employee_count_submissions" TO "authenticated";



GRANT ALL ON TABLE "public"."employers" TO "anon";
GRANT ALL ON TABLE "public"."employers" TO "authenticated";
GRANT ALL ON TABLE "public"."employers" TO "service_role";



GRANT ALL ON TABLE "public"."encrypted_media" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."encrypted_media" TO "authenticated";



GRANT ALL ON TABLE "public"."encrypted_media_access" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."encrypted_media_access" TO "authenticated";



GRANT ALL ON TABLE "public"."feedback" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."feedback" TO "authenticated";



GRANT ALL ON TABLE "public"."global_admins" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."global_admins" TO "authenticated";



GRANT ALL ON TABLE "public"."location_status" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."location_status" TO "authenticated";



GRANT ALL ON TABLE "public"."locations" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."locations" TO "authenticated";



GRANT ALL ON TABLE "public"."moderation_actions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."moderation_actions" TO "authenticated";



GRANT ALL ON TABLE "public"."moderation_appeals" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."moderation_appeals" TO "authenticated";



GRANT ALL ON TABLE "public"."notification_queue" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."notification_queue" TO "authenticated";



GRANT ALL ON TABLE "public"."post_likes" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."post_likes" TO "authenticated";



GRANT ALL ON TABLE "public"."post_shares" TO "anon";
GRANT ALL ON TABLE "public"."post_shares" TO "authenticated";
GRANT ALL ON TABLE "public"."post_shares" TO "service_role";



GRANT ALL ON TABLE "public"."posts" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."posts" TO "authenticated";



GRANT ALL ON TABLE "public"."reports" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."reports" TO "authenticated";



GRANT ALL ON TABLE "public"."thread_actor_identities" TO "service_role";



GRANT ALL ON TABLE "public"."unions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."unions" TO "authenticated";



GRANT ALL ON TABLE "public"."user_notification_preferences" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."user_notification_preferences" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







