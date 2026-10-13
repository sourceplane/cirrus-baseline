# saas-baseline-tracking — Implementation Plan

Status: Normative for the BT cluster's cirrus leg and the umbrella order.
As-built record in `IMPLEMENTATION-STATUS.md` (created when BT1 lands);
decisions and human gates in `risks-and-open-questions.md`. Three repos:
**BT0** (orun-cloud, shipped) → **BT-O1–BT-O4** (orun,
`specs/orun-baseline-tracking/implementation-plan.md`) → **BT1–BT6** (here).
Each milestone is independently landable; the dependency edges are named
per milestone.

Two invariants hold across the whole cluster:

- **Tracking never blocks a landing.** Every tracking call is guarded; a
  failure prints one actionable line and the phase proceeds untracked
  (today's branch names). The flows' existing contract — idempotent,
  self-healing, `succeeded` on the last line — is unchanged.
- **Product-only content stays product-only.** No tracking state is written
  into the product repo. Identity is looked up from the plane (slug, name,
  title); the run's working dir (`$W/tracking.json`) may cache it.

## BT0 — The MCP writes (orun-cloud) ✅

**Scope** (shipped in orun-cloud `packages/mcp`):

- `epic_create` — name, `slug`, `description`, `targetDate`, `owner`
  (`me`). A taken slug returns the existing epic with `existed: true`.
- `milestone_create` — `epic`, `name`, `targetDate`, `exitCriteria[]`,
  `after` (`mls_…` | `null` = first | omitted = last).
- `task_create` widened — `epic`, `milestone`, `brief`, `assignee`, and an
  optional `contract` (`goal`, `affects[]`, `doneWhen[]`, `gates[]`,
  `designRefs`, `deps`, `secrets`, `envs`) attached under the same
  idempotency attempt with `gatesDefined: true`.
- Roster 31 → 33; `tool-manifest.json` regenerated; budget/conformance
  pins moved; CLI README roster note updated.

**Done when** `pnpm --filter @saas/mcp test` and `@saas/mcp-tests` are
green (they are). Serving the new manifest from the binary the sandbox
runs is orun's **BT-O3**, not this milestone's.

## BT1 — `flows/common/track.sh` (needs orun BT-O1 + BT-O2)

**Scope**

- A script in the `ghrest.sh` style, but with one client: `orun`. Every
  subcommand shells to `orun task …` with `--json` and parses with
  `python3` (never `jq`); the workspace is `$ws` (set by `ctx.sh`) via
  `--workspace`; the credential is whatever the CLI already resolves
  (`ORUN_TOKEN`, `ORUN_TOKEN_FILE`, or the login session) — nothing is read
  or exported here. Idempotency keys ride the CLI's own (`mcp_`-style
  auto keys are the binary's; a retried *step* re-runs the find half first,
  so a replay never reaches a second create).
- Subcommands, each printing ONE line to stdout (the id/key) and prose to
  stderr:

  | command | does | idempotent by |
  |---|---|---|
  | `ensure-epic <slug> <name> [description]` | `orun task epic create --slug … --name … --json`; a taken slug is adopted (the CLI prints `reusing`) | slug |
  | `ensure-milestone <epic> <name> <exit-criteria…>` | `orun task epic show <epic> --json` → match `milestones[].name`; else `orun task milestone create --epic … --name … --after <previous phase's mls_…>` (`--first` for `01`) | name within epic |
  | `ensure-task <epic> <milestone> <title> <contract-file>` | `orun task list --epic <epic> --json` → match `titleMirror`; else `orun task create --prefix BASE --title … --brief … --epic … --milestone … --assignee me --contract <file> --json`; prints the KEY | title within epic |
  | `rollup <epic>` | `orun task epic show <epic> --json` → `N/M done`, per-milestone rungs — the line the agent posts | — |
  | `verdict <key>` | `orun task show <key> --json` → `rung — reason` | — |

- Contract templates live in the baseline, one per landing:
  `flows/phases/NN-*/task-contract.yaml` (`goal`, `affects` = the phase's
  blueprint components, `doneWhen` = the milestone's exit criteria,
  `gates: []`, `gatesDefined: true`). The scaffold phase's blueprint split
  (`tooling/blueprint/split-phases.py`) does not touch them; they are
  flow machinery, never product content.
