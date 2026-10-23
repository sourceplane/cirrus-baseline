# Bootstrap timings — what to budget, and where the numbers come from

**Measured.** The numbers below are one bootstrap of `baseline-v22` on
2026-10-15: `pullely/cirrus-timing-7`, built from a checkout of the tag with
`orun new --blueprint repo-blueprint.yaml --run-hooks` (orun 2.78.4) — the
pipeline `orun baseline new --local` runs, used here because the registry
still published v21 — from a laptop into a fresh workspace `cirrus-v22-test`
(`ws_QSR13SSQ`), GitHub-hosted runners, lanes `auto` at `maxLanes: 18`,
`concurrency: auto`, dev's lanes deferred for the bootstrap, and the console
deployed from the prebuilt artifact. One run is a measurement, not a
distribution; replace it when a better one exists. **The full bootstrap took
10m02s and every URL was live at 7m55s** — 4m49s and 4m03s under v21, with
both phases green on their first attempt.

## Per-phase (baseline-v22)

Phase time is the engine's own `done` narration. Prep is the phase's first
narration line to its PR being opened (local render, rebrand, install,
repository, link, credential reconciles, commit, push). PR CI is the landing
PR's run (`plan` only: a pull request deploys nothing). Main is the
`push: main` convergence, merge to `updated`. Lanes are the plan's lane count;
orun jobs are the jobs those lanes ran (one check run each).

| phase | time | prep | PR CI | merge → main start | main run | lanes / orun jobs | main attempts |
|---|---|---|---|---|---|---|---|
| 01 product | **8m23s** | 0.57m | 1.18m (the landing waits for it) | 3s | 5.7m | 18 / 50 | 1 |
| 07 domain | not run | | | | | | |
| 08 docs | **57s** | 0.2m | 0.28m | 3s | 0.65m | 0 / 0 (plan only) | 1 |

| | wall-clock (from the first command, 16:48:28Z) |
|---|---|
| stage console first 200 | 5m05s |
| prod console first 200 | 5m07s |
| stage `api-edge` `/health` first 200 | 7m31s |
| prod `api-edge` `/health` first 200 | 7m55s |
| **URLs live** (the last of the four) | **7m55s** |
| **full bootstrap** (exit 0) | **10m02s** |

### Where the ten minutes go

