# Provenance — Cirrus from the Lumen baseline

Cirrus is a fork of the reusable Lumen SaaS baseline
(`sourceplane/lumen`), taken at commit `e1fbee6` and then diverged on
purpose. This file records what carried over and what did not, so the delta
stays auditable rather than folkloric.

## What the fork changed

**The data plane, entirely.** Lumen is Cloudflare + Supabase: managed
Postgres reached through Cloudflare Hyperdrive. Cirrus is Cloudflare-only:
the platform database is Cloudflare D1, provisioned by
`infra/terraform/cloudflare-d1` and bound to every Worker as `PLATFORM_DB`.
The `supabase` and `cloudflare-hyperdrive` terraform roots are gone, and the
migration runner speaks D1's REST API instead of Postgres.

Consequences worth knowing before reading the code:

- SQL is SQLite. Bounded-context schemas fold into table-name prefixes
  (`identity.users` → `identity_users`); UUID/TIMESTAMPTZ/JSONB/BOOLEAN are
  TEXT/INTEGER; `now()` is a `strftime` expression.
- `packages/db/src/d1` is the seam: the executor translates the repositories'
  numbered `$n` placeholders to D1's positional binds, normalizes bind
  values, and matches SQLite's constraint-failure messages where Postgres
  SQLSTATEs used to be matched.
- D1 has no interactive transaction. `executor.transaction(...)` runs its
  statements in order with no rollback, and says so at the definition.
- One provider connection (Cloudflare) instead of three, which is why the
  bootstrap asks for one consent rather than three.

**Instance identity.** Applied mechanically by
`tooling/rebrand/rebrand.mjs`:

| Field | Value |
|---|---|
| reponame | `cirrus` |
| productname | Cirrus |
| pascalName | `Cirrus` |
| brandSlug | `cirrus` |
| productdomain | `cirrus.app` |
| apibaseurl | `https://api.cirrus.app` |
| cliBin | `cirrus` |
| subdomain | `rahulvarghesepullely` |
| salesEmail | (baseline mailbox kept) |

Org-owned identity is deliberately NOT rewritten: the GitHub org, the orun
state backend, the `sourceplane.io` manifest apiVersion, and company
mailboxes stay as they are.

## What carried over unchanged

The bootstrap machinery: the phase sequence `01-scaffold … 08-docs` and the
contract each phase follows — place its modules, land them, watch the
convergence, verify the outcome. It was proven end-to-end on Lumen as a shell
layer over eight workflows; it is now one `repo-blueprint.yaml` read by
`orun new`, which changes where the mechanism lives but not what any phase
does. Cirrus changes what `03-infrastructure` deploys, not how any phase
runs. `docs/phases/TIMINGS.md` marks which timings are inherited measurements
and which are Cirrus estimates awaiting a real run.

## Operator checklist (what no script can do)

1. A Cloudflare account API token whose permission groups include **D1
   Write** as well as the Workers/KV groups — the `d1-edit` mint is refused
   without it.
2. The product repo allow-listed in the workspace (console → Settings → Git
   repos). This is the one console action a workspace-scoped token cannot
   self-heal.
3. An **admin-role** workspace API key for headless runs; builder and viewer
   keys read fine but their secret writes are denied (masked as
   `not_found`).
4. Post-bootstrap runtime credentials — OAuth client secrets, billing keys —
   seeded with `orun secrets set`. Nothing blocks on them.