- Degradation: a non-zero `orun` exit other than the adopt path, or a
  binary older than the BT-O1/O2 release (`orun task epic --help` fails),
  prints `track: <what> unavailable (<reason>) — landing untracked; upgrade
  orun to ≥ <release> / grant task.write to the run's principal` to stderr
  and exits 0 with an empty stdout. Callers treat empty as "no key".
- `$W/tracking.json` cache `{epic, milestones:{"01":"mls_…"}, tasks:{"<title>":"BASE-3"}, refused: null|"<reason>"}`
  written after each ensure; read first, re-verified against the plane
  only when the cached ref 404s.

**Done when** `bash -n` clean; a contract test under `flows/testing/` with
a fake `orun` on `PATH` (a shell script answering the five subcommands
from fixtures) shows: first run creates epic + milestone + task and prints
`BASE-1`; second run creates nothing and prints the same key; an old
binary prints the refusal and an empty line.

## BT2 — `land-pr.sh` / `push-main.sh` land through the pen (needs orun BT-O4)

**Scope**

- `land-pr.sh [--no-wait] [--task KEY] [--epic SLUG] <out> <suffix> <title> [body]`
  (also honours `ORUN_TASK_KEY` / `ORUN_EPIC_SLUG` from the environment).
  With a key: after the commit, `orun pr open --task "$KEY" --branch-slug
  "$suffix" --epic "$epic" --title "$title" --body-file - --json` replaces
  the `git checkout -qb` / `git push` / `ghr_pr_create` trio: the pen
  checks out `orun/<KEY>-<suffix>`, pushes, renders `Task: <KEY>` and the
  manifest block into the body, opens the PR and returns its `number`.
  The merge, the checks wait and the return to `main` stay exactly as
  today, on that number. Best-effort
  `ghr_pr_label <n> orun:task/<KEY>` after open (needs `issues: write`;
  failure is silent — the branch already binds).
- Without a key: today's `phase/<suffix>-<epoch>` path, byte-identical.
- The pen's refusal (no `pull_requests` grant: it pushes and returns the
  compare URL) maps onto today's direct-merge fallback: the `orun/…`
  branch is already pushed (so `branch_seen` is recorded), and the merge
  commit's message carries the `Task:` trailer so the lineage survives in
  git even when the plane saw no PR.
- `push-main.sh <suffix> <title> [body]` (phase 08) gains the same
  `--task` / `--epic` handling on its PR path; its direct-push path is
  unchanged (a PR-less push cannot bind and should not pretend to).
- `ghrest.sh`: one new function `ghr_pr_label PR_NUMBER LABEL`.

**Done when** a landing with `ORUN_TASK_KEY=BASE-3` opens a PR from
`orun/BASE-3-03-infrastructure` whose body has the trailer and manifest
(`orun pr check` passes on the branch), and a landing without a key is
diff-identical to today's (checked by the existing dry-run path plus a
`git log` assertion in the BT6 rehearsal).

## BT3 — The phases ensure their task, the umbrella ensures the programme

**Scope**

- `flows/phases/00-all/workflow.yaml`: new inputs `track` (default
  `"true"`) and `epicslug` (default `infra-baselining`); a new first step
  `programme` (before `scaffold`) that runs `track.sh ensure-epic` with
  name `Infra baselining — <productname>` and description naming the repo
  and the baseline ref, then `ensure-milestone` for phases 01–06 and 08 in
  order (07 only when `domain` is set), exit criteria from the table in
  `flows/phases/README.md`. Passes `--set track= --set epicslug=` to every
  phase.
- Every `flows/phases/NN-*/workflow.yaml`: inputs `track` + `epicslug`;
  the `land` step, before calling `land-pr.sh`, runs
  `key="$("$L/flows/common/track.sh" ensure-task "$epic" "NN — <phase>" "<title>" "<goal>" "<affects>" "<done-when>")"`
  (which ensures the milestone too, so a phase run on its own still
  tracks) and calls `land-pr.sh --task "$key" …`. Phase 04 does this
  twice (two titles, two tasks, one milestone). `dryrun=true` prints what
  it would ensure and touches nothing.
- `apply-blueprint.sh` is untouched; the contract's `affects` list is
  read from the phase's `blueprint.yaml` component names by `track.sh`'s
  caller (a two-line `python3` in the step, mirroring how `verify` reads
  values.json).
