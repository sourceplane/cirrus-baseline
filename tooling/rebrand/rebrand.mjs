#!/usr/bin/env node
// Fork/rebrand renamer for the Cirrus SaaS baseline (zero-dependency).
//
// Cirrus is a self-contained baseline: fork it, rebrand it, deploy it as a new
// product. This script rewrites every *instance identity* literal in the repo
// — repo slug, product domain, product/display name, SDK class name, CLI bin,
// Cloudflare worker resource names (so a fork is account-safe even when it
// shares an account with Cirrus), wire-visible user agents, workers.dev
// subdomain — to the values supplied in a values file, leaving *org-owned*
// identity untouched (GitHub org `sourceplane`, the orun state backend,
// `sourceplane.io` manifest apiVersion, S3 state buckets, company email
// addresses). The rename map is the codified inverse of Cirrus's own instance
// identity; FORKING.md is the playbook.
//
// Usage (from the repo root, on a clean tree):
//   node tooling/rebrand/rebrand.mjs --values my-brand.json [--dry-run]
//   node tooling/rebrand/rebrand.mjs --verify
//
// Values file (see tooling/rebrand/values.example.json):
//   {
//     "reponame":            "acme-cloud",          // required — repo slug
//     "productname":         "Acme Cloud",          // required — display name
//     "productdomain":       "acme.dev",            // required — product domain
//     "pascalName":          "AcmeCloud",           // default: productname, non-alnum stripped
//     "brandSlug":           "acme",                // default: reponame
//     "cliBin":              "acme",                // default: reponame
//     "apibaseurl":          "https://api.acme.dev",// default: https://api.<productdomain>
//     "subdomain": "my-subdomain",        // default: "your-workers-subdomain"
//     "salesEmail":          "sales@acme.dev"       // optional: keeps baseline mailbox if absent
//   }
//
// Modes:
//   (default)   apply the rename map in place, then run the leftover sweep
//   --dry-run   report per-pair match counts and files; change nothing
//   --verify    only run the leftover sweep (non-zero exit on residue)

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// ── Inputs ─────────────────────────────────────────────────────

function flag(name) {
  return process.argv.includes(`--${name}`);
}
function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const dryRun = flag("dry-run");
const verifyOnly = flag("verify");

let values = {};
// --verify takes --values too, optionally: without them it cannot tell the
// product's own identity from a leftover of the baseline's (below).
const valuesPath = arg("values");
if (!verifyOnly && !valuesPath) {
  console.error("usage: rebrand.mjs --values <file> [--dry-run] | --verify [--values <file>]");
  process.exit(2);
}
if (valuesPath) {
  values = JSON.parse(fs.readFileSync(valuesPath, "utf8"));
  for (const required of ["reponame", "productname", "productdomain"]) {
    if (typeof values[required] !== "string" || values[required].length === 0) {
      console.error(`rebrand: values file is missing required field "${required}"`);
      process.exit(2);
    }
  }
}

