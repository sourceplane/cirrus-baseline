# Phase 04 — workers

Lands the **database migrations** and the **12-worker fleet**
(`repo-blueprint.yaml`, phase `04-workers`) as the **first of two waves**:
every worker-to-worker service binding is stripped, so the whole fleet deploys
at once instead of in dependency order. [`05-edge`](05-edge.md) restores the
bindings and redeploys the fleet as the second wave, beside the edge and the
console.

## What it lands

`infra/db-migrate` — the migration runner, applied to the D1 database phase 02
created; it plans on the PR (the database id exists by now) and applies after
the merge, ahead of the workers that read the schema.

`apps/`: `policy-worker`, `membership-worker`, `events-worker`,
`projects-worker`, `identity-worker`, `config-worker`, `webhooks-worker`,
`notifications-worker`, `metering-worker`, `admin-worker`,
`billing-worker`, `integrations-worker` — plus their test components.
Each worker's deploy renders its committed `wrangler.template.jsonc`
(`@@wiring(...)@@` tokens) from the `WIRING_*` secrets phase 02 published,
and reads its own runtime keys wire-now-seed-later (inert until seeded).

## Why two waves, and why each is one wave

A Cloudflare service binding cannot name a worker that does not exist yet
(error 10143), and the workers bind to each other: billing to policy,
membership to billing, identity to notifications, and a
`billing → membership → notifications → events → membership` cycle on top.
Deployed WITH their bindings, the fleet had to go in dependency order — a
six-deep chain of deploys, on stage and again on prod — and the cycle could
not deploy at all. Until this change the bootstrap stripped only the two
feedback edges that break the cycle and deployed the rest in that order.

Now the first deploy carries no worker-to-worker binding at all, and nothing
waits on anything but its migration:

- `tooling/bootstrap/cycle-break.mjs --strip --all` removes every
  worker-to-worker binding (byte-preserving markers) before this landing;
- each worker's peer `dependsOn` edges are `dependencyMode: advisory` on
  stage and prod (in its `component.yaml`) — they are runtime calls, not
  deploy order, once every target exists;
- `cycle-break.mjs --restore`, in [`05-edge`](05-edge.md), puts every
  binding back byte-for-byte, and that landing redeploys the fleet with them
  — again all at once, since every target now exists.

Both are idempotent; `--check` reports the current state. `--strip` without
`--all` still strips only the two feedback edges, for a product that wants
the old shape.

Stage and prod deploy side by side, too: `01-scaffold` defers intent.yaml's
`prod.promotion` gate for the length of the bootstrap and
[`08-docs`](08-docs.md) restores it (`tooling/bootstrap/promotion.mjs`).

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation (a `--values` file beats repeating
`--set`); everything else this phase needs it reads back from the placed
tree. See [the phases README](README.md).

## Steps

1. **requires.probe** — `orun.secrets/exists@v1` asserts both
   `WIRING_CLOUDFLARE_D1` and `WIRING_CLOUDFLARE_KV` are published before a
   single file is placed. Missing keys mean `02-foundation` did not
   finish, and the phase says which.
2. **place** — this phase's modules, then a `post` hook runs
   `tooling/bootstrap/cycle-break.mjs --strip --all`.
3. **land** — PR `feat(workers): the migrations and the twelve-worker fleet,
   first wave without bindings`, checked by `plan` and merged.
4. **converge** — the merge deploys the fleet, every worker at once on both
   environments (budget 40m, auto-resumed ×3). Lanes resolve their
   `WIRING_*` secrets at claim time. The second wave is
   [`05-edge`](05-edge.md).

## Verify / done means

The convergence run is green: every worker deployed without its bindings and
its smoke passed (the bindings come back in `05-edge`) (smoke retries ~75s over
first-deploy workers.dev propagation — stack-tectonic ≥ 0.18.1).

## Troubleshooting

- **Lane fails resolving `WIRING_*`**: `02-foundation` incomplete — both
  its own `await` verify and this phase's `requires.probe` assert these;
  re-run `02-foundation`.
- **Cloudflare 10143 (service binding target not found)** in this landing:
  a binding the strip did not cover — `node tooling/bootstrap/cycle-break.mjs
  --check` in the product repo. `--all` strips bindings to every directory
  under `apps/` ending in `-worker`; a worker named otherwise needs adding.
- **Convergence trips on runner starvation / resolve throttling**: that is
  what the auto-resume is for; a genuinely red lane stays red across
  resumes — read that lane's log.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 04-workers --values ~/acme.values.yaml
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 04-workers --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no repo, no landing, no convergence watch and no probe. Add
`--status` to derive every phase's state and write nothing at all.
Re-running a completed phase is always safe (idempotent): the placement is a
no-op, the landing finds nothing, and the `await` hooks re-assert.

This is the longest single convergence of the bootstrap (the whole fleet on
two environments; about 8 minutes once the waves are parallel). A
convergence that trips resumes itself up to 3×; a failed phase run resumes
by re-running the same command with its own `--phase`.

## Next

[Phase 05 — edge](05-edge.md).
