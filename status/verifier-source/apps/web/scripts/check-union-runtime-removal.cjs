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
    files: [
      "apps/mobile/app/union.tsx",
      "apps/mobile/app/(tabs)/union.tsx",
    ],
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

function getCheckFiles(check) {
  if (Array.isArray(check.files) && check.files.length > 0) {
    return check.files;
  }

  return check.file ? [check.file] : [];
}

for (const check of requiredChecks) {
  const files = getCheckFiles(check);
  const matchedFile = files.find((file) => fs.existsSync(path.join(repoRoot, file)));

  if (!matchedFile) {
    failures.push(`Missing required file: ${files.join(" or ")}`);
    continue;
  }

  const source = fs.readFileSync(path.join(repoRoot, matchedFile), "utf8");
  const missingPatterns = check.patterns.filter((pattern) => !source.includes(pattern));
  if (missingPatterns.length > 0) {
    failures.push(
      `${matchedFile} is missing required markers: ${missingPatterns.join(", ")}`,
    );
  }
}

for (const check of forbiddenChecks) {
  const files = getCheckFiles(check);
  const matchedFile = files.find((file) => fs.existsSync(path.join(repoRoot, file)));

  if (!matchedFile) {
    failures.push(`Missing checked file: ${files.join(" or ")}`);
    continue;
  }

  const source = fs.readFileSync(path.join(repoRoot, matchedFile), "utf8");
  const presentPatterns = check.patterns.filter((pattern) => source.includes(pattern));
  if (presentPatterns.length > 0) {
    failures.push(
      `${matchedFile} still contains removed union surface markers: ${presentPatterns.join(", ")}`,
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