// ── THE BASELINE'S OWN IDENTITY — the FROM side, declared ──────
//
// Every rule below renames the BASELINE's identity to the product's. The
// baseline's half of each pair used to be a hardcoded literal — `cirrus`,
// `Cirrus`, `CIRRUS_`, `cirrus.app`, `cirrus-web-console`, `cirrus.next`,
// thirty-six of them — which meant only a repository literally named `cirrus`
// could serve as a baseline. Promoting a proven instantiation to be the next
// baseline (which is how a baseline line is meant to advance) required editing
// all thirty-six by hand and re-proving the rebrand, and getting one wrong is
// silent: the stray literal simply never renames, and the product ships with
// the baseline's name inside it.
//
// So the FROM side is declared in `.baseline/identity.json`, and the defaults
// below are Cirrus's — a tree that does not carry the file behaves exactly as
// it did before this change.
//
//   slug        the lowercase brand word: repo slug, CLI bin, worker prefix,
//               storage prefix, check-run name, config dir, secret project
//   pascal      the code-identifier form: the SDK client class, the UA prefix
//   productName the display name as it appears in PRODUCT_NAME
//   domain      the product domain; the API host is derived as `api.<domain>`
//   subdomain   the baseline's own workers.dev subdomain
//
// A baseline that declares this file is self-describing: `identity.slug` is
// the one place that says what this tree is called, and the rules below read
// it. Nothing here is derived from the git remote or the directory name, both
// of which lie after a fork.
// RESOLVED AGAINST THIS SCRIPT, NOT THE WORKING DIRECTORY. The rebrand runs
// with its cwd set to the PRODUCT being branded, while the identity it renames
// FROM belongs to the BASELINE — and a product does not carry `.baseline/`,
// because no module places it. Read from the cwd, the file was simply absent
// during every real placement and the tool fell back to the defaults, i.e. to
// cirrus's identity. The product then came out with
// `api.acme-cloud-baseline.dev`: `cirrus` had been renamed inside
// `cirrus-baseline.dev` and the `-baseline` suffix left behind. The phase
// hooks invoke this as `node {{ .baseline.dir }}/tooling/rebrand/rebrand.mjs`,
// so the script's own path is the one thing that always points at the baseline.
// `--baseline-identity <file>` overrides it.
const BASELINE_IDENTITY_FILE =
  arg("baseline-identity") ??
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", ".baseline", "identity.json");
const BASELINE_DEFAULTS = {
  slug: "cirrus",
  pascal: "Cirrus",
  productName: "Cirrus",
  domain: "cirrus.app",
  subdomain: "rahulvarghesepullely",
};
const baseline = (() => {
  let declared = {};
  try {
    declared = JSON.parse(fs.readFileSync(BASELINE_IDENTITY_FILE, "utf8"));
  } catch {
    declared = {}; // absent is fine: the defaults ARE Cirrus's identity
  }
  const id = { ...BASELINE_DEFAULTS, ...declared };
  for (const [k, v] of Object.entries(id)) {
    if (typeof v !== "string" || v.length === 0) {
      console.error(`rebrand: ${BASELINE_IDENTITY_FILE} field "${k}" must be a non-empty string`);
      process.exit(2);
    }
  }
  if (/[^a-z0-9-]/.test(id.slug)) {
    console.error(`rebrand: ${BASELINE_IDENTITY_FILE} "slug" must be a lowercase slug ([a-z0-9-])`);
    process.exit(2);
  }
  return {
    ...id,
    envPrefix: id.slug.toUpperCase().replace(/-/g, "_"),
    camel: id.pascal.charAt(0).toLowerCase() + id.pascal.slice(1),
    apiHost: `api.${id.domain}`,
  };
})();
// Regex-escape, for the rules that build a pattern out of the identity.
const rx = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// Segment-wise PascalCase. This used to be `productname` with non-alphanumerics
// STRIPPED, which is PascalCase only when the operator already capitalised the
// display name: "Acme Cloud" -> "AcmeCloud", but the slug-shaped name a
// bootstrap actually passes, "cirrus-baseline", became "cirrusbaseline" — and
// that is a TypeScript class name. The live cirrus-baseline product shipped
// `export class cirrusbaseline`. Capitalise each segment instead.
function toPascal(s) {
  return String(s)
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join("");
}

// All fields are unused under --verify; the fallbacks keep derivation total.
const reponame = values.reponame ?? "";
const productname = values.productname ?? "";
const productdomain = values.productdomain ?? "";
const pascalName = values.pascalName ?? toPascal(productname);
const brandSlug = values.brandSlug ?? reponame;
const cliBin = values.cliBin ?? reponame;
const apibaseurl = values.apibaseurl ?? `https://api.${productdomain}`;
const subdomain = values.subdomain ?? "your-workers-subdomain";
const salesEmail = values.salesEmail; // optional
// A `secret://<workspace>/<project>/<env>/<KEY>` ref names the WORKSPACE
// first and the project (repo) second. In the baseline the two happen to be
// the same word, so a naive repo-slug rename rewrites BOTH — and the fork's
// refs then point at a workspace that does not exist, failing every resolve
// with "Validation failed". The workspace segment is renamed separately:
// orunWorkspaceSlug when the caller supplied one, else orunWorkspace itself.
//
// A ws_… id IS a valid workspace segment. The resolve verifies the segment
// against membership and accepts a slug, a public id or a ws_ ref
// (orun-cloud state-worker secrets-resolve.ts, verifySegments). This used to
// skip a ws_… id on the belief that only a slug matched, and fell back to the
// REPO name. The blueprint's `orunWorkspace` input IS a ws_… id and nothing
// supplies a slug, so every product's refs named a workspace that does not
// exist (`secret://altocumulus/altocumulus/…` for workspace cirrus-test):
//
//   Ref workspace "altocumulus" does not name this run's workspace
//
// The repo name remains the last resort only when no workspace was given.
const orunWorkspaceSlug = (() => {
  const explicit = (values.orunWorkspaceSlug ?? "").trim();
  if (explicit) return explicit;
  const ws = (values.orunWorkspace ?? "").trim();
  if (ws) return ws;
  return reponame;
})();
// Derived code-shaped forms.
const camelName = pascalName.charAt(0).toLowerCase() + pascalName.slice(1);
const envPrefix = cliBin.toUpperCase().replace(/-/g, "_");

