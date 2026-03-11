#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const webRoot = path.resolve(__dirname, "..");

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

if (failures.length > 0) {
  console.error("[actor-id-mode] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[actor-id-mode] OK");
