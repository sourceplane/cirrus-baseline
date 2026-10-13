# Decisions

Last updated: 2026-08-04

Cirrus forked the Lumen baseline and became the Cloudflare-only one. This file
records the decisions that hold for THIS baseline. Lumen's decision log is not
reproduced here — where a decision carried over unchanged it is restated, and
where Cirrus diverged the divergence is the entry.

## Active Decisions

### Provider surface

- **Cloudflare is the only provider.** Workers for compute, D1 for the
  database, KV for the edge idempotency store, Cloudflare Email Service for
  notifications. A bootstrap needs one integration consent and one account
  token. Anything that would add a second provider needs a decision entry
  here first — it costs the baseline its defining property.
- **Two brokered token scopes, not one.** `CLOUDFLARE_API_TOKEN`
  (`workers-deploy`) covers Workers and KV; `CLOUDFLARE_D1_TOKEN` (`d1-edit`)
  covers D1. Splitting them keeps the deploy token unable to touch the
  database, which is worth the extra secret.
- **`CLOUDFLARE_ACCOUNT_ID` is a connection fact**, not a secret: the
  `account-id` template mints nothing and there is nothing to revoke.

### Database

- **Cloudflare D1 is the platform database**, one per environment,
  provisioned by `infra/terraform/cloudflare-d1`. `dev` has none by design —
  it is verify-only.
- **One database, not one per bounded context.** D1 offers no cross-database
  query or foreign key, and the console's read paths join across contexts.
  Splitting would move those joins into the workers; the isolation is not
  worth that at this size.
- **Bounded-context boundaries are table-name prefixes**
  (`identity_users`, `membership_organizations`), enforced by the
  repositories. SQLite has no schemas — and Postgres schemas were never what
  enforced the boundary either.
- **`executor.transaction(...)` does not roll back.** D1 has no interactive
  transaction; the callback's statements run in order and a mid-way failure
  leaves the earlier ones applied. The method stays (rather than being
  deleted) so every place that WANTED atomicity is still visible in the code.
  Where all-or-nothing genuinely matters, use one statement with `RETURNING`
  or an upsert with `ON CONFLICT`.
- **Repositories keep numbered `$n` placeholders.** They are reused and
  reordered across ~50 statements, which positional `?` cannot express; the
  D1 executor translates them once, in one tested place.
- **Timestamps are ISO-8601 text** (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`),
  not SQLite's default `CURRENT_TIMESTAMP` format — every row mapper calls
  `new Date(...)` on them, and the default format parses inconsistently.
- **Column adds are made idempotent by the runner's applied ledger**, not by
  the statement: SQLite has no `ADD COLUMN IF NOT EXISTS`.
- **Migration checksums are generated, never typed**
  (`tooling/migrations/rechecksum.mjs`). Rechecksumming an ALREADY-APPLIED
  migration defeats the drift guard rather than satisfying it — write a
  forward migration instead.

### Deployment and state

- Terraform state lives in the Orun Cloud HTTP state backend. There is no
  AWS in the loop: no state buckets, no Secrets Manager, no OIDC roles to
  maintain.
- CI holds exactly one credential, `GITHUB_TOKEN`. Provider credentials are
  brokered per run from the workspace's integration connections.
- Every terraform root carries `adopt.tf`: an existing resource is imported
  at plan time rather than colliding, so a re-bootstrap over a half-torn-down
  attempt heals.
- Merges to `main` converge automatically; the convergence run IS the
  deployment. A push touching no component files plans zero lanes and is
  green while deploying nothing — assert outcomes, never run status.

### Baseline machinery

- **The blueprint is the bootstrap.** There is one artifact,
  `repo-blueprint.yaml`, and `orun new --phase <name>` is the whole runtime;
  the phases are `01-scaffold … 08-docs`. The shell layer that used to wrap
  it was deleted once every one of its mechanisms existed in the binary as a
  typed action — a bootstrap should not be a program the baseline ships.
- **Phase state is derived, never stored.** The engine asks the tree which
  phases are placed. Anything written down would be a cache, and it must
  always be safe to delete — which is what lets a phase be run alone, months
  later, from a fresh container.
- **Products receive product-only content.** The scaffold blueprint ships
  source, infra, CI, and the product's own docs; `repo-blueprint.yaml`,
  `agents/`, `tooling/{rebrand,blueprint,bootstrap,migrations,catalog}`, and
  the baseline's planning state stay in the baseline. A product's docs speak
  about the product, not about the factory that made it. `testing/leak.test.sh`
  gates that promise by deriving what every phase would place.
- Component catalog docs are generated from `component.yaml`
  (`tooling/catalog/gen-component-docs.mjs --check` fails on drift). Prose
  that is genuinely per-component belongs in `specs/`.
- Timings in `docs/phases/TIMINGS.md` are labeled by provenance: inherited
  measurements from Lumen, or Cirrus estimates awaiting a real run. An
  estimate must never be presented as a measurement.

## Pending Decisions

- **Phase 03's timing is an estimate.** Replace it with a measurement after
  the first full Cirrus bootstrap.
- Whether any of the ~20 `transaction(...)` call sites need reshaping into
  single-statement upserts. They were written against a database that could
  roll back; each should be reviewed on its own merits rather than in bulk.
- Durable idempotency for invitation creation remains deferred:
  `idempotency-key` is forwarded by api-edge but not stored, so duplicate
  creates may produce duplicate pending invitations to the same email.
- Cursor pagination is settled (limit/cursor, default 50, max 100, opaque
  versioned cursors, `meta.cursor`); new list endpoints follow it from day
  one.
