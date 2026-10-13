# Implementation Status — saas-baseline-tracking (BT)

As-built record for the BT cluster across its three repos. Design intent is
in `implementation-plan.md` (and, for the binary, orun's
`specs/orun-baseline-tracking/`); trust code over this doc — re-derive from
`git`/PRs on boot.

## Summary

| ID | Repo | Status | Evidence / notes |
|----|------|--------|------------------|
| BT0 | orun-cloud | ✅ Shipped ([#1374](https://github.com/sourceplane/orun-cloud/pull/1374)) | `epic_create`, `milestone_create`, `task_create` widened (`epic`/`milestone`/`brief`/`assignee`/`contract` under `<key>:contract` with `gatesDefined: true`); roster 31 → 33; a taken slug answers `existed: true`. |
| BT-O1 | orun | ✅ Shipped ([#631](https://github.com/sourceplane/orun/pull/631)) | `orun task create --epic --milestone --brief --assignee --contract <template>` (the template read and validated BEFORE the allocator is asked); `task list --epic/--milestone/--assignee`; `taskfile.ParseTemplate`; doc page `orun-task.md`. |
| BT-O2 | orun | ✅ Shipped ([#632](https://github.com/sourceplane/orun/pull/632)) | `orun task epic create\|show\|list`, `orun task milestone create` (`--after` / `--first`, `--exit-criteria`); a taken slug prints `reusing it`, exit 0; `remotestate/epics.go`. |
| BT-O4 | orun | ✅ Shipped ([#633](https://github.com/sourceplane/orun/pull/633)) | `orun pr open --branch-slug --epic --body-file`, `number` in `--json`; grammar untouched; doc page `orun-pr.md`. |
| BT-O3 | orun | ✅ Shipped ([#634](https://github.com/sourceplane/orun/pull/634)) | Manifest re-vendored at 33 (CHECKSUM + embed); the six task-plane tools native in `internal/platformmcp/tasks.go`; `PlatformAPI` compile-checked against the client; pins 27/21 → 33/24; `orun-mcp.md` gains the task plane. |
| BT1 | cirrus | ✅ Shipped ([#23](https://github.com/sourceplane/cirrus/pull/23)) | `flows/common/track.sh` (ensure-epic / ensure-milestone / ensure-task / rollup / verdict over `orun task …`, idempotent by identity, degrades loudly); `flows/phases/NN-*/task-contract.yaml` (phase 04: two); `flows/testing/fake-orun` + `track.test.sh`. |
| BT2 | cirrus | ✅ Shipped ([#30](https://github.com/sourceplane/cirrus/pull/30)) | `land-pr.sh --task/--epic` through `orun pr open` (grammar branch, `Orun-Task` trailer, `Task:` + manifest in the body, label best-effort); `push-main.sh --task`; `ghr_pr_label`; `land-pr.test.sh`. |
| BT3 | cirrus | ✅ Shipped ([#31](https://github.com/sourceplane/cirrus/pull/31)) | Phases 02–08: `track` / `epicslug` inputs, `ensure-task` before every landing, `--task` on every landing; the umbrella's `programme` step and the rollup at the end of `verify`. |
| BT4 | cirrus | ✅ Shipped ([#32](https://github.com/sourceplane/cirrus/pull/32)) | Phase 01 seeds `main` with one commit and lands the scaffold as PR #1 on `orun/BASE-n-01-scaffold`; the workflows-permission fallback re-lands without them. |
| BT5 | cirrus | ✅ Shipped ([#33](https://github.com/sourceplane/cirrus/pull/33)) | `BASELINE-TASK.md` Step 1b (lay out the programme over MCP, skip on an older binary), rollup-quoting updates, `--set track=true` explicit, `orun spec push` of the deployment manifest onto the epic, the epic in the completion report; `AGENT-PROMPT.md` in step form. |
| BT6 | cirrus | 🛠️ Partial ([#34](https://github.com/sourceplane/cirrus/pull/34)) | `tests/flows` quick-check component runs both contract tests in this repo's CI (never ships: no phase blueprint lists it). **The live rehearsal bootstrap is not done** — it needs an orun release carrying BT-O1/O2/O4, a workspace with the two integrations, and an admin key; see the human gates. |

## Departures from the plan

- **`push-main.sh --task` always takes the pen.** The plan said its
  direct-push path stays unchanged; as built, a *tracked* landing never
  takes a direct push (the platform cannot bind one), so the docs phase
  lands as a PR like every other. Untracked, the direct push is unchanged.
- **The tracking cache lives in `${XDG_CACHE_HOME:-~/.cache}/orun-bootstrap/<workspace>/`**,
  not the run's workdir: in local mode the workdir is the baseline
  checkout, and a cache file there would dirty it. It is a cache only —
  identity lookups on the plane are the source of truth.
- **`ensure-milestone` takes a phase dir, not a name.** The milestone
  name and exit criteria derive from a table in `track.sh` (the "verified
  by" column as data), so callers say `03-infrastructure` and nothing else.
- **The contract test for BT2 exists** (the plan deferred it to the BT6
  rehearsal): `land-pr.test.sh` drives `land-pr.sh` end to end over a
  fake pen and a fake `gh` with bare-repo remotes.
- **No REST leg.** Decision 4 held: the flows have one client, `orun`;
  an older binary lands untracked and says so.

## Human gates still open

- **The orun release and the flows' floor.** BT-O1–O4 are merged on
  orun `main` but not yet in a tagged release; `BOOTSTRAP.md`,
  `flows/AGENT-PROMPT.md` and `BASELINE-TASK.md` still pin `≥ v2.52.6`.
  Until the floor moves, a bootstrap on a released binary runs untracked
  (every landing says so once) — the pre-BT behaviour, byte-identical.
- **The bootstrapper's tool policy.** Whether `task_create` /
  `epic_create` / `milestone_create` join the allow lane of the
  `bootstrapper` agent type is a profile decision in orun-cloud
  (`bootstrap-profile.ts`'s capability). Until then the brief's Step 1b
  skips itself and the umbrella's `programme` step does the same work.
- **The rehearsal.** One real bootstrap with `track=true` whose epic
  rollup reads `8/8 done`, recorded here with the task keys, the
  observation ids, and the tracking overhead (expected: seconds).

## Agent brief v2 — one command, four kinds of line

Three live bootstraps showed the brief itself causing the mistakes: told
about a token endpoint the agent read and printed the token file; told to
"install gh if missing" it installed an npm package of that name; told to
pick the CI watch mode it reasoned about App grants; and every run spent
8–28 tool calls "checking the environment" before the build. The brief is
now 65 lines: ask three questions, run `flows/agent/workflow.yaml` with the
three values, relay `UPDATE:` / `ACTION REQUIRED:` / `FAILED:` / `DONE`
lines, post the summary. `flows/agent/build.sh` reads the workspace,
repository, checkout and credentials from the environment the platform
prepared, checks the binary floor, installs `gh` only if absent, runs the
umbrella with tracking on, and composes the summary. The umbrella's `watch`
defaults to `auto` (CI on main → watch; no workflow files → one
`ACTION REQUIRED` naming the App's Workflows grant, never agent-driven
deploys), every phase completion prints `umbrella: ✓ <phase> complete`, and
`verify` attaches the deployment record to the epic. Contract test:
`flows/testing/agent-build.test.sh` (in the `flows-tests` lane).
