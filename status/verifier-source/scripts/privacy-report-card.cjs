#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execSync, spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const defaultOutDir = path.join(repoRoot, "artifacts", "privacy-report-card");
const defaultDetailsUrl =
  "https://github.com/uniform-proof/uniform-proof/blob/main/status/privacy-report-card.md";
const defaultClaimMapUrl =
  "https://github.com/uniform-proof/uniform-proof/blob/main/status/worker-privacy-claim-map.json";
const defaultVerifierSourceUrl =
  "https://github.com/uniform-proof/uniform-proof/tree/main/status/verifier-source";
const localClaimMapPath = path.join(repoRoot, "scripts", "privacy-report-claims.json");

const checks = [
  {
    name: "Privacy hardening guardrails",
    command: "npm run check:privacy-hardening --workspace=apps/web",
  },
  {
    name: "Privacy hardening QA suite",
    command: "npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js",
  },
  {
    name: "Billing gate auth suite",
    command: "npm run test --workspace=apps/web -- src/server/domains/__tests__/auth-domain-billing-gate.test.js",
  },
];

const verifierSourceFiles = [
  ".github/workflows/privacy-report-card.yml",
  "scripts/privacy-report-card.cjs",
  "scripts/privacy-report-claims.json",
  "apps/web/scripts/check-boundary.cjs",
  "apps/web/scripts/check-active-runtime.cjs",
  "apps/web/scripts/check-service-role-allowlist.cjs",
  "apps/web/scripts/check-encrypted-media-only.cjs",
  "apps/web/scripts/check-rls-hardening.cjs",
  "apps/web/scripts/check-billing-vault-integration.cjs",
  "apps/web/scripts/check-actor-id-mode.cjs",
  "apps/web/scripts/check-auth-metadata-guardrails.cjs",
  "apps/web/scripts/check-db-privacy-schema.cjs",
  "apps/web/scripts/check-union-runtime-removal.cjs",
  "apps/web/uniform-zk-db/supabase/migrations/20260305010000_hard_cut_app_sessions.sql",
  "apps/web/uniform-zk-db/supabase/migrations/20260306011000_add_billing_gated_accounts.sql",
  "apps/web/uniform-zk-db/supabase/migrations/20260311110000_actor_hard_cut_cleanup.sql",
  "apps/web/uniform-zk-db/supabase/schema.sql",
  "apps/web/src/server/domains/__tests__/privacy-hardening-qa.test.js",
  "apps/web/src/server/domains/__tests__/auth-domain-billing-gate.test.js",
];

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === "--out-dir") {
      args.outDir = argv[i + 1];
      i += 1;
      continue;
    }
    if (value === "--details-url") {
      args.detailsUrl = argv[i + 1];
      i += 1;
      continue;
    }
    if (value === "--claim-map-url") {
      args.claimMapUrl = argv[i + 1];
      i += 1;
      continue;
    }
    if (value === "--verifier-source-url") {
      args.verifierSourceUrl = argv[i + 1];
      i += 1;
      continue;
    }
  }
  return args;
}

function resolveGitSha() {
  if (process.env.GITHUB_SHA) {
    return String(process.env.GITHUB_SHA).trim();
  }
  try {
    return execSync("git rev-parse HEAD", { cwd: repoRoot, encoding: "utf8" }).trim();
  } catch {
    return "unknown";
  }
}

function resolveSourceRepo() {
  if (process.env.GITHUB_REPOSITORY) {
    return `https://github.com/${String(process.env.GITHUB_REPOSITORY).trim()}`;
  }
  try {
    const remote = execSync("git config --get remote.origin.url", {
      cwd: repoRoot,
      encoding: "utf8",
    }).trim();
    if (!remote) return "unknown";
    if (remote.startsWith("git@github.com:")) {
      return `https://github.com/${remote.replace("git@github.com:", "").replace(/\.git$/, "")}`;
    }
    return remote.replace(/\.git$/, "");
  } catch {
    return "unknown";
  }
}

function resolveRunUrl() {
  const server = String(process.env.GITHUB_SERVER_URL || "").trim();
  const repository = String(process.env.GITHUB_REPOSITORY || "").trim();
  const runId = String(process.env.GITHUB_RUN_ID || "").trim();
  if (!server || !repository || !runId) return null;
  return `${server}/${repository}/actions/runs/${runId}`;
}

