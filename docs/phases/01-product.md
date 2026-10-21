# Phase 01 — the product, in one landing

The whole product lands as ONE pull request, and ONE convergence on main
deploys it: the shared packages, the D1 and KV data plane, the migrations,
the twelve-worker fleet with its service bindings, the API edge and the web
console, on stage and prod.

Before baseline-v22 this was five landings: 01-scaffold, 02-foundation (with
the data plane that was 03), 04-workers (the fleet deployed without its
bindings), 05-edge (the fleet redeployed with them, the edge and the console
that was 06). Each landing paid a fixed cost — place, open a PR, merge, wait
for the convergence to start — and the fleet was deployed twice. None of
that order is lost; the plan carries it.

## How one convergence keeps the order

| what has to come first | how the plan holds it |
|---|---|
| D1 and KV before anything that reads their wiring | every component with a `WIRING_CLOUDFLARE_D1`/`_KV` secret declares `dependsOn: cloudflare-d1` (and `cloudflare-kv`), `mode: enforced` on main. A job resolves its secrets when it STARTS, so the ids the apply lease-published are there |
| the migrations after D1 | `db-migrate` depends on `cloudflare-d1` (enforced, as before) |
| a service binding's target before the worker that binds it | `policy-worker` binds to nothing, and every worker that holds a binding depends on it, `mode: enforced`. Its pre-deploy runs `tooling/deploy/fleet-stubs.mjs`, which uploads a placeholder for each binding target in the environment that does not exist yet. Every real deploy then starts with all its targets present, carries its FULL bindings, and replaces its own placeholder |
| peer workers | stay `advisory` — runtime calls, not deploy order — so the fleet deploys side by side across the environment's lanes |

The placeholders are race-free because nothing that holds a binding deploys
while they are created: all of them wait on `policy-worker`. On a live
product every target exists and `fleet-stubs.mjs` uploads nothing. Pull
requests deploy nothing, so every one of these edges is advisory on a PR.

Cloudflare's 10143 (a binding to a Worker that does not exist) made the
fleet's cycles undeployable on a fresh account (billing ↔ membership;
membership → notifications → events → membership). The phased bootstrap
broke them with `cycle-break.mjs --strip --all` in 04 and `--restore` in 05.
That tool and its second fleet deploy are gone.

## What it lands

Every module of `repo-blueprint.yaml`: the root manifests, CI, tooling and
identity; the thirteen shared packages; `cloudflare-d1`, `cloudflare-kv` and
`db-migrate`; the twelve workers; `api-edge` and `web-console-next`; their
tests; and `cloudflare-domain`, parked (below). `testing/phases.test.sh`
holds the set: modules move whole, and nothing else moves with them.

## The custom domain — parked

`infra/terraform/cloudflare-domain` (records, and worker routes or custom
domains for the edge and the console per environment) lands with everything
else, and **deploys nothing**: its `component.yaml` declares
`subscribe.environments: []`, so CI plans no lanes for it. The product runs
on workers.dev URLs until an owner wires it.

It used to land on its own as the optional `07-domain` phase, behind a
`domain` input. That landing deployed nothing either — its convergence was a
green run with nothing in it — so the phase and the switch are gone, and the
task contract's `affects` leaves the component out: there is nothing in it
to re-plan.

Wiring it is a normal pull request in the product, once the zone exists:

1. **The zone first.** The product zone (e.g. `acme.dev`) must already exist
   in the Cloudflare account the product deploys into, created in the
   dashboard; zone creation is an account-plan operation the platform does
   not broker. The terraform manages records and routes IN the zone, not the
   zone itself — without it the plan fails with *zone not found* (or the
   brokered token's account is not the zone's).
2. **Restore the `subscribe` block** the component carries commented out,
   and finish the provider-v5 re-import its comment names (the component's
   `README.md` says where that migration stands).
3. **Land it.** The convergence on `main` applies it; check the product
   resolves on its own domain (DNS propagation applies), then re-run
   [`08-docs`](08-docs.md) so the deployment manifest records the
   custom-domain URLs.

## Inputs

| input | example | notes |
|---|---|---|
| `--out` | `$HOME/sourceplane/acme` | a flag, not an input; created if absent |
| `reponame` | `acme` | REQUIRED. Lowercase slug (`^[a-z][a-z0-9-]*$`); repo becomes `<githuborg>/<reponame>` |
| `productname` | `Acme Cloud` | REQUIRED. Display name |
| `productdomain` | `acme.dev` | REQUIRED. Product domain |
| `githuborg` | `sourceplane` | REQUIRED. The org or user the repo is created under |
| `orunWorkspace` | `ws_FGBDTQ8T` | workspace id. Unset, the workspace the build runs in (ORUN_WORKSPACE); with none anywhere, a placeholder that fails loudly rather than silently cross-tenanting |
| `subdomain` | `rahulvarghesepullely` | workers.dev subdomain of the Cloudflare account you deploy into. A console or `--from bst_…` build reads it from the Cloudflare connection; pass it only for a hand-run build |
| `apibaseurl` | `https://api.acme.dev` | CLI default API base; empty derives from `productdomain` |
| `epicSlug` | `infra-baselining` (default) | the epic every phase files its task under |

## Prerequisites

