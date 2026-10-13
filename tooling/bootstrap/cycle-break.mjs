#!/usr/bin/env node
// Two-pass bootstrap for the service-binding cycle (zero-dependency).
//
// The {billing, membership, events, notifications} workers form a service-
// binding cycle (billing <-> membership; membership -> notifications -> events
// -> membership). On a FRESH Cloudflare account this cluster cannot deploy:
// Cloudflare rejects a deploy whose service binding targets a worker that does
// not exist yet (error 10143), and re-running never resolves it because the
// cycle never breaks on its own. See docs/phases/04-workers.md and the
// ACKNOWLEDGED_BINDING_CYCLES set in
// tests/config-worker/src/deployment-config.test.ts.
//
// This tool removes the two minimal feedback edges so the cluster becomes a
// deployable DAG, then restores them once the targets exist:
//
//   1. node tooling/bootstrap/cycle-break.mjs --strip     # pass 1
//      commit + merge  -> cluster deploys (policy -> billing -> membership
//                         -> events -> notifications)
//   2. node tooling/bootstrap/cycle-break.mjs --restore   # pass 2
//      commit + merge  -> billing + membership redeploy with full bindings
//
// Each removed binding (object + its separator comma) is replaced in place by a
// single-line `//` marker that base64-encodes the exact removed text, so
// --restore reproduces the original template byte-for-byte. The marker is a
// line comment, so the stripped template is still valid wrangler JSONC and
// still parses under the deployment-config test's comment-stripping reader.
//
// Modes:
//   --strip     break the cycle (idempotent: skips edges already stripped)
//   --strip --all
//               strip EVERY worker->worker service binding in the fleet, not
//               just the feedback edges. This is what 04-workers runs: with no
//               binding naming another worker, no worker's first deploy needs
//               another to exist, so the whole fleet deploys in one parallel
//               wave instead of the six-deep chain the bindings imply. The
//               second wave (--restore, in 05-edge) redeploys every worker
//               with its bindings at once, when every target already exists.
//   --restore   put the bindings back (idempotent: no-op if none stripped).
//               Restores every marker in every worker template, whichever
//               mode stripped it.
//   --check     report which edges are currently stripped (exit 0)

import * as fs from "node:fs";
import * as path from "node:path";

// The minimal feedback edge set. Mirrors ACKNOWLEDGED_BINDING_CYCLES in
// tests/config-worker/src/deployment-config.test.ts — keep the two in sync.
// Removing `from`'s service binding to `to` makes the cluster acyclic.
const FEEDBACK_EDGES = [
  { from: "billing-worker", to: "membership-worker" },
  { from: "membership-worker", to: "notifications-worker" },
];

const MARKER = "@cycle-break";

function usage() {
  console.error("usage: cycle-break.mjs --strip [--all] | --restore | --check");
  process.exit(2);
}

function wranglerPath(component) {
  return path.join("apps", component, "wrangler.template.jsonc");
}

// Every worker placed in this tree, by directory name. A binding may TARGET
// any of them (policy-worker has no template — nothing to strip in it — but
// half the fleet binds to it); only those with a template can be stripped.
function workers() {
  if (!fs.existsSync("apps")) return [];
  return fs.readdirSync("apps").filter((d) => d.endsWith("-worker")).sort();
}

// The workers whose templates `--all` strips and restore/check visit.
function fleet() {
  return workers().filter((d) => fs.existsSync(wranglerPath(d)));
}

function allEdges() {
  const edges = [];
  for (const from of fleet()) {
    for (const to of workers()) if (to !== from) edges.push({ from, to });
  }
  return edges;
}

// The templates restore/check read: the feedback edges' sources plus the
// whole fleet, de-duplicated.
function templatesToVisit() {
  return [...new Set([...FEEDBACK_EDGES.map((e) => e.from), ...fleet()])];
}

// Find the [start, end) span of the service-binding object whose `service`
// targets `toComponent` (with or without a brand prefix), extended to include
// one separator comma — the trailing comma if present, else the leading one —
// so removal leaves a valid array with no dangling comma.
function findBindingSpan(text, toComponent, fromIndex) {
  const re = new RegExp(
    `"service"\\s*:\\s*"(?:[a-z0-9-]+-)?${toComponent}-(?:stage|prod|dev)"`,
    "g",
  );
  re.lastIndex = fromIndex;
  const m = re.exec(text);
  if (!m) return null;

  // Service objects are flat ({ "binding": …, "service": … }) — no nested
  // braces — so the enclosing object is the nearest { before and } after.
  let open = text.lastIndexOf("{", m.index);
  let close = text.indexOf("}", m.index);
  if (open < 0 || close < 0) return null;
  let start = open;
  let end = close + 1;

  // Prefer a trailing comma; otherwise take a leading one.
  let after = end;
  while (after < text.length && /\s/.test(text[after])) after++;
  if (text[after] === ",") {
    end = after + 1;
  } else {
    let before = start - 1;
    while (before >= 0 && /\s/.test(text[before])) before--;
    if (text[before] === ",") start = before;
  }
  return { start, end };
}

