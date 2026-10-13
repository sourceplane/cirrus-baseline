# Phase 02 — foundation and data plane

Lands the **13 shared packages** everything later builds on **and the data
plane** — D1 and KV on stage and prod (`repo-blueprint.yaml`, phase
`02-foundation`). The two were separate landings (`02-foundation`, then
`03-infrastructure`) until the bootstrap folded them into one: no package
reads D1 and Terraform builds none of the packages, so they converge side by
side in one run and the bootstrap pays one landing for them. This is the
first phase that touches Cloudflare: it waits for the provider consent and
mints the brokered secrets before it places anything.

The landing's pull request is checked by `plan` only — the lanes run once,
on main, in the convergence this phase watches (see [the README](README.md)).

## What it lands

`packages/`: `cli`, `contracts` (+tests), `db` (+tests),
`notifications-client` (+tests), `policy-engine` (+tests), `sdk`,
`shared`, `testing`, `webhook-verifier` — each a `turbo-package` component
whose lanes build and test it in CI.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation (a `--values` file beats repeating
`--set`); everything else this phase needs it reads back from the placed
tree. See [the phases README](README.md).

Identity comes from the repo's `.rebrand/values.json`, written once by
`01-scaffold`.

## Steps

1. **place** — the engine writes this phase's modules into `--out` and
   archives the provenance lock. The tree was branded once by
   `01-scaffold`, so these files land already speaking the product's name.
2. **land** — `orun.pr/land@v1` (a `post` hook): PR
   `feat(foundation): the shared packages, and D1 and KV on stage and prod`,
   waits for its `plan` check, merges.
3. **converge** — `orun.run/watch@v1` (an `await` hook) waits for the main
   convergence run — package builds and tests beside the D1 and KV applies —
   and auto-resumes transient lanes ×3.
4. **verify** — `orun.secrets/exists@v1` finds `WIRING_CLOUDFLARE_D1` and
   `WIRING_CLOUDFLARE_KV` published on stage and prod.

## Verify / done means

The main convergence run is green — every package builds and its tests
pass in the product repo, and D1 and KV are applied with their wiring
secrets published (below).

## Troubleshooting

- **Main lanes fail building a package**: the baseline's packages are
  self-contained; a failure here usually means a partial apply (re-run the
  phase — apply is additive) or a pnpm lock drift (the scaffold carries
  the lock; don't regenerate it mid-phase).
- **The landing picks up edits you did not intend**: commit or stash your
  local changes in the product repo before running a phase. `orun.pr/land@v1`
  lands what is in the tree, and a phase is meant to land its own modules,
  not your work in progress.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 02-foundation --values ~/acme.values.yaml
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 02-foundation --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no repo, no landing, no convergence watch and no probe. Add
`--status` to derive every phase's state and write nothing at all.
Re-running a completed phase is always safe (idempotent): the placement is a
no-op, the landing finds nothing, and the `await` hooks re-assert.

## Next

[Phase 04 — workers](04-workers.md).

## The data plane (formerly phase 03)


The first phase that **deploys**: lands the data plane
(now part of `repo-blueprint.yaml` phase `02-foundation`) and converges it against real
providers. Its terraform outputs are published as job-output secrets that
every later phase consumes.

### What it lands

`infra/terraform/`: `cloudflare-d1` and `cloudflare-kv` — each a `terraform`
component with the self-healing `adopt.tf` import machinery.

The merge's convergence applies them in parallel. On success each apply
lease-publishes its outputs to the project/env secret rungs:
`WIRING_CLOUDFLARE_D1`, `WIRING_CLOUDFLARE_KV`.

`infra/db-migrate` is data plane too, but it lands with
[`04-workers`](04-workers.md): its PR lane plans the migrations against the
database this phase creates, whose id exists only once this phase's merge has
applied. Here, that lane was red on every fresh product and the phase could not
be verified before it merged.

This is the phase where being Cloudflare-only pays: D1 databases are created
in seconds, so the phase that took ten minutes on a Postgres-backed baseline
(waiting for a managed project to provision) now converges in about two.

### Prerequisites

Both integrations ACTIVE in the workspace (preflight polls up to 10m so the
consent can be clicked while it waits), plus:

- Cloudflare account on the Workers paid plan.

### Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation (a `--values` file beats repeating
`--set`); everything else this phase needs it reads back from the placed
tree. See [the phases README](README.md).

### Steps

1. **requires.probe** — `orun.doctor/check@v1` polls for the GitHub and
   Cloudflare consents (up to 10 minutes). This is a declared precondition
   of the phase, not a preamble: a consent nobody has clicked is a *wait*,
   and the phase says so rather than failing.
2. **secrets** — three `orun.integrations/reconcile@v1` `pre` hooks mint the
   brokered provider keys (workers-deploy / d1-edit / account-id). A
   reconcile, not a create: keys that exist are KEPT, and orphaned keys are
   re-made against the current ACTIVE connection. Each holds no value — a
   brokered secret is a pointer at a connection and a scope template.
3. **place** → **land** → **converge** — the standard contract: the landing
   waits for the PR's terraform plan lanes (which resolve the minted keys on
   the PR, over remote state) and merges only on green; the convergence then
   applies.
4. **verify** — an `orun.secrets/exists@v1` `await` hook asserts
   `WIRING_CLOUDFLARE_D1` and `WIRING_CLOUDFLARE_KV` exist on the project's
   **stage and prod** environment rungs (`project` + `environments`, orun ≥
   v2.58.8 — read at the workspace rung, where nothing is published, it could
   never pass). A missing key is named per environment and means that
   environment's apply did not publish — check that lane first. `04-workers` re-asserts the same two keys as its own
   `requires.probe`, so it will not start on a half-applied phase 02.

### Failure modes we have actually hit

| symptom | meaning → fix |
|---|---|
| d1 apply: database name already exists with empty platform state | `adopt.tf` looks the database up by name at plan time and imports it — if you removed that file, restore it |
| kv apply: title already exists (10014) with empty platform state | same adoption machinery, by namespace title |
| d1 apply or db-migrate: `Authentication error (10000)` | the token in play is `workers-deploy`, which deliberately cannot touch D1 — both components must bind `CLOUDFLARE_D1_TOKEN` (the `d1-edit` template) |
| db-migrate: `no such table: _migrations_applied` | the runner creates its ledger on connect; this means the apply ran against a different database — check `WIRING_CLOUDFLARE_D1` for the environment |
| secret resolution: `orphaned` | a provider connection was revoked/replaced — re-connect, then re-run the phase (the reconcile re-mints only the missing keys) |
| verify: WIRING keys missing | the corresponding terraform lane failed or was skipped — `gh run view` the convergence run, fix, re-run the phase |

### Re-bootstrapping an EXISTING product

Adoption makes this safe for both roots: an existing D1 database or KV
namespace is imported at plan time rather than colliding. The database's
CONTENTS are untouched by adoption, and the migration runner's applied
ledger lives in the database itself — so a re-bootstrap re-applies only the
migrations that are genuinely missing.

### Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 02-foundation --values ~/acme.values.yaml
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 02-foundation --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no repo, no landing, no convergence watch and no probe. Add
`--status` to derive every phase's state and write nothing at all.
Re-running a completed phase is always safe (idempotent): the placement is a
no-op, the landing finds nothing, and the `await` hooks re-assert.

Prerequisite reminder: both integrations (GitHub, Cloudflare) must be
ACTIVE in the workspace — this phase's `requires.probe` polls up to 10m so
the consent can be clicked while it waits. Check first with:

```bash
orun integrations list ws_ABCD1234
```