`requires.probe` waits (up to 10 minutes each) for the GitHub connection of
the account that OWNS the repository — the platform sees a PR only through
that installation — and for the Cloudflare connection, which every deploy
credential is minted from.

## Steps

1. **place** — the engine writes every module into `--out`.
2. **retouch** — one trailing `# orun: redeploy 01-product <stamp>` line in
   each component the task contract `affects`, so a RE-RUN has a diff to land
   (a convergence can fail after its PR merged; see `retouch.mjs`).
3. **the identity chain**: `git init` → `git add` → `rebrand.mjs` → the
   intent `workspace:` rewrite → `promotion.mjs --defer` and
   `dev-lanes.mjs --defer` (prod deploys beside stage, and dev's verify lanes
   stay off main, until 08-docs puts both back) → `git add` →
   `rebrand.mjs --verify` → `pnpm install --lockfile-only` (a no-op: the
   baseline's complete lockfile is already placed) → the console artifact
   pin.
4. **repo** — `orun.repo/ensure@v1`: an existing `origin` is pushed to; a
   repo pre-created empty on GitHub is detected and wired; otherwise it is
   created under `githuborg`.
5. **link** — the repository becomes the workspace's (`orun cloud link`,
   best effort; `orun cloud check` is the gate). Every convergence lane
   authenticates over GitHub OIDC through that link.
6. **the deploy credentials** — `CLOUDFLARE_API_TOKEN` (workers-deploy),
   `CLOUDFLARE_D1_TOKEN` (d1-edit) and `CLOUDFLARE_ACCOUNT_ID`, each minted by
   `orun.integrations/reconcile@v1` from its own scope template; keys that
   exist are kept.
7. **land** — `orun.pr/land@v1`, one PR bound to the phase's task. Its check
   is `plan` alone on a bootstrap branch; the convergence after the merge is
   the real gate.
8. **await** — the convergence for the merged commit (`orun.run/watch@v1`,
   up to three resumes), the wiring secrets on stage and prod, and a probe of
   the four URLs.

## Verify / done means

- `WIRING_CLOUDFLARE_D1` and `WIRING_CLOUDFLARE_KV` exist on stage and prod.
- The convergence for the merge commit is green: migrations applied, every
  worker deployed once with its bindings, the edge and the console up.
- `api-edge` `/health` answers 200 and the console root answers, on stage
  and prod.

## Failure modes

| symptom | meaning → fix |
|---|---|
| a worker's deploy: 10143 (binding target not found) | `policy-worker`'s pre-deploy did not run first: the worker lacks the enforced `dependsOn: policy-worker` (`testing/fleet-stubs.test.sh` checks every binding holder), or the binding names a Worker outside `apps/` |
| `fleet-stubs: checking <name>: HTTP 403` | the workers-deploy token cannot read scripts — re-run the phase after reconnecting Cloudflare; the tool refuses to create a placeholder it cannot prove is missing |
| a lane fails resolving `WIRING_*` | the terraform lane for that environment failed — read its log; the workers wait on it, so they show as not run |
| d1 apply: database name already exists with empty platform state | `adopt.tf` looks the database up by name at plan time and imports it — if you removed that file, restore it |
| kv apply: title already exists (10014) | the same adoption, by namespace title |
| d1 apply or db-migrate: `Authentication error (10000)` | the token in play is workers-deploy, which deliberately cannot touch D1 — both components bind `CLOUDFLARE_D1_TOKEN` |
| secret resolution: `orphaned` | a provider connection was revoked or replaced — reconnect, then re-run the phase |
| `broker: limit_reached` | the workspace's daily credential-mint cap (TIMINGS.md) — a second bootstrap in one workspace within 24h |
| `/health` 5xx after a green deploy | real: the deploy lane's smoke already retried; check the worker the edge proxies to |

## Re-running

Idempotent: placement is additive, rebrand is a no-op on branded files,
`git init` and the repo step are guarded, D1 and KV are adopted rather than
recreated, and the migration ledger lives in the database, so only missing
migrations apply. A re-run of a phase whose PR already merged lands the
retouch markers alone, which re-plans exactly the components it names. Once
the tree is branded the phase derives as `drifted`, so `--resume` leaves it
alone; re-run it deliberately with `--phase 01-product` (or `--redo
01-product` under `--resume`).

## Example commands

From the baseline checkout (local mode):

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sourceplane/acme --run-hooks --phase 01-product \
  --set reponame=acme \
  --set productname="Acme Cloud" \
  --set productdomain=acme.dev \
  --set githuborg=sourceplane \
  --set orunWorkspace=ws_ABCD1234 \
  --set subdomain=rahulvarghesepullely
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
into `--out` and stops, with no git, no rebrand, no repo and no landing. Add
`--status` to derive every phase's state and write nothing at all.

What one convergence will run, before running it — from the placed tree:

```bash
node tooling/bootstrap/promotion.mjs --defer && node tooling/bootstrap/dev-lanes.mjs --defer
orun plan --all --trigger github-push-main -v lanes      # stage and prod lanes only
node tooling/deploy/fleet-stubs.mjs --root . --env stage --list
git checkout intent.yaml
```

## Next

`08-docs`, which records the live deployment and puts the promotion gate and
dev's lanes back.
