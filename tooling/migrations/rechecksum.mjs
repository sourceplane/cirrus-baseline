#!/usr/bin/env node
// Rewrites the checksums in packages/db/src/manifest.ts to match the migration
// files on disk.
//
// The manifest's checksums are the drift detector: the runner refuses to apply
// a migration whose file no longer matches what the manifest (and the applied
// ledger) recorded. That guard only has teeth if the checksums are generated
// from the files rather than typed by hand — hence this tool.
//
// Run it ONLY when a migration file's content legitimately changed before it
// was ever applied anywhere. Editing an already-applied migration is what the
// guard exists to stop, and rechecksumming it would defeat the guard rather
// than satisfy it.
//
//   node tooling/migrations/rechecksum.mjs [--check]
//
// --check exits non-zero on drift instead of rewriting (for CI).

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const MIGRATIONS = path.join(ROOT, "packages", "db", "src", "migrations");
const MANIFEST = path.join(ROOT, "packages", "db", "src", "manifest.ts");

const checkOnly = process.argv.includes("--check");

function checksum(file) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

const source = fs.readFileSync(MANIFEST, "utf8");

// Each entry is `path: "<dir>/up.sql",` followed by `checksum:\n  "<hex>",`.
const entry = /path:\s*"([^"]+)",\s*\n\s*checksum:\s*\n?\s*"([0-9a-f]{64})"/g;

const drift = [];
const updated = source.replace(entry, (match, relPath, recorded) => {
  const actual = checksum(path.join(MIGRATIONS, relPath));
  if (actual === recorded) return match;
  drift.push({ path: relPath, recorded, actual });
  return match.replace(recorded, actual);
});

if (drift.length === 0) {
  console.log("✓ manifest checksums match every migration file");
  process.exit(0);
}

if (checkOnly) {
  console.error(`✗ ${drift.length} migration checksum(s) drifted from the manifest:`);
  for (const d of drift) console.error(`    ${d.path}\n      manifest ${d.recorded}\n      file     ${d.actual}`);
  process.exit(1);
}

fs.writeFileSync(MANIFEST, updated);
console.log(`✓ rewrote ${drift.length} checksum(s):`);
for (const d of drift) console.log(`    ${d.path} → ${d.actual.slice(0, 12)}…`);
