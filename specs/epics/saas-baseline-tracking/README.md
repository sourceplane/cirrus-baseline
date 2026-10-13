# Epic: saas-baseline-tracking (BT) — the cross-repo umbrella

**The bootstrap is work, so it lives where work lives.** Today the baseline
builder takes a workspace from an empty repo to a live, documented product
and leaves no trace of that programme in the workspace's own work surface:
no epic, no phases, no tasks, and seven PRs on `phase/<n>-<epoch>` branches
that bind to nothing. BT makes the bootstrap author itself into the task
plane — one epic ("Infra baselining"), one milestone per phase, one task
per landing — and names every landing's branch `orun/<KEY>-<phase>` so the
platform's own observation drain turns each push, PR and merge into the
task's evidence. Nothing is asserted; the ledger reads what the flows did.

## Status

| Field | Value |
|-------|-------|
| Status | **In progress** — BT0 (orun-cloud), BT-O1–BT-O4 (orun) and BT1–BT5 (here) ✅ shipped; BT6 partial (CI contract tests in; the live rehearsal is a human gate). As-built: [`IMPLEMENTATION-STATUS.md`](./IMPLEMENTATION-STATUS.md) |
| Cluster | **BT** — three repos, one cluster: **BT0** orun-cloud · **BT-O1–BT-O4** orun (`specs/orun-baseline-tracking/`) · **BT1–BT6** cirrus (this folder) |
| Owner(s) | here: `flows/common/` (a new `track.sh`, `land-pr.sh`, `push-main.sh`), every `flows/phases/*/workflow.yaml`, `flows/phases/00-all`, `flows/agent/BASELINE-TASK.md`, `flows/AGENT-PROMPT.md` · orun-cloud: `packages/mcp/src/tools/tasks.ts` (BT0, shipped) · orun: `cmd/orun/tasks.go`, `cmd/orun/pr.go`, `internal/remotestate`, `internal/platformmcp` + the vendored manifest |
| Target branch | `main` |
| Builds on | orun-cloud `orun-tasks` (the task plane: epics E1–E5, milestones TV2/W2, the `orun/<key>-<slug>` provenance grammar TK-2, the observation drain, the derived verdict TK-M) · orun-cloud `saas-baseline-registry` (the bootstrap door that runs this baseline's brief) · orun v2.54.0's provenance pen (`orun pr open`) and `orun task create/attach/list/show` · orun `orun-mcp` (the one `orun mcp serve` the sandbox mounts) · `flows/phases` (the eight phases and their shared machinery) |
| End-state target | A bootstrap, run by the sandbox agent or headless from CI, shows up in the workspace as epic `infra-baselining` with eight phases and eight-plus tasks; every landing PR is on an `orun/BASE-n-<phase>` branch and carries the provenance manifest; each task folds `in_progress → in_review → done` from observed evidence alone, and the epic rollup is the progress report the agent posts |

## Thesis

Three facts, all already true in orun-cloud, make this cheap:

1. **The plane binds by branch name.** `PROVENANCE_BRANCH_RE` is
   `^orun/([A-Z][A-Z0-9]{1,5}-[A-Z]?[0-9]+)(?:-([a-z0-9-]+))?$`
   (`packages/db/src/provenance/index.ts`). The tasks-worker drains the
   normalized `scm.push` / `scm.pull_request.*` stream and, for any branch
   that parses, records `branch_seen` / `pr_opened` / `pr_merged` on the
   task with that key. Two more channels agree with it — a `Task: <KEY>`
   trailer in the PR body and an `orun:task/<KEY>` label — and disagreement
   binds nothing. Our landing branch just has to be spelled right.
2. **The verdict is derived, never typed.** `branch_seen → in_progress`,
   an open PR `→ in_review`, a merged PR `→ done` **only if the task's
   contract declared its gates** (an explicit empty gate list means "merge
   alone finishes it"; undeclared gates park the merge at `in_review`,
   forever). So every bootstrap task must be born with a contract. There is
   no status write to make, and none we could make: the status command
   exists only for tracker-linked tasks.
3. **The containers are native objects.** `POST …/tasks/epics`,
   `POST …/tasks/epics/{ref}/milestones` (a milestone *is* a phase in the
   plane's own vocabulary — ordered by `after`, carrying `exitCriteria`),
   and `POST …/tasks` with `epic` / `milestone` / `brief` / `assignee`
   resolved before the key is minted. The MCP roster lacked the two
   container writes and the widened create; **BT0 added them** (orun-cloud:
   `epic_create`, `milestone_create`, `task_create` with
   `epic|milestone|brief|assignee|contract`).

What is missing sits in two repos. **Here:** the flows never talk to the
task plane, `land-pr.sh` names branches `phase/<suffix>-<epoch>`, phase 01
pushes its first commit straight to `main` (no PR, so no evidence), and the
agent brief has no step that creates or reads the programme. **In the orun
binary** — the flows' one platform client and the sandbox agent's MCP:
`orun task create` cannot name an epic, a milestone, a brief or a contract
(`remotestate.TaskCreateRequest` carries four of the plane's nine fields),
nothing creates an epic or a milestone from the CLI, and `orun mcp serve`
embeds a vendored manifest of **27** tools — the plane is at 33 — so the
sandbox agent has no task tools at all. The pen is already right:
`orun pr open --task KEY` checks out `orun/<KEY>-<slug>`, pushes, and opens
the PR with the `Task:` trailer and the manifest block.

## The shape

```
epic     infra-baselining            "Infra baselining — <Product name>"   owner: the bootstrap principal (`me`)
  ├─ milestone  01-scaffold          exit: repo created + linked, scaffold merged, main default
  │    └─ task BASE-1  Scaffold the product repository            branch orun/BASE-1-01-scaffold
  ├─ milestone  02-foundation        exit: verify lanes green
  │    └─ task BASE-2  Publish the shared packages                branch orun/BASE-2-02-foundation
  ├─ milestone  03-infrastructure    exit: WIRING_* secrets published on stage+prod
  │    └─ task BASE-3  Provision the D1 and KV data plane
  ├─ milestone  04-workers           exit: convergence green, bindings restored
  │    ├─ task BASE-4  Deploy the worker fleet                    orun/BASE-4-04-workers
  │    └─ task BASE-5  Restore the service-binding feedback edges orun/BASE-5-04-workers-restore
  ├─ milestone  05-edge              exit: /health 200 on stage+prod
  │    └─ task BASE-6  Deploy the API edge
  ├─ milestone  06-console           exit: console + edge live
  │    └─ task BASE-7  Deploy the web console
  ├─ milestone  07-domain            exit: domain component merged (its phase runs only when asked for)
  │    └─ task BASE-8  Bind the custom domain
  └─ milestone  08-docs              exit: committed manifest matches probed reality
       └─ task BASE-9  Record the live deployment                 orun/BASE-9-08-docs
```

All of it is opened by the blueprint's run-level `hooks.preInstantiate`
(orun ≥ v2.60) before the first phase places — the whole tree at once, in
this order — and each phase's own `pre` hook then finds its task by title to
bind the landing to it. A task title is an imperative sentence about the
outcome; the landing PR carries a conventional-commit title of its own
(`feat(workers): …`, `fix(workers): …`, `docs(deployment): …`).

- **One epic per bootstrap**, slug `infra-baselining` by default
  (`--set epicslug=` overrides). A taken slug is *adopted*, not suffixed:
  `POST …/tasks/epics` answers 409 with the holder, and the flow — like the
  MCP tool — takes that as "that one". Re-running a phase never makes a
  second epic.
- **One milestone per phase**, named `NN — <phase>` so it sorts and reads
  like the folder. Exit criteria are the phase's verify assertions, copied
  from `flows/phases/README.md`'s "verified by" column. Idempotent by name:
  the flow lists the epic's milestones (`GET …/tasks/epics/{ref}`) and
  creates only what is absent.
- **One task per landing**, i.e. per `land-pr.sh` / `push-main.sh` call —
  eight today, nine with phase 07. Keys are minted from the workspace
  sequence with `mintPrefix: BASE` (`BASE-1`, `BASE-2`, …; the prefix is
  ≤ 6 chars by the key grammar). The task's `titleMirror` is the landing's
  PR title verbatim (`phase(03-infrastructure): d1, kv, db-migrate`), which
  is what makes find-or-create idempotent: `GET …/tasks?epic=<slug>` and
  match on title. (Since baseline-v12 the title is the task's own imperative
  sentence rather than the PR title; the two are named side by side in the
  blueprint and the identity rule is unchanged.) Every task is born with a contract:
  `goal` = the phase README's one-liner, `affects` = the components in the
  phase's `blueprint.yaml`, `doneWhen` = the milestone's exit criteria,
  `gates: []` with `gatesDefined: true` — the merge's main run is the gate
  the flow *watches* (converge), not one the plane can observe as a PR
  check, so the task must be allowed to reach `done` on the merge. `brief`
  = the phase README's first paragraph. `assignee: me` (the run's own
  principal, so "My agents" shows the bootstrapper at work).
- **The branch is the binding.** `land-pr.sh` commits, then hands the
  landing to the pen: `orun pr open --task <KEY> --branch-slug <suffix>
  --epic <slug> --title … --json` checks out `orun/<KEY>-<suffix>` (the
  suffix is already `[a-z0-9-]`), pushes, and opens the PR with
  `Task: <KEY>` as the body's trailer and the provenance manifest block
  (`<!-- orun:manifest {"version":1,"task":"BASE-3","epic":"infra-baselining"} -->`)
  so `orun pr check` and the compliance evaluator read the same lineage.
  `land-pr.sh` keeps owning the merge and the convergence wait, and adds
  the `orun:task/<KEY>` label when the token can. Three channels, one key —
  they agree by construction.
- **Phase 01 becomes a landing.** An empty repo cannot take a PR, which is
  why the scaffold pushes to `main` directly today. BT4 creates the repo
  with an initial commit (`gh repo create --add-readme`, or an empty
  `README.md` commit when the repo was pre-created) and lands the scaffold
  as the first PR from `orun/BASE-1-01-scaffold`. `main` pinned as default,
  the workflow-scope caveat and the deferred-workflows fallback all carry
  over unchanged; the scaffold merely arrives by the same door as every
  later phase — and the epic is born *before* it, so the first thing the
  workspace sees is the plan, then the commits.
- **The flow is the writer; the agent reads (and may pre-write).** The
  phase workflows own creation over REST, so headless CI runs track
  themselves with nobody in the loop. The sandbox agent, which has the MCP
  roster, is told to lay out the epic and its phases *first* (BT0's three
  tools) so the console shows the programme in minute one, then run the
  umbrella — whose find-or-create adopts what the agent made. Progress
  updates in the brief become `task_get infra-baselining` (the rollup: N/M
  done, the running phase's rung and evidence) instead of prose.

## Decisions locked

1. **Derived, not asserted.** No flow ever writes a status. Done means the
   plane saw the merge; the contract's empty gate list is the one authored
   fact that lets it say so.
2. **Milestone = phase, task = landing.** Phases are the human unit and
   carry exit criteria; landings are what a PR binds to. Phase 04's two
   PRs are two tasks in one milestone, never one task with two branches.
3. **Idempotent by identity, not by memory.** Epic by slug, milestone by
   name-within-epic, task by title-within-epic. No tracking file is written
   into the product (product-only content stays product-only); the run's
   working dir may cache what it resolved.
4. **The binary is the path — CLI for the flows, MCP for the agent.** The
   flows already require `orun` and call it for every other platform
   fact; the task plane is reached through `orun task …` and the PR
   through `orun pr open`, with the same ambient credential
   (`ORUN_TOKEN` / `ORUN_TOKEN_FILE`) the CLI already honours. No curl, no
   second client: the floor in `BOOTSTRAP.md` moves to the release that
   carries orun's BT-O1/O2/O4.
5. **Tracking never blocks a landing.** If the task plane is unreachable
   or the principal lacks `task.write`, `track.sh` says so once and
   `land-pr.sh` falls back to today's `phase/<suffix>-<epoch>` branch. A
   bootstrap that ships but is untracked beats one that stops for a ledger.

## Where the work lives

| Repo | Milestones | Owns | Spec |
|---|---|---|---|
| **orun-cloud** | **BT0** ✅ | the plane's MCP contract: `epic_create`, `milestone_create`, `task_create` with `epic` / `milestone` / `brief` / `assignee` / `contract`; roster 31 → 33 | `specs/epics/saas-baseline-tracking/` (pointer + as-built), `packages/mcp/src/tools/tasks.ts` |
| **orun** | **BT-O1** `orun task create --epic --milestone --brief --assignee --contract` · **BT-O2** `orun task epic create\|show`, `orun task milestone create` · **BT-O3** manifest re-vendored at 33 and the six task-plane tools native in `orun mcp serve` · **BT-O4** `orun pr open --branch-slug --epic --body-file`, `number` in `--json` | the flows' CLI and the sandbox agent's MCP | `specs/orun-baseline-tracking/` |
| **cirrus** | **BT1** `track.sh` over `orun task …` · **BT2** `land-pr.sh` / `push-main.sh` land through `orun pr open` · **BT3** phases ensure milestone + task, umbrella ensures the epic · **BT4** phase 01 lands as a PR · **BT5** the agent lays out the programme and reports the rollup · **BT6** rehearsal + contract test | the flows and the brief | this folder |

Sequencing: BT0 is done. BT-O1 + BT-O2 unblock BT1 and BT3; BT-O4 unblocks
BT2; BT-O3 unblocks the MCP half of BT5 (the brief skips it when the tools
are absent). BT4 and BT6 follow BT3.

## Read order

1. This README — the shape and the decisions.
2. [`implementation-plan.md`](./implementation-plan.md) — BT0–BT6, file by
   file, with "done when".
3. [`risks-and-open-questions.md`](./risks-and-open-questions.md) — the
   human gates (the orun release and the flows' floor, the bootstrapper's
   tool policy) and the open leans.
4. In orun: `specs/orun-baseline-tracking/` (BT-O1–BT-O4: the CLI flags,
   the container commands, the manifest re-vendor, the pen's flags).
5. In orun-cloud: `specs/epics/orun-tasks/` (`design.md` §3.4 binding,
   `epics-and-docs.md`, `tasks-view.md` §5 native authoring) and
   `packages/mcp/src/tools/tasks.ts` (BT0).

## Milestones at a glance

| # | Ships | Where | Depends on |
|---|---|---|---|
| BT0 | `epic_create`, `milestone_create`, `task_create` widened (epic/milestone/brief/assignee/contract) on the MCP roster; 31 → 33 | orun-cloud `packages/mcp` | — (✅ shipped) |
| BT-O1 | `orun task create --epic --milestone --brief --assignee --contract`; `orun task list --epic` | orun | — |
| BT-O2 | `orun task epic create\|show`, `orun task milestone create` (`remotestate/epics.go`) | orun | — |
| BT-O3 | Manifest re-vendored at 33; `task_list`, `task_get`, `policy_preview`, `task_create`, `epic_create`, `milestone_create` native in `internal/platformmcp` | orun | BT0 |
| BT-O4 | `orun pr open --branch-slug --epic --body-file`, PR `number` in `--json` | orun | — |
| BT1 | `flows/common/track.sh`: `ensure-epic`, `ensure-milestone`, `ensure-task`, `rollup` as thin wrappers over `orun task …`; idempotent; degrades loudly | cirrus | BT-O1, BT-O2 |
| BT2 | `land-pr.sh` / `push-main.sh` take a task key and land through `orun pr open` (`orun/<KEY>-<suffix>` branch, `Task:` trailer, manifest block) + label; fallback unchanged | cirrus | BT1, BT-O4 |
| BT3 | Every phase's `land` step ensures its milestone + task, then lands on the task's branch; the umbrella ensures the epic + all milestones up front | cirrus | BT1, BT2 |
| BT4 | Phase 01 lands as a PR (repo born with an initial commit) | cirrus | BT3 |
| BT5 | The agent brief: lay out the programme over MCP first, report progress from the rollup, push the deployment manifest onto the epic (`orun spec push --epic`), name the epic in the completion report | cirrus | BT-O3, BT3 |
| BT6 | Verification: a rehearsal bootstrap whose epic rollup reads 8/8 done; `flows/testing` gains a track.sh contract test against a stub | cirrus | BT3–BT5 |
