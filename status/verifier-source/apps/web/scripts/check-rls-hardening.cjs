#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const migrationsRoot = path.resolve(__dirname, "../uniform-zk-db/supabase/migrations");

const checks = [
  {
    file: "20260303183000_privacy_hardening_phase1.sql",
    markers: [
      "CREATE TABLE IF NOT EXISTS public.card_receipt_submission_tokens",
      "CREATE POLICY entitlements_select_owned",
      "DROP POLICY IF EXISTS account_entitlements_insert_self",
      "REVOKE INSERT ON TABLE public.card_receipts FROM authenticated",
      "CREATE TABLE IF NOT EXISTS public.context_actor_identities",
      "CREATE OR REPLACE FUNCTION public.issue_card_receipt_submission_token",
    ],
  },
  {
    file: "20260304110000_actor_identity_backfill_hard_cut.sql",
    markers: [
      "INSERT INTO public.context_actor_identities",
      "INSERT INTO public.thread_actor_identities",
      "ALTER TABLE public.posts",
      "ALTER COLUMN actor_id SET NOT NULL",
      "ALTER TABLE public.comments",
      "ALTER TABLE public.dm_messages",
    ],
  },
  {
    file: "20260304133000_privacy_hard_cut_phase2.sql",
    markers: [
      "CREATE POLICY accounts_select_self",
      "CREATE POLICY accounts_update_self",
      "REVOKE ALL ON TABLE public.context_actor_identities FROM authenticated",
      "REVOKE ALL ON TABLE public.thread_actor_identities FROM authenticated",
      "ALTER TABLE public.card_receipt_submission_tokens",
      "DROP COLUMN IF EXISTS created_by_account_id",
      "REVOKE SELECT ON TABLE public.card_receipt_submission_tokens FROM authenticated",
      "CREATE OR REPLACE FUNCTION public.issue_card_receipt_submission_token",
    ],
  },
  {
    file: "20260304153000_actor_only_content_and_billing_unlink.sql",
    markers: [
      "ALTER TABLE public.posts",
      "ALTER COLUMN author_account_id DROP NOT NULL",
      "ALTER TABLE public.dm_messages",
      "ALTER COLUMN sender_account_id DROP NOT NULL",
      "CREATE TABLE IF NOT EXISTS public.account_subscription_states",
      "DELETE FROM public.account_entitlements",
      "DELETE FROM public.entitlements",
      "DROP FUNCTION IF EXISTS public.redeem_entitlement_token(text)",
    ],
  },
  {
    file: "20260306012000_drop_account_subscription_states_hard_cut.sql",
    markers: [
      "DROP TABLE IF EXISTS public.account_subscription_states CASCADE",
    ],
  },
];

const failures = [];

for (const check of checks) {
  const migrationPath = path.join(migrationsRoot, check.file);
  if (!fs.existsSync(migrationPath)) {
    failures.push(`Missing migration: ${check.file}`);
    continue;
  }

  const source = fs.readFileSync(migrationPath, "utf8");
  const missingMarkers = check.markers.filter((marker) => !source.includes(marker));
  if (missingMarkers.length > 0) {
    failures.push(
      `${check.file} missing markers: ${missingMarkers.join(", ")}`,
    );
  }
}

if (failures.length > 0) {
  console.error("[rls-hardening] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[rls-hardening] OK");
