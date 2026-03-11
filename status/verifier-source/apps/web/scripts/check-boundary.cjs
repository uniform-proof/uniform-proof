#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const activeSrcRoot = path.join(projectRoot, "src");
const configFiles = [
  path.join(projectRoot, "next.config.mjs"),
  path.join(projectRoot, "jsconfig.json"),
  path.join(projectRoot, "package.json"),
];
const sourceExtensions = new Set([".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]);

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, files);
      continue;
    }
    if (sourceExtensions.has(path.extname(entry.name))) {
      files.push(fullPath);
    }
  }
  return files;
}

function findViolations(filePath) {
  const relPath = path.relative(projectRoot, filePath);
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split(/\r?\n/);
  const hits = [];
  const isActiveAppFile = relPath.startsWith(path.join("src", "app") + path.sep);

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();

    if (line.includes("legacy-reference")) {
      hits.push({
        file: relPath,
        line: i + 1,
        text: trimmed,
      });
      continue;
    }

    if (isActiveAppFile && line.includes("@/services/")) {
      hits.push({
        file: relPath,
        line: i + 1,
        text: trimmed,
      });
    }
  }

  return hits;
}

const filesToCheck = [...walk(activeSrcRoot), ...configFiles.filter((f) => fs.existsSync(f))];
const violations = filesToCheck.flatMap(findViolations);
const pagesDir = path.join(projectRoot, "src", "pages");
const legacyStorePath = path.join(projectRoot, "src", "app", "store", "store.js");

if (violations.length > 0) {
  console.error(
    "Boundary check failed. Active code references legacy-reference or imports legacy services:",
  );
  for (const violation of violations) {
    console.error(`- ${violation.file}:${violation.line} ${violation.text}`);
  }
  process.exit(1);
}

if (fs.existsSync(pagesDir)) {
  console.error("Boundary check failed. Active app should not include src/pages.");
  process.exit(1);
}

if (fs.existsSync(legacyStorePath)) {
  console.error(
    "Boundary check failed. src/app/store/store.js should not exist in active runtime.",
  );
  process.exit(1);
}

console.log("Boundary check passed: no active references to legacy-reference found.");
