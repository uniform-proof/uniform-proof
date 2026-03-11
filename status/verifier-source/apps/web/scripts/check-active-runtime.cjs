#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const srcRoot = path.join(projectRoot, "src");
const appRoot = path.join(srcRoot, "app");
const sourceExts = [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"];

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, files);
      continue;
    }
    if (sourceExts.includes(path.extname(entry.name))) {
      files.push(fullPath);
    }
  }
  return files;
}

function extractSpecifiers(content) {
  const specs = [];
  const patterns = [
    /import\s+[^'"]*?\sfrom\s*['"]([^'"]+)['"]/g,
    /export\s+[^'"]*?\sfrom\s*['"]([^'"]+)['"]/g,
    /import\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
    /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];

  for (const pattern of patterns) {
    let match = pattern.exec(content);
    while (match) {
      specs.push(match[1]);
      match = pattern.exec(content);
    }
  }

  return specs;
}

function resolveLocalImport(fromFile, spec) {
  let basePath = null;
  if (spec.startsWith("@/")) {
    basePath = path.join(srcRoot, spec.slice(2));
  } else if (spec.startsWith(".")) {
    basePath = path.resolve(path.dirname(fromFile), spec);
  } else {
    return null;
  }

  const candidates = [];
  candidates.push(basePath);
  for (const ext of sourceExts) {
    candidates.push(`${basePath}${ext}`);
  }
  for (const ext of sourceExts) {
    candidates.push(path.join(basePath, `index${ext}`));
  }

  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      return path.normalize(candidate);
    }
  }

  return null;
}

function rel(file) {
  return path.relative(projectRoot, file);
}

const entryFiles = walk(appRoot);
const queue = [...entryFiles];
const visited = new Set();
const violations = [];
const unresolvedLocalImports = [];

while (queue.length > 0) {
  const filePath = queue.shift();
  if (visited.has(filePath)) continue;
  visited.add(filePath);

  const content = fs.readFileSync(filePath, "utf8");
  const specifiers = extractSpecifiers(content);

  for (const spec of specifiers) {
    if (spec.includes("legacy-reference")) {
      violations.push({
        file: rel(filePath),
        type: "legacy-reference import",
        spec,
      });
      continue;
    }

    if (spec.startsWith("@/services/")) {
      violations.push({
        file: rel(filePath),
        type: "legacy services import",
        spec,
      });
      continue;
    }

    if (spec === "@/app/store/store") {
      violations.push({
        file: rel(filePath),
        type: "legacy store import",
        spec,
      });
      continue;
    }

    const resolved = resolveLocalImport(filePath, spec);
    if (!resolved) {
      if (spec.startsWith(".") || spec.startsWith("@/")) {
        unresolvedLocalImports.push({
          file: rel(filePath),
          spec,
        });
      }
      continue;
    }

    if (!resolved.startsWith(srcRoot)) {
      continue;
    }

    if (!visited.has(resolved)) {
      queue.push(resolved);
    }
  }
}

if (violations.length > 0) {
  console.error(
    "Active runtime check failed. Files reachable from src/app import legacy services/reference paths:",
  );
  for (const v of violations) {
    console.error(`- ${v.file} (${v.type}) -> ${v.spec}`);
  }
  process.exit(1);
}

if (unresolvedLocalImports.length > 0) {
  console.warn("Active runtime check warning: unresolved local imports found.");
  for (const item of unresolvedLocalImports.slice(0, 20)) {
    console.warn(`- ${item.file} -> ${item.spec}`);
  }
  if (unresolvedLocalImports.length > 20) {
    console.warn(`...and ${unresolvedLocalImports.length - 20} more`);
  }
}

console.log(
  `Active runtime check passed: ${visited.size} reachable source files from src/app with no legacy service/store imports.`,
);
