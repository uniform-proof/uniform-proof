#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const webRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(webRoot, "..", "..");
const sourceExtensions = new Set([".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]);

const checks = [
  {
    file: "src/server/identity/actor-identity.js",
    patterns: [
      "resolveContextActorIdentityMap",
      "resolveThreadActorIdentityMap",
      "getOrCreateContextActorIdentity",
      "getOrCreateThreadActorIdentity",
    ],
  },
  {
    file: "src/server/domains/contexts-domain.js",
    patterns: ["author_actor_id", "author_display_handle", "getOrCreateContextActorIdentity"],
  },
  {
    file: "src/server/domains/dm-domain.js",
    patterns: ["sender_actor_id", "resolveThreadActorIdentityMap", "getOrCreateThreadActorIdentity"],
  },
  {
    file: "src/server/repositories/contexts-repository.js",
    patterns: ["actor_id"],
  },
  {
    file: "src/server/repositories/dm-repository.js",
    patterns: ["actor_id"],
  },
];

const forbiddenActivePatterns = [
  { label: "legacy post/comment account id field", regex: /\bauthor_account_id\b/ },
  { label: "legacy dm sender account id field", regex: /\bsender_account_id\b/ },
  { label: "legacy thread preview sender account id field", regex: /\blast_message_sender_account_id\b/ },
];

const activeSourceRoots = [
  path.join(webRoot, "src"),
  path.join(repoRoot, "apps", "mobile"),
  path.join(repoRoot, "packages", "api-client"),
];

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === ".next" || entry.name === ".expo") {
        continue;
      }
      walk(fullPath, files);
      continue;
    }
    if (sourceExtensions.has(path.extname(entry.name))) {
      files.push(fullPath);
    }
  }
  return files;
}

const failures = [];

for (const check of checks) {
  const absPath = path.join(webRoot, check.file);
  if (!fs.existsSync(absPath)) {
    failures.push(`${check.file} is missing`);
    continue;
  }

  const source = fs.readFileSync(absPath, "utf8");
  const missingPatterns = check.patterns.filter((pattern) => !source.includes(pattern));
  if (missingPatterns.length > 0) {
    failures.push(
      `${check.file} is missing required markers: ${missingPatterns.join(", ")}`,
    );
  }
}

for (const root of activeSourceRoots) {
  if (!fs.existsSync(root)) continue;
  for (const filePath of walk(root)) {
    if (filePath.includes(`${path.sep}__tests__${path.sep}`)) continue;
    const source = fs.readFileSync(filePath, "utf8");
    for (const check of forbiddenActivePatterns) {
      if (check.regex.test(source)) {
        failures.push(
          `${path.relative(webRoot, filePath)} still references ${check.label}`,
        );
      }
    }
  }
}

if (failures.length > 0) {
  console.error("[actor-id-mode] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[actor-id-mode] OK");