function sha256Buffer(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function loadClaimMap() {
  const raw = fs.readFileSync(localClaimMapPath, "utf8");
  return JSON.parse(raw);
}

function writeClaimMap(outDir, claimMap) {
  const outputPath = path.join(outDir, "worker-privacy-claim-map.json");
  fs.writeFileSync(outputPath, `${JSON.stringify(claimMap, null, 2)}\n`, "utf8");
  return {
    file: "worker-privacy-claim-map.json",
    sha256: sha256File(outputPath),
    path: outputPath,
  };
}

function copyVerifierSources(outDir) {
  const outputRoot = path.join(outDir, "verifier-source");
  const files = [];

  for (const relativePath of verifierSourceFiles) {
    const sourcePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing verifier-source file: ${relativePath}`);
    }

    const targetPath = path.join(outputRoot, relativePath);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.copyFileSync(sourcePath, targetPath);
    const stats = fs.statSync(targetPath);
    files.push({
      path: `verifier-source/${relativePath}`,
      exists: true,
      bytes: stats.size,
      sha256: sha256File(targetPath),
    });
  }

  return {
    directory: "verifier-source",
    file_count: files.filter((file) => file.exists).length,
    files,
  };
}

function runCheck(check) {
  const startedAt = Date.now();
  const result = spawnSync(check.command, {
    cwd: repoRoot,
    shell: true,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 16 * 1024 * 1024,
  });
  const finishedAt = Date.now();
  const exitCode = Number.isInteger(result.status) ? result.status : 1;
  const status = exitCode === 0 ? "PASS" : "FAIL";

  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }

  return {
    name: check.name,
    command: check.command,
    status,
    exit_code: exitCode,
    duration_ms: finishedAt - startedAt,
  };
}

function buildMarkdown(report) {
  const lines = [];
  lines.push("# Worker Privacy Report Card");
  lines.push("");
  lines.push(`- Overall status: **${report.overall_status}**`);
  lines.push(`- Generated at (UTC): ${report.generated_at_utc}`);
  lines.push(`- Source repo: ${report.source_repo}`);
  lines.push(`- Source commit: \`${report.source_commit_sha}\``);
  if (report.verification_run_url) {
    lines.push(`- Verification run: ${report.verification_run_url}`);
  }
  lines.push(`- Claim map: ${report.claim_map.public_url}`);
  lines.push(`- Verifier source snapshot: ${report.verifier_source.public_url}`);
  lines.push("");
  lines.push("## Check Results");
  lines.push("");
  lines.push("| Check | Status | Duration (ms) |");
  lines.push("| --- | --- | ---: |");
  for (const check of report.checks) {
    lines.push(`| ${check.name} | ${check.status} | ${check.duration_ms} |`);
  }
  lines.push("");
  lines.push("## Commands");
  lines.push("");
  for (const check of report.checks) {
    lines.push(`- \`${check.command}\``);
  }
  lines.push("");
  lines.push("## Claims Covered");
  lines.push("");
  const claims = Array.isArray(report.claims?.claims) ? report.claims.claims : [];
  if (claims.length === 0) {
    lines.push("- No claim map available.");
  } else {
    for (const claim of claims) {
      const claimId = String(claim?.id || "").trim() || "unknown_claim";
      const statement = String(claim?.statement || "").trim() || "No statement provided.";
      lines.push(`- \`${claimId}\`: ${statement}`);
    }
  }
  lines.push("");
  lines.push("This report publishes reproducible verification evidence for worker-account privacy controls.");
  lines.push("It does not attest to external infrastructure/provider logs outside app DB scope.");
  return `${lines.join("\n")}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const outDir = path.resolve(repoRoot, args.outDir || defaultOutDir);
  const detailsUrl = String(args.detailsUrl || defaultDetailsUrl).trim() || defaultDetailsUrl;
  const claimMapUrl = String(args.claimMapUrl || defaultClaimMapUrl).trim() || defaultClaimMapUrl;
  const verifierSourceUrl =
    String(args.verifierSourceUrl || defaultVerifierSourceUrl).trim() ||
    defaultVerifierSourceUrl;

  fs.mkdirSync(outDir, { recursive: true });
  const claimMap = loadClaimMap();
  const claimMapOutput = writeClaimMap(outDir, claimMap);
  const verifierSource = copyVerifierSources(outDir);
  const checkResults = checks.map((check) => runCheck(check));
  const overallStatus = checkResults.every((check) => check.status === "PASS") ? "PASS" : "FAIL";
  const sourceCommitSha = resolveGitSha();

  const report = {
    schema_version: 2,
    report_name: "Worker Privacy Report Card",
    overall_status: overallStatus,
    generated_at_utc: new Date().toISOString(),
    source_repo: resolveSourceRepo(),
    source_commit_sha: sourceCommitSha,
    verification_run_url: resolveRunUrl(),
    details_url: detailsUrl,
    claim_map: {
      file: claimMapOutput.file,
      sha256: claimMapOutput.sha256,
      public_url: claimMapUrl,
      claim_count: Array.isArray(claimMap?.claims) ? claimMap.claims.length : 0,
    },
    verifier_source: {
      ...verifierSource,
      public_url: verifierSourceUrl,
    },
    claims: claimMap,
    transparency_log_key: `privacy-report-card-${sourceCommitSha}.json`,
    checks: checkResults,
  };

  const jsonPath = path.join(outDir, "privacy-report-card.json");
  const markdownPath = path.join(outDir, "privacy-report-card.md");

  fs.writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.writeFileSync(markdownPath, buildMarkdown(report), "utf8");

  console.log(`[privacy-report-card] overall status: ${overallStatus}`);
  console.log(`[privacy-report-card] wrote ${jsonPath}`);
  console.log(`[privacy-report-card] wrote ${markdownPath}`);
}

main();
