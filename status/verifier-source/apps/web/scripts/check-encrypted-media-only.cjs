#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const webRoot = path.resolve(__dirname, "..");

const checks = [
  {
    file: "src/app/api/upload/route.js",
    patterns: ["PLAINTEXT_UPLOAD_DISABLED", "status: 410"],
    allowMissing: true,
  },
  {
    file: "src/app/api/upload-image/route.js",
    patterns: ["PLAINTEXT_UPLOAD_DISABLED", "status: 410"],
    allowMissing: true,
  },
  {
    file: "src/app/api/media/moderate-image/route.js",
    mustNotExist: true,
  },
  {
    file: "src/server/domains/contexts-domain.js",
    patterns: ["Plaintext image_url is disabled", "insertData.image_url = null"],
    allowMissing: false,
  },
  {
    file: "src/server/domains/media-domain.js",
    patterns: [],
    disallowPatterns: [
      "export async function handlePostUpload(",
      "export async function handlePostUploadImage(",
      "export async function handleModerateImage(",
      "moderateImageBlob",
    ],
    allowMissing: false,
  },
  {
    file: "src/lib/e2ee-client.js",
    patterns: [],
    disallowPatterns: ["/api/media/moderate-image"],
    allowMissing: false,
  },
];

const failures = [];

for (const check of checks) {
  const absPath = path.join(webRoot, check.file);
  if (!fs.existsSync(absPath)) {
    if (check.mustNotExist) {
      continue;
    }
    if (check.allowMissing) {
      continue;
    }
    failures.push(`${check.file} is missing`);
    continue;
  }
  if (check.mustNotExist) {
    failures.push(`${check.file} should be removed`);
    continue;
  }

  const source = fs.readFileSync(absPath, "utf8");
  const missingPatterns = check.patterns.filter((pattern) => !source.includes(pattern));
  if (missingPatterns.length > 0) {
    failures.push(
      `${check.file} is missing required markers: ${missingPatterns.join(", ")}`,
    );
  }
  const disallowPatterns = Array.isArray(check.disallowPatterns) ? check.disallowPatterns : [];
  const presentDisallow = disallowPatterns.filter((pattern) => source.includes(pattern));
  if (presentDisallow.length > 0) {
    failures.push(
      `${check.file} includes forbidden plaintext handlers: ${presentDisallow.join(", ")}`,
    );
  }
}

if (failures.length > 0) {
  console.error("[encrypted-media-only] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[encrypted-media-only] OK");
