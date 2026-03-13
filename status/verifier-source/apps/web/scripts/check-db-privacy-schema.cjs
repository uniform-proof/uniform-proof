#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const schemaPath = path.resolve(__dirname, "../uniform-zk-db/supabase/schema.sql");

function extractTableBlock(schema, tableName) {
  const pattern = new RegExp(
    `CREATE TABLE IF NOT EXISTS "public"\\."${tableName}" \\(([^]*?)\\n\\);`,
    "m",
  );
  const match = schema.match(pattern);
  return match ? match[0] : null;
}

if (!fs.existsSync(schemaPath)) {
  console.error("[db-privacy-schema] Failed:");
  console.error(" - Missing schema snapshot: uniform-zk-db/supabase/schema.sql");
  process.exit(1);
}

const schema = fs.readFileSync(schemaPath, "utf8");
const failures = [];

const actorOnlyTables = [
  { table: "posts", forbidden: ['"author_account_id"'] },
  { table: "comments", forbidden: ['"author_account_id"'] },
  { table: "dm_messages", forbidden: ['"sender_account_id"'] },
];

for (const check of actorOnlyTables) {
  const block = extractTableBlock(schema, check.table);
  if (!block) {
    failures.push(`Missing expected table definition: ${check.table}`);
    continue;
  }

  const presentPatterns = check.forbidden.filter((pattern) => block.includes(pattern));
  if (presentPatterns.length > 0) {
    failures.push(
      `${check.table} still contains forbidden direct account-id columns: ${presentPatterns.join(", ")}`,
    );
  }
}

const removedTables = [
  "account_member_links",
  "member_profiles",
  "account_entitlements",
  "entitlements",
  "account_auth_identities",
];

for (const table of removedTables) {
  if (extractTableBlock(schema, table)) {
    failures.push(`Legacy runtime table still present in schema snapshot: ${table}`);
  }
}

const sessionTable = extractTableBlock(schema, "account_session_challenges");
if (!sessionTable) {
  failures.push("Missing expected auth/session table definition: account_session_challenges");
} else {
  const forbiddenSessionPatterns = [
    { label: "IP field", regex: /\bip(_address)?\b/i },
    { label: "fingerprint field", regex: /\bfingerprint\b/i },
    { label: "user-agent field", regex: /\buser_agent\b/i },
    { label: "browser field", regex: /\bbrowser\b/i },
  ];

  for (const pattern of forbiddenSessionPatterns) {
    if (pattern.regex.test(sessionTable)) {
      failures.push(
        `account_session_challenges still contains forbidden ${pattern.label} marker`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error("[db-privacy-schema] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[db-privacy-schema] OK");
