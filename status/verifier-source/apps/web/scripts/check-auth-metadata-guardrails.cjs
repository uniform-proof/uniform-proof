#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const webRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(webRoot, "..", "..");
const supabaseConfigPath = path.join(webRoot, "uniform-zk-db", "supabase", "config.toml");
const sourceExtensions = new Set([".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]);

const sourceRoots = [
  path.join(webRoot, "src"),
  path.join(repoRoot, "apps", "mobile"),
].filter((dir) => fs.existsSync(dir));

const forbiddenCodePatterns = [
  { label: "supabase.auth runtime usage", regex: /\bsupabase\s*\.\s*auth\b/ },
  { label: "anonymous sign-in usage", regex: /\bsignInAnonymously\s*\(/ },
  { label: "direct GoTrue auth endpoint usage", regex: /\/auth\/v1\b/ },
];

const forbiddenIdentifiers = [
  { label: "legacy account_auth_identities coupling", regex: /\baccount_auth_identities\b/ },
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

function rel(filePath) {
  return path.relative(repoRoot, filePath);
}

function getHits(filePath, checks) {
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split(/\r?\n/);
  const hits = [];

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    for (const check of checks) {
      if (check.regex.test(line)) {
        hits.push({
          file: rel(filePath),
          line: lineIndex + 1,
          label: check.label,
          text: line.trim(),
        });
      }
    }
  }

  return hits;
}

function validateSupabaseAuthConfig() {
  if (!fs.existsSync(supabaseConfigPath)) {
    return [`Missing Supabase config: ${path.relative(repoRoot, supabaseConfigPath)}`];
  }

  const config = fs.readFileSync(supabaseConfigPath, "utf8");
  const failures = [];

  if (!/\[auth\][\s\S]*?\nenable_signup\s*=\s*false\b/.test(config)) {
    failures.push("[auth] enable_signup must be false");
  }

  if (!/\[auth\][\s\S]*?\nenable_anonymous_sign_ins\s*=\s*false\b/.test(config)) {
    failures.push("[auth] enable_anonymous_sign_ins must be false");
  }

  if (!/\[auth\.email\][\s\S]*?\nenable_signup\s*=\s*false\b/.test(config)) {
    failures.push("[auth.email] enable_signup must be false");
  }

  return failures;
}

const failures = [];

const configFailures = validateSupabaseAuthConfig();
for (const failure of configFailures) {
  failures.push({
    type: "config",
    message: failure,
  });
}

const files = sourceRoots.flatMap((root) => walk(root));
for (const filePath of files) {
  const disallowed = [
    ...getHits(filePath, forbiddenCodePatterns),
    ...getHits(filePath, forbiddenIdentifiers),
  ];
  failures.push(...disallowed.map((hit) => ({ type: "source", ...hit })));
}

if (failures.length > 0) {
  console.error("[auth-metadata-guardrails] FAILED");
  for (const failure of failures) {
    if (failure.type === "config") {
      console.error(` - config: ${failure.message}`);
      continue;
    }
    console.error(` - ${failure.file}:${failure.line} [${failure.label}] ${failure.text}`);
  }
  process.exit(1);
}

console.log("[auth-metadata-guardrails] OK");
