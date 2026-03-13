#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..", "..", "..");

const requiredChecks = [
  {
    file: "apps/web/src/app/api/member-profile/route.js",
    patterns: [
      "MEMBER_PROFILE_LINKING_DISABLED",
      "status: 410",
    ],
  },
  {
    file: "apps/web/src/app/app/union/page.js",
    patterns: ['redirect("/app")'],
  },
  {
    file: "apps/web/src/app/app/union/join/page.js",
    patterns: ['redirect("/app")'],
  },
  {
    file: "apps/mobile/app/(tabs)/union.tsx",
    patterns: ['router.replace("/(tabs)/feed"'],
  },
  {
    file: "apps/mobile/app/union/join.tsx",
    patterns: ['router.replace("/(tabs)/feed"'],
  },
];

const forbiddenChecks = [
  {
    file: "apps/web/src/app/app/layout.js",
    patterns: ["/app/union"],
  },
  {
    file: "apps/mobile/app/(tabs)/_layout.tsx",
    patterns: ['name="union"'],
  },
  {
    file: "apps/mobile/components/NotificationHandler.tsx",
    patterns: ["/(tabs)/union"],
  },
  {
    file: "packages/api-client/src/uniform-zk-client.js",
    patterns: ["memberProfile"],
  },
  {
    file: "packages/api-client/src/index.d.ts",
    patterns: ["memberProfile"],
  },
];

const failures = [];

for (const check of requiredChecks) {
  const absPath = path.join(repoRoot, check.file);
  if (!fs.existsSync(absPath)) {
    failures.push(`Missing required file: ${check.file}`);
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

for (const check of forbiddenChecks) {
  const absPath = path.join(repoRoot, check.file);
  if (!fs.existsSync(absPath)) {
    failures.push(`Missing checked file: ${check.file}`);
    continue;
  }

  const source = fs.readFileSync(absPath, "utf8");
  const presentPatterns = check.patterns.filter((pattern) => source.includes(pattern));
  if (presentPatterns.length > 0) {
    failures.push(
      `${check.file} still contains removed union surface markers: ${presentPatterns.join(", ")}`,
    );
  }
}

if (failures.length > 0) {
  console.error("[union-runtime-removal] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[union-runtime-removal] OK");