- The umbrella's `verify` step ends with `track.sh rollup <epic>` and
  fails if fewer than the expected tasks are `done` **only when**
  `track=true` and tracking was not refused (the refusal is recorded in
  `$W/tracking.json` as `refused: <reason>` so verify can tell "untracked
  by policy" from "tracked and not done").

**Done when** a phase re-run after success creates nothing (the `track:`
lines all say `reusing`), and `flows/phases/README.md` documents the two
inputs and the branch grammar in its "Shared machinery" table.

## BT4 — Phase 01 lands as a PR

**Scope**

- `flows/phases/01-scaffold/workflow.yaml` `repo` step: create the repo
  with an initial commit (`gh repo create … --add-readme`, or when the
  repo is pre-created and empty, push one commit containing a one-line
  `README.md` to `main`); pin `main` as default as today. Then the scaffold
  content is committed on `orun/BASE-1-01-scaffold` and landed with
  `land-pr.sh --no-wait --task BASE-1` (no checks exist yet, so no gate to
  wait on; the README stub is overwritten by the scaffold's own README).
- The deferred-`.github/workflows` fallback (token lacks the Workflows
  grant) stays: the PR lands without them, and the existing follow-up
  push carries the same task key in its commit trailer.
- `flows/AGENT-PROMPT.md` and `BASELINE-TASK.md` lose the sentence that
  says phase 01 lands directly on main.

**Done when** a fresh bootstrap's first PR is `#1` from
`orun/BASE-1-01-scaffold`, `BASE-1` folds to `done` on its merge, and the
scaffold's post-merge tree is byte-identical to today's direct push
(verified by `git diff` between a BT4 and a pre-BT4 rehearsal).

## BT5 — The agent lays out the programme and reports from it

**Scope** — `flows/agent/BASELINE-TASK.md` (and the operator-facing
`flows/AGENT-PROMPT.md` in step form):

- New **Step 1b — the programme**, after intake: with the MCP roster
  (`epic_create` → `milestone_create` ×7 → nothing else; tasks are the
  flows' to mint at landing time so a key is never assigned to work that
  did not happen). Slug `infra-baselining`, exit criteria copied from the
  brief's own phase table. If the tools are absent (older `orun`), skip
  the step: the umbrella's `programme` step creates the same objects.
- **Step 3 — updates** become the rollup: `task_get infra-baselining` (or
  `track.sh rollup`) every phase boundary and every 10 minutes; the update
  line is `<N>/<M> phases done · <running phase>: <rung> — <evidence>`.
- **Step 5 — completion** adds the epic link
  (`/<account>/<workspace>/work/epics/infra-baselining`) and the per-task
  keys beside the per-phase durations, and asks the operator to keep the
  epic (it is the bootstrap's audit trail) rather than archive it.
- The umbrella command in the brief gains `--set track=true` explicitly so
  a future default flip cannot silently untrack an agent-run bootstrap.
- **The manifest rides the epic.** After phase 08, the brief runs
  `orun spec push --epic infra-baselining ai/context/deployment.md
  ai/context/operations.md` from the product checkout (committed files,
  idempotent by content hash), so the epic carries the deployment record
  beside its tasks and `task_get infra-baselining` answers with it.

**Done when** a sandbox bootstrap's transcript shows the epic created
before the umbrella starts, every progress update quotes the rollup, and
the completion report names eight `done` tasks.

## BT6 — Verification

**Scope**

- `flows/testing/track-stub.py` + `flows/testing/track.test.sh`: the
  BT1 contract test, runnable locally and in this repo's CI (`bash`,
  `python3` only).
- One rehearsal bootstrap (the `nimbus`/`vela` precedent) with `track=true`
  recorded in `IMPLEMENTATION-STATUS.md`: the epic slug, the nine keys,
  each task's verdict evidence (`pr_merged` observation ids), the rollup
  line, and the wall-clock delta tracking added (expected: seconds — one
  `GET` and at most two `POST`s per landing).
- `flows/phases/TIMINGS.md` gains a "tracking overhead" row.

**Done when** the rehearsal's rollup reads `8/8 done` (9/9 with domain),
the CI test is green, and `IMPLEMENTATION-STATUS.md` records where the
build departed from this plan.
