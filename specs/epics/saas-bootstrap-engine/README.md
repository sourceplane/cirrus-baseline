# Epic: saas-bootstrap-engine (BE) — the blueprint is the bootstrap

**The bootstrap machinery is 4,971 lines of this repository, and almost none of
it is about this baseline.** `flows/` is eight near-identical workflows over one
contract — *apply → land → converge → verify* — retyped eight times, wrapped
around eleven shell scripts that are themselves thin policy over verbs the orun
binary already has. The same 20-line baseline-fetch preamble appears **59
times**. `ctx.sh` is sourced **32 times**. `land-pr.sh` and `converge.sh` are
GitHub clients for an execution the platform owns.

BE deletes `flows/` and moves its mechanism into the binary, leaving this
repository holding only what is genuinely its own: **what to place, in what
order, what it needs first, and what to say about it while it happens.**

## Status

| Field | Value |
|-------|-------|
| Status | **Draft (not started)** |
| Cluster | **BE** — **BE1–BE6** here · **BE-K1–BE-K4** orun-cloud (`specs/epics/saas-bootstrap-engine/`) · **BE-O1–BE-O8** orun (`specs/orun-bootstrap-engine/`) |
| Owner(s) | `repo-blueprint.yaml` (which absorbs the whole of `flows/`), `tooling/blueprint/` and `tooling/bootstrap/` (both retired), `flows/testing/manifest.test.sh` (kept and widened), `.github/workflows/ci.yml`, `tests/flows` |
| Target branch | `main` |
| Builds on | `saas-bootstrap-console` (BC — the manifest as the contract, and `blueprint.yaml` v2) · `saas-baseline-tracking` (BT — the task plane the phases already write to) · `saas-bootstrap-factory` (BF3/BF5/BF6 — config indirection and deploy-time wiring, which is what lets a phase be declarative at all) · orun `orun-scaffolding` (the Blueprint engine, `internal/scaffold`) · orun `orun-workflows-v3` (whose `poll:`/`until:` primitive BE relocates rather than consumes) |
| Decisions locked | (1) **The Blueprint is the only execution artifact.** `kind: Workflow` leaves the bootstrap path entirely; `Hook.Workflow` is deleted from orun's schema. (2) **orun verbs are typed actions, not argv.** A hook says `uses: orun.pr/land@v1` with validated `with:` parameters; `run:` survives only as the ecosystem escape. (3) **Phase state is derived; a stored file is a cache and must be safe to delete.** (4) **The agent is retired from the build path.** Every input is collected by the console; progress comes from the engine's event stream. (5) **Narration is pre-authored prose in the YAML, templated over state, and may never set state.** |
| End-state target | `orun baseline new cirrus --org ws_… --repo sourceplane/acme` runs the whole bootstrap from one pinned artifact, with no agent, no `flows/`, no workflow engine — and every change to this repository is verified against a real bootstrap before a `baseline-vN` tag is cut. |

## Thesis

Four facts, and the fourth is why this is worth doing now rather than later.

1. **The duplication is structural, not untidy.** 2,904 lines of workflow YAML
   express eight instances of one five-step contract. The preamble that fetches
   the baseline at its pinned commit is copy-pasted 59 times because a workflow
   step has no notion of context. Every one of those copies is a place a fix
   lands in seven of eight files.

2. **The scripts are already orun verbs with a table on top.**
   `create-secrets.sh` is `integrations list` → `secrets list` →
   `integrations <p> secret create` → `secrets revoke`, plus a desired-state
   table that `blueprint.yaml` **already transcribes** and a conformance test
   already holds in step. Make the manifest the input and the transcription,
   the test, and the drift all disappear together.

3. **orun's Blueprint schema is already most of the way there.**
   `internal/scaffold/blueprint.go` has `Phases` with per-phase `Hooks` and
   placement barriers, `CycleBreak`, `Ignore`, provenance and `upgrade.go`.
   Its own doc comment names the gap: *"Approval gates + resumable pausing are
   a planned follow-on."* BE is that follow-on.

4. **The console is already drawing the wrong number of states, and the code
   says why.** `build-model.ts` in orun-cloud: *"The strip's COPY is the
   agent's latest line, verbatim"*, and two of six row states are undrawable
   because *"the shipped agent brief instructs the agent to post each line 'in
   plain words, without the prefix', so the marker never reaches the
   transcript."* Its own conclusion: *"The durable fix is to record the block
   where the other states already live… a shell script is deterministic in a
   way a model paraphrasing prose is not. That is a change in the baseline
   repos and belongs in its own milestone."* This is that milestone.

## Read order

1. `README.md` (this file) — the thesis and the split.
2. [`design.md`](./design.md) — the phase declaration, the narration contract,
   the derivation rule, and the CI ladder.
3. [`implementation-plan.md`](./implementation-plan.md) — BE1–BE6, each with
   scope, dependencies and "done when".
4. [`risks-and-open-questions.md`](./risks-and-open-questions.md) — the
   decisions taken and what is still open.

## Milestones at a glance

| ID | Repo | What | Depends on |
|----|------|------|------------|
| **BE1** | cirrus | `repo-blueprint.yaml` v3: native phases carrying hooks; the eight slices and `split-phases.py` retired | BE-O1, BE-O2 |
| **BE2** | cirrus | The narration contract — `narrate.{start,await,done,failed}` per phase and per notable hook, conformance-tested | BE1, BE-O6 |
| **BE3** | cirrus | Inputs v3 — every input console-collectable (`pattern`, `help`, `example`, `derive`, `probe`); `askedBy` deleted | BE-K1 |
| **BE4** | cirrus | `flows/` deleted — `common/`, the phase workflows, the agent brief, `build.sh`, `cycle-break.mjs` | BE1–BE3, BE-O5, BE-O8 |
| **BE5** | cirrus | CI ladder tiers 0–2: static gates (coverage, action typecheck), dry instantiation (rebrand sweep, **leak gate**), phase simulation (resume determinism) | BE1 |
| **BE6** | cirrus | CI tier 3: the live bootstrap — nightly, pre-tag mandatory, with teardown, and `TIMINGS.md` written back from the run | BE4, BE5, BE-O7 |

**BE1 is the spine** — nothing else in this repository can start before the
blueprint carries the phases. **BE5 should land beside BE1**, not after it: the
tiers verify the collapse as it happens, and tier 1's leak gate closes a
promise this repository is currently breaking (see `design.md` §6).

## Scope boundary

| In scope | Out of scope |
|----------|--------------|
| The bootstrap's shape and prose in this repo; the deletion of `flows/`; this repo's CI ladder | The Blueprint engine, typed actions, the event stream and `orun baseline` (→ orun `orun-bootstrap-engine`) · the console's input collection and build page (→ orun-cloud `saas-bootstrap-engine`) · the rename-map → parameterization move, which BE assumes but does not do (→ `saas-bootstrap-factory` BF3) · `orun … upgrade` |

## What this repository looks like afterwards

```
repo-blueprint.yaml      the whole bootstrap: inputs · sources · modules · phases · hooks · narration
blueprint.yaml           the console contract (unchanged in shape; inputs v3)
tooling/rebrand/         the last argv hook — and itself on notice (BF3)
specs/ tests/ apps/ packages/ infra/

flows/                   DELETED   (2,904 YAML + 1,474 shell + 593 test)
tooling/blueprint/       DELETED   (split-phases.py — phases are native)
tooling/bootstrap/       DELETED   (cycleBreak is a schema field)
```

Hand-maintained bootstrap logic: **~4,971 lines → ~895**, of which the only
non-declarative remainder is one `run:` hook and the deployment-docs renderer.
