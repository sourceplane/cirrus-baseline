# Bootstrap timings — what to budget, and where the numbers come from

**Measured.** The numbers below are one bootstrap of `baseline-v17` on
2026-10-14: `pullely/cirrus-timing-3`, built with `orun baseline new
cirrus-baseline --local --run-hooks` (orun 2.77.1) from a laptop into
workspace `cirrus-v15-test` (`ws_KCR13BW3`), GitHub-hosted runners, lanes
`auto` at `maxLanes: 6`, `concurrency: 6`, and the console deployed from the
prebuilt artifact (saas-console-artifact CA5). One run is a measurement, not a
distribution; replace it when a better one exists.

## Per-phase (baseline-v17)

Phase time is the engine's own `done` narration. Prep is the phase's first
narration line to its PR being opened (local render, rebrand, install, commit,
push). PR CI is the landing PR's run (`plan` only, by design). Main is the
`push: main` convergence, merge to `updated`. Lanes are GitHub lane jobs; orun
jobs are the jobs those lanes ran (one check run each).

| phase | time | prep | PR CI | merge → main start | main run | lanes / orun jobs | main attempts |
|---|---|---|---|---|---|---|---|
| 01 scaffold | **1m05s** | 0.4m | 0.3m | 3s | 0.5m | 0 / 0 (plan only) | 1 |
| 02 foundation | **3m51s** | 0.3m | 0.3m | 4s | 2.7m | 6 / 33 | 1 |
| 04 workers | **11m20s** | 0.4m | 0.3m | 3s | 10.1m | 6 / 48 | **2** |
| 05 edge | **10m04s** | 0.4m | 0.3m | 3s | 8.7m | 6 / 35 (+3 skipped) | 1 |
| 07 domain | not run | | | | | | |
| 08 docs | **~1m** | 0.3m | 0.3m | 3s | 0.7m | 0 / 0 (plan only) | 1 |

| | wall-clock (from the first command, 09:42:49Z) |
|---|---|
| stage `api-edge` `/health` first 200 | 22m25s |
| stage console first 200 | 24m42s |
| prod `api-edge` `/health` first 200 | 25m16s |
| **URLs live** (prod console, the last of the four) | **27m05s** |
| **full bootstrap** (exit 0) | **28m25s** |

Run ids, all on `pullely/cirrus-timing-3`: 05 main run 38546597137, 04 main
run 38545219854. The stamped build log, the URL probe log and the per-run
job lists are what these come from.

### Against earlier runs

| | v13 (2026-10-12) | v16 (2026-10-14, partial) | **v17 (this run)** | expected for v17 |
|---|---|---|---|---|
| 01 | ~1m | 1m03s | 1m05s | |
| 02 | ~4.3m | 3m32s | 3m51s | |
| 04 | ~8.5m | failed (see below) | 11m20s (one rerun) | |
| 05 | ~9m | not reached | 10m04s | |
| 08 | ~3m | not reached | ~1m | |
| URLs live | ~23m | — | **27m05s** | ~18m |
| total | ~26m | — | **28m25s** | ~21m |

**The prebuilt console works, and the console stopped being the critical
path.** Both console deploys logged
`✓ prebuilt console web-console-next-8c0e95682a85f12a2a0f7749614cd3d4.tar.gz
(sha256:48d5c051…); no build`; the build step took 0.6s and each console job
1m13s–1m22s end to end. The product's `console-artifact.pin.json` names that
tarball. Both consoles answer as "cirrus-timing-3 Console", stage with
`deployEnv: stage` and prod with `deployEnv: prod`, each calling only
`cirrus-timing-3-api-edge-<env>`.

**Why the total did not fall to ~21m:**

1. **04 paid one rerun (~2m).** Attempt 1 (8.1m) failed one job,
   `admin-worker · prod`, on a Cloudflare first-deploy race —
   `This Worker does not exist on your account. [code: 10007]` on
   `cirrus-timing-3-admin-worker-prod`. The watch hook's resume passed it in
   2.0m. A clean 04 is ~8.1m.
2. **04's stage fleet runs in ONE lane.** `maxLanes: 6` across three
   environments leaves stage with `auto 1/1` — 13 jobs at concurrency 6 in a
   single runner, the slowest single job of the run (7.3m).
3. **05's critical path is now `api-edge`, serialised stage → prod.**
   `api-edge · stage` ran 10:02:16→10:05:50 (3.5m), `api-edge · prod` only
   started after it, 10:05:59→10:08:21, although promotion is deferred during
   a bootstrap; each console waits on its environment's `api-edge`
   (component `dependsOn`), so prod's console went live at 10:09:54. Removing
   the console build shortened the console job, not the path.

So the next minutes are in 04's lane split (give stage more than one lane)
and in why prod's `api-edge` waits for stage's.

### What it took to get a clean run (2026-10-14)

| run | baseline | stopped at | cause | fixed by |
|---|---|---|---|---|
| `pullely/cirrus-timing-1` | v15 | 01 | `orun.repo/ensure` calls `/orgs/<owner>/repos`, which 404s for a personal account | pre-creating the repo; orun fix in progress |
| `pullely/cirrus-timing-1` | v15 | 02 | every secret ref kept the baseline's workspace: `Ref workspace "ws_KWQ45Z6M" does not name this run's workspace` | #17 (rebrand matches a `ws_…` segment) → v16 |
| `pullely/cirrus-timing-2` | v16 | 04 | Cloudflare account at its 500-Worker limit (`code: 10037`); also `broker: mint_lock_timeout` on concurrent token mints | account cleaned up (344 Workers deleted) |
| `sourceplane/cirrus-timing-3` | v17 | 01 | built into the baseline's own workspace: the `orun-workspace` hook read "unchanged" as "no workspace line" | #20; this run used another workspace |

## Things that shape the total

1. **One convergence per landing.** A phase's `orun.pr/land@v1` merges
   without waiting on PR checks: the phase content comes from the PINNED
   baseline and was verified there, so PR lanes would deploy the fleet a
   second time. The `orun.run/watch@v1` await hook is the gate. Waiting on
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
