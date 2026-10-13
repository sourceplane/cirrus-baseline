# The phases — one blueprint, six selections

`repo-blueprint.yaml` declares six phases that take a product from
**nothing** to a **live, documented baseline**. Run them one at a time at
your own pace with `--phase <name>`, or run the whole sequence unattended
with `--resume`. There is no umbrella workflow and no per-phase document:
a phase is a selection on one artifact, which is what makes running one
alone, months later, from a fresh container the same operation as running
them all.

Each phase follows the same contract:

> **place its modules → land them as a PR (checked by `plan`, then merged —
> the convergence is the gate) → watch the deployment convergence
> (auto-resumed) → verify it is actually deployed.**

Run from the baseline checkout (the blueprint's source is `path: .`); the
product repo is wherever `--out` points.

## Execution order

The phase number is the EXECUTION order — the root scaffold must exist
before anything else can build or deploy. Each phase's `requires.phases`
states this in the document, and the engine refuses a phase whose
predecessor is not placed, naming it.

Every phase lands as a pull request that is checked, then merged: each landing waits for its PR's own CI to finish green — and on a bootstrap branch (`orun/BASE-…`) that CI is `plan` alone (the intent, every component and composition resolve; the changed set is computed). The lanes are skipped on those pull requests because the merge runs every one of them on main a minute later, for real, and that convergence is what each phase watches to green before the next starts. Any other pull request in the product runs its lanes as before.

| phase | lands | verified by |
|---|---|---|
| [`01-scaffold`](01-scaffold.md) | **GitHub repo created** + repo born: intent, CI, tooling, identity | repo pushed + workspace-linked |
| [`02-foundation`](02-foundation.md) | 13 shared packages + the data plane (d1, kv) | convergence green + published `WIRING_*` secrets |
| [`04-workers`](04-workers.md) | db-migrate + the 12-worker fleet, first wave: every worker-to-worker binding stripped, all deployed at once | convergence green |
| [`05-edge`](05-edge.md) | second wave: every binding restored and the fleet redeployed, + api-edge + web console | `/health` and console live on stage+prod |
| [`07-domain`](07-domain.md) | custom domain (OPTIONAL — `when: inputs.domain`) | convergence green |
| [`08-docs`](08-docs.md) | live-deployment docs (manifest + operating contract) | committed manifest matches probed reality |

## Inputs

`01-scaffold` takes the product identity once and writes it into the repo
(`.rebrand/values.json`); every later phase reads it back from the placed
tree. But the blueprint's **required** inputs — `reponame`, `productname`,
`productdomain`, `githuborg` — are validated before any phase runs, so
they must be supplied on every invocation, single-phase ones included. A
`--values` file is easier than repeating `--set`.

The three the phases used to carry as per-workflow inputs are blueprint
inputs now, which is how the console can render a form from this document
alone:

- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`: ORUN_WORKSPACE, which a console build
  always has); with none anywhere, a placeholder that fails loudly rather than
  silently cross-tenanting.
- `epicSlug` (default `infra-baselining`) — the epic every phase clubs its
  task under. Found by slug, so a fresh run and a resumed run find the same
  work.
- `domain` (default `false`) — whether to run `07-domain`. It needs the
  Cloudflare zone to already exist, so it is off unless asked for; the
  phase carries the condition as its own `when:`.

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sourceplane/acme --run-hooks --phase 02-foundation \
  --values ~/acme.values.yaml
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase
places files and stops: no repo, no landing, no convergence watch, and no
probe — which is exactly what makes a dry instantiation of this baseline
possible in CI with no workspace and no provider.

## Headless / container mode

A fresh container with two env tokens is the entire contract (see
[BOOTSTRAP.md §2](../../BOOTSTRAP.md)). Clone the baseline at a tag and the
tag pins everything: the blueprint, its modules, and the scripts its hooks
run all come from that one commit, and orun pins the checkout by digest
into its object store before any module is read.

```bash
export ORUN_TOKEN=… GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme --run-hooks \
  --phase 02-foundation --values /work/acme.values.yaml
```

Inside a baseline checkout the same command uses the local tree: the two
modes are the same files.

## Unattended: `--resume`

`--resume` places every phase not already derived as done, in dependency
order, honouring each barrier. Expected wall-clock on a clean run:
**~25–30 minutes** (an estimate until a rehearsal measures it). It was 50–65
until the bootstrap stopped paying for the same work twice:

- **Five landings, not eight.** The data plane lands with the packages
  (`02-foundation`), and the binding restore and the console land with the
  edge (`05-edge`). The numbering keeps its gaps (`03`, `06`) so the
  surviving names stay the identities the task plane and `--phase` use.
- **A landing's PR is checked, not rehearsed.** `plan` only; the lanes run
  once, on main.
- **The fleet deploys in two parallel waves** instead of a six-deep chain:
  every worker-to-worker binding is stripped for the first deploy
  (`cycle-break.mjs --strip --all`) and the peer `dependsOn` edges are
  `dependencyMode: advisory`; `05-edge` restores the bindings and redeploys
  the fleet at once.
- **Stage and prod deploy side by side** during the bootstrap: `01-scaffold`
  defers `prod.promotion` and `08-docs` restores it
  (`tooling/bootstrap/promotion.mjs`).
- **More lanes at once** (`max-parallel: 16`) and one shared pnpm store
  cache across them.

Why it can run unattended:

- **Idempotence, everywhere.** Landings and the convergence watch fall back
  to plain REST when `gh` is degraded, smokes retry route propagation
  (~4.5 m), OCI resolves retry transient 5xx, and `orun.run/watch@v1`
  auto-resumes failed lanes ×3 (`resumeBudget: 3`). A phase that failed
  partway resumes by simply being re-run.
- **Waits are declared, not slept.** `02-foundation` waits on the
  provider consent through `orun.doctor/check@v1` (up to 10 minutes), and
  `04-workers` will not start until `orun.secrets/exists@v1` finds both
  `WIRING_*` keys. A consent nobody has clicked is a *wait*, not a failure.
- **Verification is the phase's own last act.** `await` hooks re-probe the
  live endpoints and re-list the published secrets, trusting no earlier
  step's word.

## Pacing, idempotence, resume

- Run one phase today and the next whenever. Nothing expires between
  phases; each phase re-derives its own preconditions.
- **Phase state is derived from the tree, never stored.** Nothing in
  `--out` records which phases have run. A stored file would be a cache,
  and it must always be safe to delete.
- A phase whose files are all present but differ from the blueprint derives
  as **`drifted`** — which is every phase once `01-scaffold` brands the
  tree. Drift SATISFIES a successor's requirement (the files are all
  there), and `--resume` leaves a drifted phase placed rather than
  reverting your product's identity to `cirrus`. Re-place one deliberately
  with `--phase <name>`.
- **A re-run phase always has something to land.** A convergence can
  fail AFTER its PR merged, and the merge has already put every file the
  phase places on main — so a plain re-run finds nothing to commit, and the
  product's CI (`orun plan --changed`) redeploys nothing. Re-run the phase
  (`--phase <name>`, `--redo <name>` under `--resume`, or the console's
  Retry): its `retouch` hook (`tooling/bootstrap/retouch.mjs`) rewrites
  `# orun: redeploy <phase> <stamp>` as the last line of each affected
  `component.yaml`, so the landing has a diff and exactly the phase's
  components redeploy. The line is a deploy trigger, never state: nothing
  reads it back, and the invariant above holds.

## Prerequisites (once)

1. `orun auth login --device` (approve at app.orun.dev/cli/device).
2. A workspace for the product; note its `ws_…` id.
3. The two integrations connected in that workspace — GitHub and
   Cloudflare. `02-foundation` POLLS for these up to 10 minutes, so
   you can click the consent while it waits.
4. An **admin-role** API key. Note that the first credential WRITE is now
   `02-foundation`'s secret reconcile: a builder/viewer key gets
   through `01-scaffold` and dies at phase two with
   the re-mint-as-admin hint. The shell layer probed this at minute two;
   restoring an early write-probe as a declared precondition is tracked as
   the epic's open question 14.

## The mechanism, as typed actions

Everything the phases do that is not placing files is a **typed action** —
a closed registry inside the orun binary, not a script this repo ships:

| action | role |
|---|---|
| `orun.task/ensure@v1` | the phase's own task in the workspace's task plane: find-or-create by identity under `epicSlug`, contract attached from `tasks/<phase>.TaskContract.yaml`. Never blocks a landing |
| `orun.repo/ensure@v1` | create the product repo under `githuborg` if it does not exist (pre-created is supported) |
| `orun.pr/land@v1` | commit → branch → PR → wait for checks → merge → back on main, through the provenance pen so the landing binds to the phase's task |
| `orun.run/watch@v1` | wait for the main convergence run; auto-resume through transient failures (`resumeBudget: 3`) |
| `orun.doctor/check@v1` | the provider-consent wait — a precondition, not a preamble |
| `orun.secrets/exists@v1` | assert the keys a later phase reads are published |
| `orun.integrations/reconcile@v1` | bring the brokered provider secrets to their declared state: keys that exist are KEPT, keys that are missing are minted against the ACTIVE connection. It never holds a value — a brokered secret is a pointer at a connection and a scope template |
| `orun.http/probe@v1` | probe the live `/health` and console URLs |

The hooks that still `run:` a command are the ones that are this
baseline's own business rather than a verb any bootstrap needs: git init /
stage / restage and `pnpm install --lockfile-only` in `01-scaffold`,
`tooling/rebrand/rebrand.mjs` (the identity rename, then `--verify`),
`tooling/bootstrap/cycle-break.mjs` (strip and restore the service bindings
across the fleet's two waves), `tooling/bootstrap/promotion.mjs` (defer and
restore the prod promotion gate), `tooling/bootstrap/retouch.mjs` (the
redeploy marker every deploying phase writes before it lands), and
`hooks/render-deployment-docs.sh`
(`08-docs`'s renderer). Each resolves the baseline checkout as
`{{ .baseline.dir }}`, so a pinned clone pins them too.

## Tracking the bootstrap as work (BT)

The whole programme is on the plane before the first phase places a file:
the blueprint's run-level `hooks.preInstantiate` list (orun ≥ v2.60) opens
the `epicSlug` epic with its description, one milestone per phase in phase
order with the phase's verify assertions as exit criteria, and one task per
landing with a brief — so a reader can open the epic while `01-scaffold` is
still creating the repository. Every phase's `pre` hook is then an
`orun.task/ensure@v1` on its own task: the same identity (title within the
epic), so it finds rather than creates, and yields the key its landing binds
the pull request to. A task title is an imperative sentence about the outcome
("Deploy the worker fleet"); the pull request that lands it carries a
conventional-commit title of its own (`feat(workers): …`). The milestone keeps
the phase's name, which is the identity the engine's events, the plane's
evidence and the console's rows meet on. The contract templates live in
`tasks/` at the repo root, one per landing, named by the hooks' `contract:`
field. `gates: []` is a declaration: merge alone
finishes the task, because the main convergence is the gate the phase
*watches*, not one the plane observes as a PR check. The templates are
baseline machinery, never product content. The whole design:
`specs/epics/saas-baseline-tracking/`.

## Why there is one document

Until BE1 each phase folder carried a `blueprint.yaml` slice derived by
`tooling/blueprint/split-phases.py`, and the derivation had to PRUNE every
cross-phase `dependsOn` edge, because a slice that names a module in
another slice does not parse.

The prune is what is really gone. orun's phase overlay enforces the same
barrier by REFUSING a dependency that points forward across it, and a
refusal and a deletion are not the same thing — the splitter was deleting
`shared`'s `dependsOn: [bootstrap]`, an edge to a module that does not
exist and never has, for as long as it ran. A pruned edge to a module in
no phase looks exactly like a pruned edge to a module in an earlier one.
