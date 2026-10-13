# Phase 05 — the second wave: bindings, edge and console

Puts back **every service binding** the fleet deployed without in
[`04-workers`](04-workers.md) and redeploys the fleet with them, and lands the
**API edge** — the single public entry point fronting the fleet — and the
**web console** beside it (`repo-blueprint.yaml`, phase `05-edge`). One
landing, one convergence, everything side by side.

These were three landings — `04-workers-restore`, `05-edge` and
`06-console` — until the bootstrap folded them into one. None of them waits
on another's deploy: every worker a binding names already exists after
`04-workers`, the edge binds only to those workers, and the console reaches
the edge by URL. The console still deploys after the edge inside the run
(its `dependsOn: api-edge` is enforced on main), and the console build is the
long pole.

## What it lands

- every worker-to-worker binding, restored byte-for-byte by
  `tooling/bootstrap/cycle-break.mjs --restore` — so every worker that binds
  to another redeploys;
- `apps/api-edge` (+ its test component): the gateway worker with service
  bindings to the fleet from phase 04, the idempotency KV binding (id from
  `WIRING_CLOUDFLARE_KV`), and the D1 binding (database id from
  `WIRING_CLOUDFLARE_D1`).
- `apps/web-console-next` (+ its test component): the Next.js console built
  and deployed as a Cloudflare worker with static assets, configured against
  the edge.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation (a `--values` file beats repeating
`--set`); everything else this phase needs it reads back from the placed
tree. See [the phases README](README.md).

## Steps

1. **place** — the edge and the console; then the `post` hooks write the
   retouch marker on every component in the contract (the edge, the console
   and every worker that binds to another) and run
   `cycle-break.mjs --restore`.
2. **land** — PR `feat(edge): the fleet's bindings, the API edge and the web
   console`, checked by `plan` and merged.
3. **converge** — the merge redeploys the bound workers and deploys the edge
   and the console, on both environments at once (budget 45m, auto-resumed
   ×3).
4. **verify** — an `orun.http/probe@v1` `await` hook probes the edge's
   `/health` and the console root on stage and prod, and fails on any dead
   endpoint (the URLs are templated from the blueprint's own inputs).

## Verify / done means

The edge's `/health` and the console root answer 2xx–4xx (a 4xx is "alive
but unauthorized", which counts as deployed; 5xx/timeout does not) on BOTH
environments, and the convergence that redeployed the fleet with its bindings
is green.

## Troubleshooting

- **A worker's deploy fails on a missing service binding (10143)**:
  `04-workers` did not converge — every binding target has to exist before
  this wave. Re-run `04-workers` first.
- **`/health` 5xx after a green deploy**: the edge boots but a downstream
  binding misbehaves — check the worker it proxies to; the smoke in the
  deploy lane retried ~75s already, so this is real, not propagation.
- **Smoke fails right after the very first deploy**: a brand-new
  workers.dev route can 4xx for a few seconds — the deploy lane's smoke
  already retries ~75s (stack-tectonic ≥ 0.18.1); a persistent failure is
  real. Check the console's build output in the lane log.
- **Console up, edge probes fail**: re-run `05-edge` (`--redo 05-edge` under
  `--resume`); the console is static assets and can be "up" while the API
  behind it is not.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 05-edge --values ~/acme.values.yaml
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 05-edge --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no repo, no landing, no convergence watch and no probe. Add
`--status` to derive every phase's state and write nothing at all.
Re-running a completed phase is always safe (idempotent): the placement is a
no-op, the landing finds nothing, and the `await` hooks re-assert.

On success the verify step has already probed
`https://acme-api-edge-{stage,prod}.<subdomain>.workers.dev/health`.

## Next

[Phase 07 — domain](07-domain.md) when the build asks for one, else
[Phase 08 — docs](08-docs.md).
