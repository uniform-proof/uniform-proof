#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const apiRoot = path.resolve(__dirname, "../src/app/api");
const allowlistMatchers = [
  `${path.sep}app${path.sep}api${path.sep}webhooks${path.sep}`,
  `${path.sep}app${path.sep}api${path.sep}public${path.sep}`,
  `${path.sep}app${path.sep}api${path.sep}payment${path.sep}`,
  `${path.sep}app${path.sep}api${path.sep}internal${path.sep}`,
  `${path.sep}app${path.sep}api${path.sep}auth${path.sep}check-handle${path.sep}`,
];

const serviceRolePatterns = [
  /getSupabaseAdminClient/g,
  /SUPABASE_SERVICE_ROLE_KEY/g,
  /@\/supabase-utils\/adminClient/g,
];

function collectFiles(dir, files = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectFiles(fullPath, files);
      continue;
    }
    if (!/\.(js|ts|tsx|mjs|cjs)$/.test(entry.name)) continue;
    files.push(fullPath);
  }
  return files;
}

function isAllowlisted(filePath) {
  return allowlistMatchers.some((segment) => filePath.includes(segment));
}

const files = collectFiles(apiRoot).filter((filePath) => path.basename(filePath) === "route.js");
const violations = [];

for (const filePath of files) {
  if (isAllowlisted(filePath)) continue;
  const source = fs.readFileSync(filePath, "utf8");
  if (serviceRolePatterns.some((pattern) => pattern.test(source))) {
    violations.push(filePath);
  }
}

if (violations.length > 0) {
  console.error("[service-role-allowlist] Found disallowed service-role usage in user routes:");
  for (const violation of violations) {
    console.error(` - ${violation}`);
  }
  process.exit(1);
}

console.log("[service-role-allowlist] OK");