function strip(all) {
  let total = 0;
  for (const { from, to } of all ? allEdges() : FEEDBACK_EDGES) {
    const file = wranglerPath(from);
    if (!fs.existsSync(file)) {
      console.warn(`cycle-break --strip: ${file} absent — skipping ${from} -> ${to}`);
      continue;
    }
    let text = fs.readFileSync(file, "utf8");
    let removed = 0;
    // Repeatedly remove each remaining (stage/prod/…) binding to `to`.
    for (;;) {
      const span = findBindingSpan(text, to, 0);
      if (!span) break;
      const slice = text.slice(span.start, span.end);
      const b64 = Buffer.from(slice, "utf8").toString("base64");
      // A marker is a LINE comment, so nothing may follow it on its line. When
      // the removed object's closing brace was directly followed by another
      // marker (an earlier strip in the same array took the leading comma),
      // the two would fuse into one comment and restore could not split them.
      // Break the line, and say so in the marker so restore takes the break
      // back out: `+nl` markers own the newline after them.
      const rest = text.slice(span.end);
      const nl = !/^[ \t]*(\r?\n|$)/.test(rest);
      const marker = `// ${MARKER}${nl ? "+nl" : ""}:${from}->${to}:${b64}${nl ? "\n" : ""}`;
      text = text.slice(0, span.start) + marker + rest;
      removed++;
    }
    if (removed > 0) {
      fs.writeFileSync(file, text);
      console.log(`cycle-break --strip: ${from} -> ${to}: removed ${removed} binding(s) in ${file}`);
      total += removed;
    } else if (!all) {
      // Under --all most pairs never had a binding; only the named feedback
      // edges are worth reporting as "already stripped".
      console.log(`cycle-break --strip: ${from} -> ${to}: already stripped (no live binding)`);
    }
  }
  console.log(
    total > 0
      ? `cycle-break --strip: done (${total} binding(s)). Commit + merge to deploy the DAG, then run --restore.`
      : "cycle-break --strip: nothing to do (already stripped).",
  );
}

function restore() {
  // `+nl` markers inserted the line break that follows them; take it back.
  const re = new RegExp(`// ${MARKER}(\\+nl)?:[a-z0-9-]+->[a-z0-9-]+:([A-Za-z0-9+/=]+)(\\n)?`, "g");
  let total = 0;
  for (const from of templatesToVisit()) {
    const file = wranglerPath(from);
    if (!fs.existsSync(file)) continue;
    let text = fs.readFileSync(file, "utf8");
    let count = 0;
    text = text.replace(re, (_m, plusNl, b64, lineBreak) => {
      count++;
      const original = Buffer.from(b64, "base64").toString("utf8");
      return plusNl || !lineBreak ? original : original + lineBreak;
    });
    if (count > 0) {
      fs.writeFileSync(file, text);
      console.log(`cycle-break --restore: restored ${count} binding(s) in ${file}`);
      total += count;
    }
  }
  console.log(
    total > 0
      ? `cycle-break --restore: done (${total} binding(s)). Commit + merge to redeploy with full bindings.`
      : "cycle-break --restore: nothing to restore.",
  );
}

function check() {
  const re = new RegExp(`// ${MARKER}(?:\\+nl)?:([a-z0-9-]+->[a-z0-9-]+):`, "g");
  let any = false;
  for (const from of templatesToVisit()) {
    const file = wranglerPath(from);
    if (!fs.existsSync(file)) continue;
    const text = fs.readFileSync(file, "utf8");
    for (const m of text.matchAll(re)) {
      console.log(`stripped: ${m[1]} (${file})`);
      any = true;
    }
  }
  if (!any) console.log("cycle-break --check: no edges stripped (full binding topology).");
}

const mode = process.argv[2];
const all = process.argv.slice(3).includes("--all");
if (mode === "--strip") strip(all);
else if (mode === "--restore") restore();
else if (mode === "--check") check();
else usage();
