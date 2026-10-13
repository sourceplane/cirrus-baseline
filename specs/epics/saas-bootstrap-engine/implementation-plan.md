# saas-bootstrap-engine — Implementation Plan

Status: Normative for the BE cluster's cirrus milestones. The model lives in
[`design.md`](./design.md); decisions and open questions in
[`risks-and-open-questions.md`](./risks-and-open-questions.md). As-built goes in
`IMPLEMENTATION-STATUS.md`, created when BE1 lands.

Three repos: **BE1–BE6** here, **BE-K1–BE-K4** in orun-cloud, **BE-O1–BE-O8** in
orun. Every milestone is independently landable; cross-repo edges are named per
milestone. The ordering constraint that matters across the whole cluster:

> **Nothing in this repository may delete a flow before the orun milestone that
> replaces it has shipped.** BE4 is gated on BE-O5 and BE-O8 for exactly this
> reason — invert them and the baseline has no way to express a bootstrap in
> between.

## BE1 — `repo-blueprint.yaml` v3: native phases (needs BE-O1, BE-O2)

**Scope.** Promote `phases:` from an input of `split-phases.py` to orun's own
`Phase` overlay, and move each phase workflow's five steps into that phase's
`hooks.{pre,post,await}`.

- Each of the eight phases gains `title`, `expectedMinutes`, `requires.phases`,
  `requires.probe` and its hook lists, per `design.md` §2.
- `07-domain` keeps its condition as `when:`, replacing the umbrella's
  `if [ "{{ inputs.domain }}" = "true" ]`.
- `04-workers` expresses its two landings as two `post` hooks around the
  existing `cycleBreak:` declaration; `tooling/bootstrap/cycle-break.mjs` is
  retired **only if** orun's `cycleBreak` semantics are confirmed to defer the
  same edge (open question 2).
- The eight `flows/phases/*/blueprint.yaml` slices are deleted; there is one
  blueprint again.
- `tooling/blueprint/split-phases.py` is deleted, and with it the cross-phase
  `dependsOn` prune — orun's barrier already forbids the forward edge the
  prune existed to hide.
- The phase task contracts move to `tasks/<phase>.TaskContract.yaml` and are
  referenced by the `orun.task/ensure@v1` hook.

**Done when** `orun new --blueprint repo-blueprint.yaml --dry-run` places every
module in the same order the eight slices did (asserted by Tier 2), no
`flows/phases/*/blueprint.yaml` remains, and `split-phases.py` is gone from the
tree and from `flows/phases/README.md`.

## BE2 — The narration contract (needs BE1, BE-O6)

**Scope.** Author the prose and the test that keeps it honest.

- `narrate.{start,await,done,failed}` on every phase; `narrate` on every hook
  whose completion is worth a line (`land`, `converge`, `verify`).
- Narration is a template over state with a constrained funcmap — the same
  sandbox rules as module rendering, no file/exec/net.
- `manifest.test.sh` gains the narration checks: every phase declares the four
  keys; every `await` hook declares one; every template reference resolves
  against the event schema orun publishes; no narration string contains a state
  word (`done`, `failed`, `complete`) outside a template expression — prose may
  describe, never assert.

**Done when** a reviewer can read `repo-blueprint.yaml` top to bottom and
predict every line an operator will see, and the test fails if they diverge.

## BE3 — Inputs v3 (needs BE-K1)

**Scope.** Make every input collectable by a form.

- `askedBy` deleted from this repo's `blueprint.yaml`.
- `productname`, `productdomain` and `subdomain` — today `askedBy: agent`, and
  therefore pattern-free — acquire `pattern`, `label`, `help` and `example`.
- `apibaseurl` gains `derive: "https://api.{productdomain}"`.
- `subdomain` gains `probe: { uses: orun.cloudflare/subdomain@v1 }`.
- `manifest.test.sh` asserts every input has a `pattern` and every `derive`/
  `probe` references a declared input or a registered action.

**Done when** no input in this repository needs a human to be asked a question
in prose, and BC's `askedConsoleInputs()` returns the whole set.

## BE4 — `flows/` deleted (needs BE1–BE3, BE-O5, BE-O8)

**Scope.** The deletion, once every replacement is live.

> **The cross-repo half is done.** `spec.bootstrap.umbrella` and
> `spec.bootstrap.agentBrief` named the two files BE4 deletes, and orun-cloud
> both required them in the manifest and *fetched* them in its catalog
> preflight — so the tag carrying BE4 would have been refused twice over.
> orun-cloud **BE-K1c** shipped both halves. What remains is this repository's
> own: open question 10's input-key rename, in the same commit that deletes the
> translation table.

- Delete `flows/common/` (eleven scripts), the eight `flows/phases/*/workflow.yaml`,
  `flows/phases/00-all/`, `flows/agent/BASELINE-TASK.md`, `flows/agent/build.sh`,
  `flows/agent/workflow.yaml`, `flows/AGENT-PROMPT.md`.
- Keep, relocated: `render-deployment-docs.sh` → `hooks/`, invoked as phase 08's
  `run:` hook; `manifest.test.sh` and `provision-workspace.yaml` → `testing/`.
