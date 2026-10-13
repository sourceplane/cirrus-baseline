#!/usr/bin/env node
// Generates each component's catalog docs (overview / architecture / runbook)
// from its component.yaml and the dependency graph those files already form.
//
// Why generated: the workspace Docs library renders a `docs/` folder next to
// every component.yaml, and there are ~40 of them. Hand-written, they drift the
// first time a dependency or a wiring secret changes — and a docs page that
// lies about which secret a Worker needs is worse than no page. Everything here
// is derived from declarations that CI already validates, so the docs cannot
// disagree with the components.
//
//   node tooling/catalog/gen-component-docs.mjs           # write
//   node tooling/catalog/gen-component-docs.mjs --check    # fail on drift (CI)
//
// Prose that is genuinely per-component (why a boundary exists, what a
// specific failure means) belongs in specs/, not here: this file states what
// is true of every component of a given type.

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const ROOTS = ["apps", "packages", "infra", "tests"];
const checkOnly = process.argv.includes("--check");

// ── A deliberately small YAML reader ────────────────────────────
// component.yaml is a flat, machine-written shape: scalars, one level of
// nesting, and `- name:` lists. Reading the handful of fields the docs need
// beats adding a YAML dependency to a zero-dependency tooling directory.

function readComponent(file) {
  const text = fs.readFileSync(file, "utf8");
  const get = (key, within) => {
    const scope = within ? text.slice(text.indexOf(within)) : text;
    const m = new RegExp(`^\\s*${key}:\\s*(.+)$`, "m").exec(scope);
    if (!m) return null;
    return m[1].trim().replace(/^["']|["']$/g, "").replace(/\s+#.*$/, "");
  };
  const dependsOn = [
    ...text.matchAll(/^\s*-\s*component:\s*(\S+)\s*$/gm),
  ].map((m) => m[1]);
  const secretEnvKeys = (() => {
    const start = text.indexOf("\n  secretEnv:");
    if (start < 0) return [];
    const rest = text.slice(start + 1).split("\n").slice(1);
    const keys = [];
    for (const line of rest) {
      if (/^\s*#/.test(line) || line.trim() === "") continue;
      const m = /^\s{4}([A-Z0-9_]+):/.exec(line);
      if (!m) break;
      keys.push(m[1]);
    }
    return keys;
  })();
  const services = [
    ...text.matchAll(/^\s*-\s*component:\s*(\S+-worker)\s*$/gm),
  ].map((m) => m[1]);

  return {
    file,
    dir: path.dirname(file),
    name: get("name"),
    description: get("description") ?? "",
    type: get("type"),
    path: get("path") ?? path.relative(ROOT, path.dirname(file)),
    dependsOn,
    secretEnvKeys,
    services,
  };
}

function discover() {
  const out = [];
  for (const root of ROOTS) {
    const base = path.join(ROOT, root);
    if (!fs.existsSync(base)) continue;
    const walk = (dir, depth) => {
      if (depth > 3) return;
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          // `infra/terraform` is a container of components, not a component
          // root — only a directory holding .tf files is a dead end.
          if (["node_modules", "dist", ".turbo", "docs", "src", ".next", ".wrangler"].includes(entry.name)) continue;
          if (fs.existsSync(path.join(full, "main.tf"))) continue;
          walk(full, depth + 1);
        } else if (entry.name === "component.yaml") {
          out.push(readComponent(full));
        }
      }
    };
    walk(base, 0);
  }
  return out.filter((c) => c.name && c.type).sort((a, b) => a.name.localeCompare(b.name));
}

// ── Page bodies ─────────────────────────────────────────────────

const PRODUCT = "cirrus";

function overview(component, byName, dependents) {
  const kind = {
    "cloudflare-worker-turbo": `Part of the ${PRODUCT} runtime: a Cloudflare Worker deployed per environment (\`stage\`, \`prod\`; \`dev\` is verify-only). Not publicly routable — reached only through \`api-edge\` service bindings.`,
    "cloudflare-workers-assets-turbo": `Part of the ${PRODUCT} runtime: a Cloudflare Worker serving static assets plus server rendering, deployed per environment (\`stage\`, \`prod\`; \`dev\` is verify-only).`,
    terraform: `Terraform-managed infrastructure for ${PRODUCT}, per environment (\`stage\`, \`prod\`; \`dev\` is verify-only and provisions nothing).`,
    "db-migrate": `Applies this repo's ordered migrations to the environment's Cloudflare D1 database: plan on pull requests, apply on merge to \`main\`.`,
    "turbo-package": `A workspace package built by the turbo pipeline. It deploys nothing on its own — its lane type-checks, lints, tests, and builds it for the components that depend on it.`,
  }[component.type] ?? `A \`${component.type}\` component of ${PRODUCT}.`;

  const list = (names) =>
    names.length === 0
      ? "- (none)"
      : names
          .map((n) => {
            const dep = byName.get(n);
            return dep ? `- **${n}** — ${dep.description}` : `- **${n}**`;
          })
          .join("\n");

  return [
    `# ${component.name}`,
    "",
    component.description,
    "",
    kind,
    "",
    "## Depends on",
    "",
    list(component.dependsOn),
    "",
    "## Depended on by",
    "",
    list(dependents),
    "",
  ].join("\n");
}

function architecture(component) {
  const head = `# ${component.name} — architecture`;

  if (component.type === "terraform") {
    const published = component.name === "cloudflare-d1"
      ? "`WIRING_CLOUDFLARE_D1` (database id/name for deploy-time binding)"
      : component.name === "cloudflare-kv"
        ? "`WIRING_CLOUDFLARE_KV` (namespace id/title for deploy-time binding)"
        : "its wiring document";
    return [
      head,
      "",
      `A \`terraform\` component rooted at \`${component.path}/terraform\`.`,
      "",
      "- **State** lives in the platform's HTTP state backend (run-token auth) —",
      "  no local state, no cloud-vendor state buckets.",
      "- **Credentials are brokered per run** from the workspace's Cloudflare",
      "  connection; no long-lived provider secrets exist anywhere in CI.",
      "- **Outputs are published as job-output secrets** on the environment",
      `  rungs: ${published}. Downstream deploy lanes resolve them by name.`,
      "- **Self-healing adoption** (`adopt.tf`): when the platform state is",
      "  empty but the resource already exists at the provider, plan-time import",
      "  adopts it instead of failing with \"already exists\" — safe re-bootstrap",
      "  over half-torn-down attempts.",
      "",
    ].join("\n");
  }

  if (component.type === "db-migrate") {
    return [
      head,
      "",
      "Applies `packages/db/src/migrations` to the environment's D1 database over",
      "Cloudflare's REST API (`POST /accounts/{account}/d1/database/{db}/query`).",
      "",
      "- **The applied ledger is in the database**: `_migrations_applied` records",
      "  id, context, and checksum. A migration whose file no longer matches its",
      "  recorded checksum stops the run — that guard is the whole point.",
      "- **Statements are sent one at a time**, so a failure names the exact",
      "  statement instead of the whole file.",
      "- **No transaction**: D1 exposes none over REST. Migrations are written",
      "  idempotently (`IF NOT EXISTS`) and the ledger row is written last, so a",
      "  failed migration is simply re-attempted in full on the next run.",
      "- **The lock is a row** (`_migrations_lock`), reclaimed when stale —",
      "  SQLite has no advisory locks.",
      "",
    ].join("\n");
  }

  const lines = [
    head,
    "",
    `A \`${component.type}\` component: TypeScript built by the turbo pipeline`,
    `from \`${component.path}\`${component.type === "turbo-package" ? "." : ", deployed per environment by its CI lane."}`,
    "",
  ];

  if (component.type.startsWith("cloudflare-")) {
    lines.push("## Bindings and wiring", "");
    if (component.services.length > 0) {
      lines.push(
        `- **Service bindings** → ${component.services.map((s) => `\`${s}\``).join(", ")} —`,
        "  in-process RPC to sibling Workers; no public hops between contexts.",
      );
    }
    const wiring = component.secretEnvKeys.filter((k) => k.startsWith("WIRING_"));
    if (wiring.length > 0) {
      lines.push(
        "- **Wired configuration** (resolved at deploy time from job-output",
        "  secrets published by the infrastructure terraform; names only):",
        `  ${wiring.map((k) => `\`${k}\``).join(", ")}.`,
      );
    }
    if (component.dependsOn.includes("cloudflare-d1")) {
      lines.push(
        "- **`PLATFORM_DB`** is a D1 binding. SQLite types apply: timestamps are",
        "  ISO-8601 text, JSON is text, booleans are 0/1, and there is no",
        "  interactive transaction (see `packages/db/src/d1`).",
      );
    }
    lines.push(
      "",
      "## Boundaries",
      "",
      "This Worker owns its bounded context: its data, its invariants, its",
      "API surface (exposed to the fleet through the edge). Cross-context calls",
      "go over service bindings; nothing else may reach into its storage.",
      "",
    );
  } else {
    lines.push(
      "## Boundaries",
      "",
      "A library, not a runtime: it holds no credentials, opens no connections,",
      "and is consumed at build time by the components that depend on it.",
      "",
    );
  }
  return lines.join("\n");
}

function runbook(component) {
  const common = [
    `# ${component.name} — runbook`,
    "",
    "## How it deploys",
    "",
    "Merges to `main` converge automatically: CI plans changed components",
    "(`orun plan --changed`) and runs this component's lane via",
    "`orun run --remote-state` with credential-free OIDC auth. The convergence",
    "run is the deployment; the DAG orders this component after everything it",
    "depends on. Failed lanes resume with `gh run rerun --failed`.",
    "",
    "## Rollback",
    "",
    "Revert the offending commit on `main`; the next convergence applies the",
    "previous desired state. There is no out-of-band mutation to undo — the",
    "repo is the source of truth.",
    "",
    "## Verify",
    "",
  ];

  if (component.type === "terraform") {
    return [
      ...common,
      "```bash",
      "# published outputs (names only, per environment)",
      "orun secrets list --org <ws> --env stage",
      "orun secrets list --org <ws> --env prod",
      "```",
      "",
      "## Common failures",
      "",
      "- **\"Resource already exists\" with empty platform state**: adoption",
      "  (`adopt.tf`) imports at plan time; if a root lacks adoption the",
      "  resource must be state-migrated or deleted.",
      "- **Provider auth failure**: the workspace's Cloudflare connection is",
      "  missing or revoked — reconnect it in the console; secrets are brokered",
      "  from it per run.",
      "- **`Authentication error (10000)` on a D1 resource**: the lane resolved",
      "  the `workers-deploy` token, which deliberately cannot touch D1 — bind",
      "  `CLOUDFLARE_D1_TOKEN` (the `d1-edit` template) instead.",
      "",
    ].join("\n");
  }

  if (component.type === "db-migrate") {
    return [
      ...common,
      "```bash",
      "# what the runner would apply, without touching the database",
      "pnpm --filter @saas/db migrate:plan -- --env stage",
      "```",
      "",
      "## Common failures",
      "",
      "- **Checksum mismatch for an already-applied migration**: someone edited",
      "  a migration that has already run. Do NOT rechecksum it — write a new",
      "  forward migration.",
      "- **`no such table: _migrations_applied`**: the run reached a different",
      "  database than the one it migrated before — check `WIRING_CLOUDFLARE_D1`",
      "  for that environment.",
      "- **A statement fails partway**: nothing rolls back (D1 has no REST",
      "  transaction), but every migration is idempotent, so fix the file and",
      "  re-run.",
      "",
    ].join("\n");
  }

  if (component.type === "turbo-package") {
    return [
      ...common,
      "The lane itself is the gate: typecheck, lint, test, build. This package",
      "has no deployed surface.",
      "",
      "## Common failures",
      "",
      "- **A dependent's lane fails to build after a change here**: the change",
      "  was source-compatible but not type-compatible — run",
      "  `pnpm typecheck` across the workspace before landing.",
      "",
    ].join("\n");
  }

  return [
    ...common,
    "The deploy lane's own verify/smoke is the gate. End-to-end behavior is",
    "exercised through `api-edge` (this Worker has no public URL).",
    "",
    "## Common failures",
    "",
    "- **Missing `WIRING_*` secret at deploy**: the infrastructure terraform",
    "  upstream has not applied — check that lane first; within one",
    "  convergence run the DAG guarantees order.",
    "- **Service-binding target missing (Cloudflare 10143)**: the target",
    "  Worker does not exist yet on this account — converge the fleet before",
    "  this lane (the bootstrap's two-pass landing handles first boot).",
    "- **Smoke fails right after a first deploy**: a brand-new workers.dev",
    "  route can 4xx for a few seconds; the lane already retries — persistent",
    "  failure means a real regression.",
    "",
  ].join("\n");
}

// ── Main ────────────────────────────────────────────────────────

const components = discover();
const byName = new Map(components.map((c) => [c.name, c]));
const dependents = new Map(components.map((c) => [c.name, []]));
for (const c of components) {
  for (const dep of c.dependsOn) dependents.get(dep)?.push(c.name);
}

let written = 0;
const drifted = [];

for (const component of components) {
  const pages = {
    "overview.md": overview(component, byName, dependents.get(component.name) ?? []),
    "architecture.md": architecture(component),
    "runbook.md": runbook(component),
  };
  const dir = path.join(component.dir, "docs");
  for (const [file, body] of Object.entries(pages)) {
    const target = path.join(dir, file);
    const current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : null;
    if (current === body) continue;
    if (checkOnly) {
      drifted.push(path.relative(ROOT, target));
      continue;
    }
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(target, body);
    written += 1;
  }
}

if (checkOnly) {
  if (drifted.length === 0) {
    console.log(`✓ component docs match ${components.length} component.yaml file(s)`);
    process.exit(0);
  }
  console.error(`✗ ${drifted.length} component doc(s) drifted from their component.yaml:`);
  for (const f of drifted) console.error(`    ${f}`);
  console.error("\nRun: node tooling/catalog/gen-component-docs.mjs");
  process.exit(1);
}

console.log(`✓ wrote ${written} page(s) for ${components.length} component(s)`);