if (!verifyOnly && /[^a-z0-9-]/.test(`${reponame}${brandSlug}${cliBin}`)) {
  console.error("rebrand: reponame/brandSlug/cliBin must be lowercase slugs ([a-z0-9-])");
  process.exit(2);
}

// In-place rewrite of the whole tree: insist on a clean checkout so the
// result is reviewable as one diff (and trivially revertible).
if (!verifyOnly && !dryRun && !flag("allow-dirty")) {
  const status = execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" });
  if (status.trim().length > 0) {
    console.error("rebrand: working tree is not clean — commit/stash first (or pass --allow-dirty)");
    process.exit(2);
  }
}

// ── File set ───────────────────────────────────────────────────

// Tracked text files only. Exclusions are either generated/locked artifacts,
// this tool itself, or files that intentionally keep baseline-provenance
// literals.
const EXCLUDE_RE = new RegExp(
  [
    "^tooling/rebrand/",
    "^\\.rebrand/",
    // The baseline's declared identity. Renaming its contents would make the
    // product claim to be a baseline called by the product's own name.
    "^\\.baseline/",
    // The prebuilt-console pin (saas-console-artifact CA4) names the BASELINE's
    // release URL, which is provenance: renaming it would point the product at
    // a release that does not exist.
    "^apps/web-console-next/console-artifact\\.pin\\.json$",
    "^FORKING\\.md$",
    "^ai/context/fork-from-baseline\\.md$",
    "^pnpm-lock\\.yaml$",
    "^kiox\\.lock$",
    "\\.(png|jpg|jpeg|ico|gif|woff2?|ttf|eot)$",
  ].join("|"),
);

function trackedFiles() {
  return execFileSync("git", ["ls-files"], { encoding: "utf8" })
    .split("\n")
    .filter((f) => f.length > 0 && !EXCLUDE_RE.test(f))
    .filter((f) => {
      // `git ls-files` also lists gitlinks (nested repos — a grounded sandbox
      // checkout carries `baseline/` as one) and paths deleted from disk.
      // Only regular files are sweepable; a gitlink crashed the sweep with
      // readFileSync-on-directory mid-bootstrap (observed live).
      try {
        return fs.statSync(f).isFile();
      } catch {
        return false;
      }
    });
}

// ── Protected literals (org-owned identity, never rewritten) ───
//
// Masked before the pair sweep and restored after, so no rename can touch the
// org's shared infrastructure identity, even where it shares the `sourceplane`
// token with a company mailbox.

const PROTECTED = [
  /https:\/\/orun-api\.sourceplane\.ai/g, // orun state backend (intent.yaml)
  /sourceplane\.io/g, // manifest apiVersion, owned by the orun tooling
  /[A-Za-z0-9._%+-]+@sourceplane\.ai/g, // company mailboxes
];

const MASK = (i, j) => `\u0000REBRAND_PROTECTED_${i}_${j}\u0000`;