- Delete `flows/testing/{track,land-pr,converge,agent-build,phase-vars}.test.sh`
  and the `fake-orun`/`fake-gh` doubles: they test orun behaviour now and move
  to orun's own suite beside the verbs.
- Rewrite `BOOTSTRAP.md` and `flows/phases/README.md` around
  `orun baseline new` / `--phase` / `--resume`; the per-phase remote-reference
  URLs become `--phase <name>` on one pinned artifact. This is a documented
  contract change, called out in the release notes for the tag that carries it.
- `tests/flows` component retired or reduced to the manifest test.

**Done when** `flows/` does not exist, a full bootstrap runs green (BE6), and
no document references a path under it.

## BE5 — CI ladder, tiers 0–2 (needs BE1; lands beside it)

**Scope.** The three free tiers, per `design.md` §6.

- Tier 0: `orun validate` in CI; the **coverage gate** (every component
  directory in exactly one phase); `manifest.test.sh` kept.
- Tier 1: dry instantiation into a temp dir from `tests/fixtures/acme.json`;
  two-parser gate; `orun validate` + `orun plan --dry-run` in the produced
  tree; `rebrand.mjs --verify`; the **leak gate**.
- Tier 2: the recording-registry phase walk and the **resume determinism**
  assertion.

**Done when** the three tiers run on every pull request in under ~3 minutes
total, and the leak gate is red until `ai/context/` stops shipping — which is
the point, and is fixed in the same PR by narrowing the `ai-context` module to
the files a product should actually carry.

## BE6 — CI tier 3: the live bootstrap (needs BE4, BE5, BE-O7)

**Scope.** The end-to-end run that has never happened.

> **Corrected before implementing, per open questions 12, 15 and 16.** Three
> things in the original entry no longer describe anything that exists, and one
> was never satisfiable. The corrections are inline below; the design (§6) is
> left as written, because that is where the design is recorded and this file
> is where the plan is.

- A workflow that provisions a scratch workspace + repo
  (`testing/provision-workspace.yaml`, relocated by BE4), clones this baseline
  at the commit under test and runs
  `orun new --blueprint repo-blueprint.yaml --out <product> --run-hooks
  --resume --progress json`. **Not `orun baseline new`** — that is BE-O7b and
  is not in any release; the flag form is what a bootstrap runs today, and
  swapping it in later changes one line of this workflow (open question 15).
- Asserts **phases placed** — `done` OR `drifted`, never `Done()` alone —
  endpoints, rollup and the narration sequence. A branded product's phases
  derive as `drifted` permanently and by design, so "every phase `done`" is
  unsatisfiable and any "resume until done" loop never terminates
  (open question 12).
- The two properties nothing tests today: idempotence on re-run, and
  cross-session resume from a deleted working directory.
- Per-phase wall clock written back into `docs/phases/TIMINGS.md` (relocated
  by BE4) as a committed artifact of the run.
- `always()` teardown: delete the repo, revoke the brokered secrets, and
  **destroy the Cloudflare resources the run created** — which the original
  entry did not list and which is the only part of teardown that costs money
  if it is missing (open question 18: ~30 paid resources per run, and orun
  has no `destroy` verb). Not "retire the workspace": there is no verb for
  that either, so tier 3 reuses ONE rehearsal workspace instead of creating
  one per run (open question 17), which also exercises the adoption and
  idempotence paths a fresh tenant never would.
- Triggers: nightly on `main`, `e2e` label on a PR, and a **required check on
  the tag workflow** so no `baseline-vN` is cut from an unproven tree.

**Done when** a `baseline-vN` tag cannot be pushed without a green tier-3 run
on that commit, and `TIMINGS.md` carries measurements rather than estimates.

**Two halves, and only one of them is code.** The tag gate is this repository's
to build. The measurements are not: they exist only after a real ~60-minute
bootstrap against a real Cloudflare account, so the first green nightly is what
closes the second half — and until then `TIMINGS.md` must keep saying its
numbers are estimates rather than being quietly blessed by a workflow that
exists. **And the run needs two credentials this repository deliberately does
not hold** (open question 16), which is a decision before it is an
implementation.

## Cross-repo edges

| This milestone | Needs, from | Because |
|---|---|---|
| BE1 | orun **BE-O1** (typed actions), **BE-O2** (`--phase`/`--resume`/derivation) | a phase's hooks cannot be authored before the action registry exists |
| BE2 | orun **BE-O6** (event stream + `--progress`) | narration has nowhere to be printed |
| BE3 | orun-cloud **BE-K1** (manifest v3 parser) | the console must accept the new input fields before the baseline declares them |
| BE4 | orun **BE-O5** (remaining actions), **BE-O8** (`Hook.Workflow` deleted) | the deletion rule above |
| BE4 | orun-cloud **BE-K1c** ✅ | `spec.bootstrap.umbrella` and `agentBrief` had to stop being required, and the catalog preflight had to stop fetching them, before a tag without those files could be registered at all. Both shipped; see open question 11 |
| BE6 | orun **BE-O7** (`orun baseline`) | the run command does not exist yet |