| from the first command | what |
|---|---|
| 0:00–0:27 | run-level hooks: the epic, three milestones and three tasks |
| 0:27–1:01 | 01-product prep; PR #1 opened at 1:01 |
| 1:06–2:17 | the PR's CI: its `plan` job queued 54s for a runner, then ran 16s |
| 2:30 | PR #1 merged; the convergence was created at 2:33 |
| 2:36–3:33 | the convergence's `plan` job (57s) |
| 3:36 | all 18 lanes start, stage and prod side by side |
| 5:05 | the consoles answer (prebuilt artifact, deployed 85s into their lanes) |
| 5:12 / 5:16 | policy-worker deployed on stage / prod, after `fleet-stubs` uploaded 11 placeholders in each (10.1s / 8.6s); the 11 binding holders start |
| 6:44 / 6:52 | `api-edge` starts on stage / prod — third in a two-slot lane, behind billing and config |
| 7:31 / 7:55 | `api-edge` `/health` answers on stage / prod |
| 8:14 | the convergence finishes; the slowest lane is the prod console (4m36s), 3m00s of it a smoke retrying until `api-edge` answers |
| 8:45 | the watch reports green, 31s after the run finished |
| 8:49 | wiring secrets and the four URLs verified; 01-product done |
| 9:46 | 08-docs done (PR #2 merged after its 17s PR run) |
| 10:02 | exit 0 |

Run ids, all on `pullely/cirrus-timing-7`: 01 PR run 38772209314, 01 main run
38772406988, 08 main run 38773396423. All 67 GitHub jobs of the 01
convergence were green on attempt 1: one deploy per worker per environment,
no Cloudflare `10143` anywhere, and each of the 11 binding holders started
its deploy after policy-worker's had finished in its environment. The
stamped build log, the URL probe log and the per-run job lists are what these
come from.

**Where the next minutes are.**

1. **`api-edge` waits for a lane slot (~1.5m).** `cloudflare-worker-turbo 6/8
   · api-edge, billing-worker, config-worker` runs two at a time on a 2-CPU
   runner (`concurrency auto → 2`); billing and config held both slots for
   1m34s, then `api-edge` deployed in 48s. It is the last URL, and the
   console's smoke waits for it, so starting it first or alone moves both
   "URLs live" and the end of the convergence.
2. **01-product waits for its PR's CI (1m29s from open to merge).** Its
   `orun.pr/land@v1` has no `wait: false` (07's does); 54s of that wait was
   the PR's `plan` job queueing for a runner. v21's 02/04/05 landed the same
   pinned content without waiting.
3. **The convergence's `plan` job took 57s**, against 16s for the PR's.

### Against earlier runs

| | v13 (10-12) | v17 (10-14) | v19 (10-14) | v20 (10-14, partial) | v21 (10-14) | **v22 (this run)** |
|---|---|---|---|---|---|---|
| 01 | ~1m | 1m05s | 0m42s | 1m04s | 0m40s | **8m23s** (01-product) |
| 02 | ~4.3m | 3m51s | 3m54s | 3m08s | 3m12s | in 01-product |
| 04 | ~8.5m | 11m20s (one rerun) | 14m01s (one resume) | 5m50s | 4m34s | in 01-product |
| 05 | ~9m | 10m04s | 13m37s (one resume) | failed, see below | 4m29s | in 01-product |
| 01–05, the product | ~23m | 26m20s | 32m14s | — | 12m55s | **8m23s** |
| 08 | ~3m | ~1m | 0m48s | not reached | 1m07s | **0m57s** |
| URLs live | ~23m | 27m05s | 27m35s | — | 11m58s | **7m55s** |
| total | ~26m | 28m25s | 33m29s | — | 14m51s | **10m02s** |

**What moved the minutes, v21 → v22:**

1. **One landing (#27).** 01-scaffold, 02-foundation, 04-workers and 05-edge
   are one `01-product` phase: one prep, one PR, one merge and one
   convergence instead of four of each, and the fleet deploys once instead
   of twice.
2. **Placeholders instead of a second deploy.** v21 deployed the twelve
   workers without their bindings (04, `cycle-break --strip`) and again with
   them (05). In v22 policy-worker's pre-deploy
   (`tooling/deploy/fleet-stubs.mjs`) uploads a placeholder for every
   binding target that does not exist yet, and every binding holder waits on
   policy-worker (an enforced edge on main), so each worker deploys once,
   with its full bindings, and replaces its own placeholder.
3. **The data plane in the same convergence.** Every component with a
   `WIRING_*` secret waits on `cloudflare-d1`/`cloudflare-kv` (enforced on
   main), so D1 and KV no longer need a landing of their own.

**What moved the minutes, v17 → v21:**

1. **Lane packing (v20).** `maxLanes: 6` had left each environment one lane,
   so stage's 13 deploys ran in rounds of six in a single runner (7.3m).
   `maxLanes: 18` / `concurrency: auto` gives 04 and 05 nine lanes per
   environment, two or three workers each; `max-parallel: 19` in `ci.yml`
   keeps the fleet one under GitHub's free-plan limit of 20 concurrent jobs.
2. **No PR-check wait (v20).** `orun.pr/land@v1` lands with `wait: false` on
   02/04/05/07 — the content is the pinned baseline's and was verified there;
   the convergence watch is the gate. Each landing shed ~20s.
3. **No resumes (v20, platform).** The broker's mint lock serialised ~40
   concurrent `CLOUDFLARE_API_TOKEN` mints into a 20s waiter budget and
   failed a lane in most phases (`mint_lock_timeout`, 2–4m per resume).
   orun-cloud#1902 takes the lock only for parents that rotate. The
   Cloudflare first-deploy race (`code: 10007`) is retried in the
   composition (stack-tectonic 0.19.0), the console smoke race since 0.18.2.
4. **One install per lane (v21).** Worker and console installs are
   `scope: lane` at the workspace root (stack-tectonic 0.20.0, orun 2.78.4
   for the planner and runner fixes), so a three-worker lane installs once.
5. **No dev lanes during the bootstrap (v21).** `dev-lanes.mjs --defer` in
   01 removes dev's `github-push-main` trigger and 08 restores it; 02/04/05
   plan stage and prod only — 20/26/24 jobs instead of 33/48/38.
6. **The console no longer waits for `api-edge` (v21).** `dependsOn` is gone
   from `web-console-next`; its smoke retry covers the first request.

**The cap this run fitted under.** A brokered mint is per job, two or three
per deploy job, so a bootstrap is ~160 of them against
`limit.credential_mints_per_day` = 200 per workspace (rolling 24h). v20's
05 failed every lane with `broker: limit_reached` because it followed v19
in the same workspace. Until orun-cloud#1905 (cap 5000) is deployed and
existing rows are backfilled, give each bootstrap a fresh workspace.

### What it took to get a clean run (2026-10-14)

| run | baseline | stopped at | cause | fixed by |
|---|---|---|---|---|
| `pullely/cirrus-timing-1` | v15 | 01 | `orun.repo/ensure` calls `/orgs/<owner>/repos`, which 404s for a personal account | pre-creating the repo; orun fix in progress |
| `pullely/cirrus-timing-1` | v15 | 02 | every secret ref kept the baseline's workspace: `Ref workspace "ws_KWQ45Z6M" does not name this run's workspace` | #17 (rebrand matches a `ws_…` segment) → v16 |
| `pullely/cirrus-timing-2` | v16 | 04 | Cloudflare account at its 500-Worker limit (`code: 10037`); also `broker: mint_lock_timeout` on concurrent token mints | account cleaned up (344 Workers deleted) |
| `sourceplane/cirrus-timing-3` | v17 | 01 | built into the baseline's own workspace: the `orun-workspace` hook read "unchanged" as "no workspace line" | #20; this run used another workspace |
| `pullely/test-cirrus-12` | v18 | 05 | `pnpm install --lockfile-only` killed (OOM) on the platform box | #23 seeds the baseline's lockfile per phase → v19 |
| `pullely/cirrus-timing-5` | v20 | 05 | second bootstrap in one workspace within 24h: `broker: limit_reached` at 200 mints | fresh workspace; orun-cloud#1905 raises the cap |

## Things that shape the total

1. **One convergence per landing.** The convergence on main, watched by the
   `orun.run/watch@v1` await hook, is the gate: the phase content comes from
   the PINNED baseline and was verified there, and a pull request deploys
   nothing. 07-domain lands with `wait: false`; 01-product and 08-docs still
   wait for their PR's `plan` run (1m29s and 39s in the v22 run). Waiting on
   checks remains right for incremental changes on a live product, which is
   what a normal PR does.
2. **Watch GitHub Actions billing.** A full bootstrap is hundreds of runner
   minutes. A tripped spending limit presents as lanes that "fail" with NO
   logs anywhere — the message lives only in the check-run ANNOTATIONS
   (`gh api repos/<o>/<r>/check-runs/<job-id>/annotations`).
3. **Mint `ORUN_TOKEN` per phase** — it is short-lived (~30m). The container
   contract in BOOTSTRAP.md §2 covers this.
4. **A converge that follows a commit touching NO components** plans zero
   lanes and reads "green". The phase's verify step is the real gate; never
   trust a green run without it.

## Inherited defect log

These were found and fixed during Lumen's measured bootstraps. They are
listed so nobody re-hits them — every one is already landed in the shared
flow scripts this baseline carries.

| fix | what broke on a fresh product |
|---|---|
| #50 | `secret://` refs: segment 1 is the WORKSPACE — the repo-slug rebrand rewrote both segments; every resolve failed `Validation failed` |
| #52 | `cloud check` passes without the LOCAL link cache (fresh HOME) — preflight now links unconditionally |
| #53 | the workspace-slug self-heal dirtied the tree before its own clean-tree check |
| #54 | later phases branded fresh baseline content with the product's scaffold-era rebrand copy — the tool now always runs from the pinned baseline |
| #56/#57 | phase 03's PR lanes are structurally red on first boot → `--no-wait` landing |

And what the workspace-scoped (`sk_`) token path surfaced, all fixed:

1. `sk_` tokens see NO memberships list → slug resolution needs
   `orun workspace <ws>` (v2.52.1) — the direct org read.
2. `sk_` tokens cannot write repo links → the intent must declare
   `project:` (the scaffold writes it; preflight self-heals).
3. Intent declares the project SLUG; config-surface and state routes take
   `prj_…` ids → CLI-side slug resolution (v2.52.2 secrets, v2.52.4 run).
   The lane pin in `ci.yml` must be ≥ v2.56.2 (the phase overlay's floor was
   v2.56.0; v2.56.2 is where a branded tree stopped refusing its next phase).
4. Step `timeout:` didn't kill grandchildren — a wedged git held the step's
   pipes past its deadline → process-group kill + WaitDelay (orun v2.52.3).
5. git has NO transfer timeout → `http.lowSpeedLimit/Time` on every flow git.
6. git's credential `store` fires EVERY configured helper (system
   osxkeychain included) → in a keychain-less HOME securityd can raise a
   BLOCKING dialog on the console user's screen, hanging the step until a
   human clicks. Get-only credential helper everywhere.