// ── Substituted values are opaque ──────────────────────────────
//
// The rules run in sequence over one buffer, and each used to write its VALUE
// into it — where every later rule could match again. A value that contains a
// baseline word was rewritten a second time:
//
//   secret://lumen/cirrus/…  →  secret://cirrus-test/altocumulus/…   (secret ref)
//                            →  secret://altocumulus-test/altocumulus/…  (repo slug)
//   Cirrus-Webhooks  →  CirrusNext-Webhooks  →  CirrusNextNext-Webhooks
//   cirrus.app       →  cirrus-weather.dev   →  acme-weather.dev
//
// So a rule writes a TOKEN standing for its value, and every token is expanded
// once, after the last rule. A token is NUL, `H<n>`, NUL — NUL cannot occur in a
// file this touches (binary files are skipped; the protected-literal mask above
// relies on the same fact), and nothing between the NULs is anything a rule
// matches. Its outer characters take the word/non-word class of the value's own
// first and last characters, so a `\b` in a later rule sees the same boundary
// beside the token that it would have seen beside the value.
const heldValues = [];
const heldIndex = new Map();
function hold(value) {
  if (value === "") return "";
  let i = heldIndex.get(value);
  if (i === undefined) {
    i = heldValues.push(value) - 1;
    heldIndex.set(value, i);
  }
  const edge = (c) => (/\w/.test(c) ? "0" : "\u0001");
  return `${edge(value[0])}\u0000H${i}\u0000${edge(value[value.length - 1])}`;
}
const HELD_RE = /[0\u0001]\u0000H(\d+)\u0000[0\u0001]/g;
function release(text) {
  return text.replace(HELD_RE, (_, i) => heldValues[Number(i)]);
}

// ── Worker resource names ──────────────────────────────────────
//
// Every Cloudflare worker ships brand-prefixed as `cirrus-<base>` (top-level
// wrangler "name", `<worker>-<env>` service bindings, smoke health-checks,
// binding tests, user agents). The base of each worker is its `apps/<base>/`
// directory. Re-prefix `cirrus-<base>` → `<brandSlug>-<base>` so a fork's
// workers never collide with Cirrus's, even in a shared Cloudflare account.
// `web-console-next` is handled by an explicit literal pair below because its
// deployed names include the `-next`-less legacy `cirrus-web-console` form.
function workerBases(files) {
  const bases = new Set();
  for (const file of files) {
    const m = /^apps\/([^/]+)\//.exec(file);
    if (m && m[1] !== "web-console-next") bases.add(m[1]);
  }
  return [...bases];
}

// ── Rename map (ordered, most specific first) ──────────────────

function pairs() {
  const list = [];
  // Optional mailbox retarget runs before emails are masked.
  if (salesEmail) {
    list.push(["sales@sourceplane.ai", salesEmail, "sales mailbox (console seam)"]);
  }
  list.push(
    // Console worker/Pages prefix (covers the -next variant and the legacy
    // pages.dev fixtures in the CORS tests).
    [`${baseline.slug}-web-console`, `${brandSlug}-web-console`, "console worker prefix"],
    // Wire-visible webhooks user agent (test assertions update in lockstep).
    [`${baseline.pascal}-Webhooks`, `${pascalName}-Webhooks`, "webhooks UA"],
    // CLI default API base (brand seam). Most specific first so the bare-host
    // and product-domain forms below do not consume it.
    [`https://${baseline.apiHost}`, apibaseurl, "CLI default API base"],
    [baseline.apiHost, apibaseurl.replace(/^https?:\/\//, ""), "CLI API host (bare)"],
    // Product domain wherever it is the *product* (BASE_DOMAIN, console custom
    // domains, Polar success URLs, OAuth origins, CORS tests, docs). The orun
    // backend URL and company mailboxes are masked above.
    [baseline.domain, productdomain, "product domain"],
    // Display-name seams keep the human-readable name even in .ts files.
    [`PRODUCT_NAME = "${baseline.productName}"`, `PRODUCT_NAME = "${productname}"`, "product-name seams"],
    // Console localStorage namespace (console app-config seam).
    [`STORAGE_PREFIX = "${baseline.slug}.next"`, `STORAGE_PREFIX = "${brandSlug}.next"`, "storage prefix"],
    // Workers.dev subdomain (app-config seams, console component, identity template).
    [baseline.subdomain, subdomain, "workers.dev subdomain"],
    // SDK usage examples (integrations README): the client variable and the
    // product-namespaced check-run name.
    [`const ${baseline.camel} = new`, `const ${camelName} = new`, "SDK example variable (decl)"],
    [`await ${baseline.camel}.integrations`, `await ${camelName}.integrations`, "SDK example variable (use)"],
    [`"${baseline.slug}/verify"`, `"${brandSlug}/verify"`, "check-run name example"],
    // CLI config-dir references in docs.
    [`.config/${baseline.slug}/`, `.config/${cliBin}/`, "CLI config dir (docs)"],
    // CLI command examples in docs: `cirrus ...` / `cirrus`.
    [`\`${baseline.slug} `, `\`${cliBin} `, "CLI bin (doc examples, open)"],
    [`\`${baseline.slug}\``, `\`${cliBin}\``, "CLI bin (doc examples, closed)"],
  );
  return list;
}

// ── `Cirrus` (display name vs. code identifier) ────────────────
//
// The `@saas/sdk` client class (`Cirrus`, `CirrusError`, `CirrusEventEnvelope`, …)
// is a code identifier; prose references are the display name:
//   - code files (.ts/.js/...)            → pascalName
//   - markdown code fences + inline code  → pascalName
//   - everything else (prose, yaml, json) → productname

function replaceBrandWord(file, text, count) {
  const BRAND_WORD = new RegExp(rx(baseline.pascal), "g");
  const sub = (chunk, to) =>
    chunk.replace(BRAND_WORD, () => {
      count();
      return hold(to);
    });

  if (/\.(ts|tsx|mts|cts|js|mjs|cjs)$/.test(file)) return sub(text, pascalName);
  if (!/\.(md|markdown)$/.test(file)) return sub(text, productname);

  // Markdown: fenced blocks keep the identifier form …
  return text
    .split(/(```[\s\S]*?(?:```|$))/)
    .map((part) => {
      if (part.startsWith("```")) return sub(part, pascalName);
      // … as do inline code spans; bare prose gets the display name.
      return part
        .split(/(`[^`\n]+`)/)
        .map((span) =>
          span.startsWith("`") && span.endsWith("`")
            ? sub(span, pascalName)
            : sub(span, productname),
        )
        .join("");
    })
    .join("");
}

// Scoped, regex-based pairs applied after the literal map.
function scopedPairs() {
  const list = [
    // Secret refs: `secret://<workspace>/<project>/…`. MUST precede the
    // repo-slug pass below, which would otherwise rewrite the workspace
    // segment to the repo name (see orunWorkspaceSlug above).
    {
      re: new RegExp(`\\bsecret://[a-z0-9-]+/${rx(baseline.slug)}/`, "g"),
      replacement: () => `secret://${orunWorkspaceSlug}/${reponame}/`,
      label: "secret ref workspace/project",
    },
    // Branded env-var names: the real CONFIG_DIR override (brand.ts derives it
    // from CLI_BIN, so tests/docs must rename in lockstep) plus doc
    // placeholders like CIRRUS_TOKEN / CIRRUS_API_KEY / CIRRUS_WEBHOOK_SECRET.
    {
      re: new RegExp(`${rx(baseline.envPrefix)}_(?=[A-Z])`, "g"),
      replacement: () => `${envPrefix}_`,
      label: "branded env-var prefix",
    },
    // CLI bin: usage strings, keychain/config-dir derivations, package bin.
    // Inside packages/cli the org token never appears bare (the masked
    // sourceplane.io/backend forms aside), so a word-boundary replace is safe.
    {
      re: new RegExp(`\\b${rx(baseline.slug)}\\b`, "g"),
      replacement: () => cliBin,
      label: "CLI bin (packages/cli)",
      fileFilter: (file) => file.startsWith("packages/cli/"),
    },
  ];

  // Re-prefix every Cloudflare worker resource name (`cirrus-<base>`) so a fork
  // is safe to deploy even into an account it shares with Cirrus. The alternation
  // is the explicit set of worker bases, so `cirrus-stage` / `cirrus-prod`
  // (the D1 database names, which are repo-slug-derived) are never matched
  // here — they fall to the repo-slug pass below.
  const bases = workerBases(files);
  if (bases.length > 0) {
    // Longest-first so an alternation never matches a shorter prefix of a base.
    const wb = bases.slice().sort((a, b) => b.length - a.length).join("|");
    list.push({
      re: new RegExp(`\\b${rx(baseline.slug)}-(${wb})\\b`, "g"),
      replacement: (_file, _m, base) => `${brandSlug}-${base}`,
      label: "worker CF name",
    });
  }

  // Repo slug: intent metadata.name + per-env repo: params, component.yaml
  // repo: fields, Terraform repo defaults, Secrets Manager paths, OIDC role
  // names, D1 database names (`cirrus-stage` → `<repo>-stage`), root package
  // name, docs. Runs AFTER the worker pass so `cirrus-<worker>` has already
  // been consumed. packages/cli owns the CLI-bin meaning of `cirrus` (handled
  // above), so it is excluded here.
  list.push({
    re: new RegExp(`\\b${rx(baseline.slug)}\\b`, "g"),
    replacement: () => reponame,
    label: "repo slug",
    fileFilter: (file) => !file.startsWith("packages/cli/"),
  });

  return list;
}

// ── Leftover sweep ─────────────────────────────────────────────
//
// After a rebrand (or under --verify) every remaining Cirrus-identity literal is
// residue: either org-owned (allowed, enumerated below) or a missed rename
// (reported, non-zero exit).

// The baseline's workers.dev subdomain is residue ONLY when the fork changed
// it: a fork deploying into the same Cloudflare account legitimately keeps the
// subdomain (worker names are already brand-prefixed, so there is no
// collision), and flagging it made the rebrand exit 1 mid-bootstrap — which
// silently skipped every later hook. Under --verify (no values file) the
// subdomain check is skipped for the same reason: --verify runs on forks, and
// a kept subdomain is not a missed rename.
const BASELINE_SUBDOMAIN = baseline.subdomain;
const subdomainChanged =
  !verifyOnly && subdomain !== BASELINE_SUBDOMAIN;
const RESIDUE_RE = new RegExp(
  (subdomainChanged ? `${rx(BASELINE_SUBDOMAIN)}|` : "") +
    [
      `\\b${rx(baseline.slug)}\\b`,
      `${rx(baseline.slug)}-`,
      rx(baseline.pascal),
      `${rx(baseline.envPrefix)}_`,
    ].join("|"),
  "g",
);

const ALLOWED_RESIDUE = [
  /https:\/\/orun-api\.sourceplane\.ai/, // orun state backend
  /[A-Za-z0-9._%+-]+@sourceplane\.ai/, // company mailboxes
];

function sweep(files, allowedLiterals = []) {
  const residue = [];
  for (const file of files) {
    let text;
    try {
      text = fs.readFileSync(file, "utf8");
    } catch {
      continue; // unreadable/deleted/non-file — nothing to sweep
    }
    for (const line of text.split("\n")) {
      // Strip allowed (org-owned) forms first; whatever still matches is residue.
      let cleaned = ALLOWED_RESIDUE.reduce(
        (l, re) => l.replace(new RegExp(re.source, "g"), ""),
        line,
      );
      // Then the rename's own TARGET values: a fork legitimately named with
      // the brand token inside it (repo "cirrus-e2e") is not residue — without
      // this, its every occurrence failed the post-rename sweep.
      for (const lit of allowedLiterals) {
        if (lit) cleaned = cleaned.split(lit).join("");
      }
      if (new RegExp(RESIDUE_RE.source).test(cleaned)) {
        residue.push(`${file}: ${line.trim().slice(0, 120)}`);
      }
    }
  }
  return residue;
}

// ── Main ───────────────────────────────────────────────────────

const files = trackedFiles();

const literalPairs = pairs();
const regexPairs = scopedPairs();
const counts = new Map();
const touched = new Set();

// Every value a rule can write. A value that some rule would match again is
// HELD wherever it already stands in a file: every phase of a bootstrap re-runs
// this over the whole tree, so the product a previous run branded is the input
// to the next one, and `secret://cirrus-test/altocumulus/` written by phase 01
// must not become `…/altocumulus-test/…` in phase 02. (This generalises the
// guard the literal pairs had for their own target alone — "cirrus" ->
// "cirrus-e2e" -> "cirrus-e2e-e2e" under a retry, observed live.)
const produced = [
  ...literalPairs.map(([, to]) => to),
  pascalName,
  productname,
  `secret://${orunWorkspaceSlug}/${reponame}/`,
  `${envPrefix}_`,
  cliBin,
  reponame,
  ...workerBases(files).map((base) => `${brandSlug}-${base}`),
].filter((v, i, all) => v && all.indexOf(v) === i);
const rematchable = (v) =>
  literalPairs.some(([from]) => v.includes(from)) ||
  new RegExp(rx(baseline.pascal)).test(v) ||
  regexPairs.some(({ re }) => new RegExp(re.source).test(v));
// Longest first, so a held value is never split by a shorter one inside it.
const guarded = produced.filter(rematchable).sort((a, b) => b.length - a.length);

if (verifyOnly) {
  // A product whose own name, domain or workspace slug contains a baseline
  // word (`cirrus-test`, `cirrus-e2e`) carries that word legitimately, and
  // without its values --verify cannot know that: every phase of such a
  // bootstrap failed its rebrand-verify on the product's own identity. Given
  // --values, what this rebrand would write is allowed exactly as the
  // post-rename sweep allows it.
  const residue = sweep(
    files,
    valuesPath ? produced.filter((to) => new RegExp(RESIDUE_RE.source).test(to)) : [],
  );
  if (residue.length > 0) {
    console.error(`rebrand --verify: ${residue.length} baseline-identity leftover(s):`);
    for (const r of residue) console.error(`  ${r}`);
    process.exit(1);
  }
  console.log("rebrand --verify: no baseline-identity leftovers.");
  process.exit(0);
}


for (const file of files) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    continue; // unreadable/deleted — not our concern
  }
  if (text.includes("\0")) continue; // binary safety net
  const original = text;

  // Mask org-owned literals.
  const masks = [];
  PROTECTED.forEach((re, i) => {
    text = text.replace(re, (m) => {
      const token = MASK(i, masks.length);
      masks.push([token, m]);
      return token;
    });
  });

  // What a previous run already wrote stays as written.
  for (const value of guarded) text = text.split(value).join(hold(value));

  for (const [from, to, label] of literalPairs) {
    const n = text.split(from).length - 1;
    if (n === 0) continue;
    text = text.split(from).join(hold(to));
    counts.set(label, (counts.get(label) ?? 0) + n);
  }
  const brandLabel = "Cirrus (class name in code, display name in prose)";
  text = replaceBrandWord(file, text, () =>
    counts.set(brandLabel, (counts.get(brandLabel) ?? 0) + 1),
  );

  for (const { re, replacement, label, fileFilter } of regexPairs) {
    if (fileFilter && !fileFilter(file)) continue;
    text = text.replace(re, (...m) => {
      counts.set(label, (counts.get(label) ?? 0) + 1);
      return hold(replacement(file, ...m));
    });
  }

  // Every rule has run; only now do the values it wrote appear.
  text = release(text);

  // Restore org-owned literals.
  for (const [token, value] of masks) text = text.split(token).join(value);

  if (text !== original) {
    touched.add(file);
    if (!dryRun) fs.writeFileSync(file, text);
  }
}

console.log(`rebrand${dryRun ? " (dry-run)" : ""}: ${touched.size} file(s) affected`);
for (const [label, n] of counts) console.log(`  ${String(n).padStart(5)}  ${label}`);

if (dryRun) {
  process.exit(0);
}

// Provenance stub for the fork, recording its instantiation from Cirrus.

const residue = sweep(
  trackedFiles(),
  produced.filter((to) => new RegExp(RESIDUE_RE.source).test(to)),
);
if (residue.length > 0) {
  console.error(`rebrand: ${residue.length} baseline-identity leftover(s) after rename:`);
  for (const r of residue) console.error(`  ${r}`);
  process.exit(1);
}
console.log("rebrand: leftover sweep clean.");
