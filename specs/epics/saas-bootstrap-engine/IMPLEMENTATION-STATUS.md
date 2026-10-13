# saas-bootstrap-engine (cirrus) — Implementation status

As-built. Kept distinct from the design and the plan: this file records what
shipped and every place it departed from the spec.

| Milestone | Status | Landed |
|---|---|---|
| **BE1** | ✅ Shipped | `repo-blueprint.yaml` v3: nine native phases, hooks, the slices and the splitter deleted |
| **BE2** | ✅ Shipped | the narration contract: 57 authored lines, every reference conformance-checked |
| **BE1a** | ✅ Shipped | the orun floor moved to v2.56.0, and a job that proves the blueprint parses |
| **BE3** | ✅ Shipped | inputs v3: `askedBy` deleted, every input patterned, `apibaseurl` derived — and two seams the manifest had no gate for |
| **BE4** | ✅ Shipped | `flows/` deleted — 4,971 lines, and the five inputs renamed to the manifest's keys in the same commit (open question 10, answered) |
| **BE5a** | ✅ Shipped | Tier 0's coverage gate, the leak gate, and `ai/context/` narrowed to two files |
| **BE5b** | ✅ Shipped | Tier 1 places, brands and runs the phases — and found two orun defects that made a real bootstrap impossible |
| **BE4c** | ✅ Shipped | this baseline names the document a runner places (`spec.bootstrap.blueprint`) |
| **BE6a** | ✅ Shipped | the teardown, before the lane that needs it — workers, D1 and KV by validated prefix |
| **BE6b** | ✅ Shipped | the rehearsal is a component, with a stack this repo keeps |
| BE6 | 🟡 Partial | the tag gate shipped; the live rehearsal itself needs credentials this repository deliberately does not hold |

## BE1 — `repo-blueprint.yaml` v3: native phases

### What shipped

**Nine phases, declared in execution order, named the way the task plane names
them.** `01-scaffold`, `02-foundation`, `03-infrastructure`, `04-workers`,
`04-workers-restore`, `05-edge`, `06-console`, `07-domain`, `08-docs`. Each
carries `title`, `expectedMinutes`, its `requires`, and its
`hooks.{pre,post,await}`. `07-domain` carries the umbrella's shell condition as
`when: inputs.domain`.

**What the splitter was hiding.** `tooling/blueprint/split-phases.py` derived
eight slices and re-mapped phase names to folders through a table inside
itself — this file declared `workspace` **last** while the folder it became,
`01-scaffold`, runs **first**. The deriving also had to PRUNE every cross-phase
`dependsOn` edge, because a slice naming a module in another slice does not
parse. That prune was deleting a real defect for as long as it ran:

```yaml
- name: shared
  dependsOn: [bootstrap]      # a module that does not exist and never has
```

orun refuses that outright (`dependsOn unknown module`), but a pruned edge to a
module in *no* phase is indistinguishable from a pruned edge to a module in an
earlier one. `packages/shared` has no workspace dependency this blueprint
declares as an edge for any package (`contracts` has the same two devDeps and
no `dependsOn`), so the edge is simply gone.

**`discovery-roots`, a new module.** orun's repo-scale gate discovers `apps/`,
`infra/`, `packages/` and `tests/`, which are empty until later phases fill
them, and a missing root is a hard gate failure.
`flows/phases/01-scaffold/workflow.yaml` created them with a `mkdir` and four
`touch`es immediately before calling `orun new`. Shell that creates a file the
tree needs in order to be valid is a module nobody wrote down.

**The identity chain moved from `hooks.postInstantiate` into `01-scaffold`'s
`post` hooks.** It was global because a one-shot instantiation has only one
end; in a phased bootstrap the end of `01-scaffold` *is* that moment.

**Three inputs came in from the flows**: `githuborg`, `epicSlug` and `domain`
were workflow inputs on `flows/phases/*/workflow.yaml`, invisible to anything
reading this file — including the console that has to render a form for them.
They are also written into `.rebrand/values.json`, because that file is
committed and `.orun/provenance.lock` is not: a phase run months later in a
fresh container reads them back from the product repo.

**Task contracts moved to `tasks/<phase>.TaskContract.yaml`** and are named by
each phase's `orun.task/ensure@v1` hook as `contract:`.

**Deleted**: eight `flows/phases/*/blueprint.yaml`, and
`tooling/blueprint/split-phases.py`.

### Two departures from the plan

**1. `04-workers` became two phases, not "two `post` hooks".** The plan said
*"04-workers expresses its two landings as two post hooks around the existing
`cycleBreak:` declaration"*. Both halves of that turned out to be wrong.

The restore can only run **after** `04-workers` has converged — a service
binding may not name a worker that is not deployed — and `post` hooks all run
before `await`, so `strip → land → converge → restore → land → converge` is not
expressible as one phase's hook list. It is also already two landings, with two
PRs and two task contracts. Two units of work that land separately are two
phases; that is the whole of what a phase is here.

**2. There was no `cycleBreak:` declaration to express anything around.**
`repo-blueprint.yaml` has never carried that key, and the worker modules'
edges are acyclic — the cycle lives in a wrangler config a *deploy* reads, not
in the placement order, so orun's DAG has never seen it. This answers open
question 2: `cycle-break.mjs` is not an ordering workaround orun could absorb,
and it survives BE4 as a `run:` hook.

### What the hooks could not say, and the orun milestone that fixed it

BE1 was written against what BE-O1–BE-O8 actually shipped rather than against
`design.md`, and five things the design takes for granted did not exist. They
are fixed in orun **BE-O9**, which BE1 depends on:

| | Gap | Symptom for this file |
|---|---|---|
| 1 | the `with:` scope held only `hooks` | `{{ .inputs.epicSlug }}` and `{{ .phase.name }}` failed at run time |
| 2 | `orun.task/ensure@v1` took no contract | every landing would park at `in_review` forever |
| 3 | an action received only the product dir | `contract: tasks/…` could not resolve |
| 4 | a templated LIST passed through unrendered | a probe would GET the literal `{{ .inputs.repoName }}` |
| 5 | `run:` argv was not templated at all | `node tooling/rebrand/rebrand.mjs` names a path the product does not carry |

Gap 5 was already latent in this file before BE1, next to a comment explaining
that hook argv is not templated. Nothing had hit it because nothing runs these
hooks yet — `flows/` still does that work in shell, and BE4 is what flips it.

### The flows still work, and had to

BE4 deletes `flows/`; BE1 does not. So every caller was repointed rather than
removed:

- `flows/common/apply-blueprint.sh` takes a sixth argument, the phase, and
  passes `orun new --phase`. Its provenance archive is now named by the phase
  — before BE1 each phase was its own document, so `basename "$bp"` named the
  phase by accident, and with one blueprint every phase would have overwritten
  the same `provenance.repo-blueprint.lock`.
- Eight `workflow.yaml` apply steps pass `repo-blueprint.yaml <phase>`.
- `flows/phases/01-scaffold/workflow.yaml` calls
  `orun new --blueprint "$L/repo-blueprint.yaml" --phase 01-scaffold`.
- `track.sh ensure-task` call sites and `track.test.sh` point at `tasks/`.

### Verification

**Placement equivalence, proven rather than asserted.** The pre-BE1 tree was
materialized at `HEAD`, each of the seven slices placed into its own directory,
and the result compared to the new blueprint's per-phase file sets (read from
`orun new --status --json` against an empty output directory, which derives
without probing):

```
same   01-scaffold: 25 files      same   04-workers: 478 files
same   02-foundation: 312 files   same   05-edge: 59 files
same   03-infrastructure: 24      same   06-console: 177 files
                                  same   07-domain: 10 files
EQUIVALENT
```

`01-scaffold` additionally places the four declared `.gitkeep` discovery roots
the flow used to `mkdir`. A byte-level `diff -r` of `01-scaffold` old vs new
differs **only** inside `.orun/` — the provenance lock names a different
blueprint and digest, and the object store pins different blueprint bytes.
`.orun/` is gitignored in every product.

`flows/testing/phases.test.sh` is new and wired into the `flows-contract` CI
job. It carries the pre-migration module partition as data and fails if a
later edit moves a module between phases — the bootstrap's order is
load-bearing (a worker cannot deploy before the D1 binding exists) and a
module that drifts one phase earlier fails at deploy time, live, with nothing
in this repo having looked wrong. It also asserts execution order, that every
phase declares `title`/`expectedMinutes`/hooks, that every `contract:` exists,
that every surviving phase folder has a phase of its name, and that the slices
and the splitter stay deleted.

All seven contract tests pass: `track`, `land-pr`, `agent-build`,
`phase-vars`, `manifest`, `converge`, `phases`.

### Two questions BE1 opened

Recorded in `risks-and-open-questions.md` as 7 and 8:

- **A hook-only phase derives as `done`.** `derivePhase` returns `PhaseDone`
  when a phase places no files, which is right for a consume-only phase and
  wrong for `04-workers-restore` and `08-docs`. Nothing declares a
  `requires.phases` gate on either, deliberately, until orun **BE-O10**.
- **`requires.probe` makes an offline placement impossible**, which Tier 1
  needs. BE1 verified itself through `--status --json`, which derives without
  probing; BE5 decides whether the CLI grows a way to reach the substitute
  runner seam that already exists.


## BE2 — the narration contract

### What shipped

**Fifty-seven authored lines.** Four on every phase (`start`, `await`, `done`,
`failed`) and twenty-one on the hooks whose completion an operator would want
to see — the repo being created, each landing, each convergence, each probe.

They are templates over the engine's own state, which BE-O10 made true rather
than merely declared. A `done` line can say how long it took because `.meta`
carries `elapsed`; a `start` line can say what to budget because it carries
`expectedMinutes`; `07-domain` can name the domain it is wiring because
`.inputs` is in scope. The YAML supplies the prose, the engine supplies the
numbers, and neither can lie about the other.

An operator reading a cirrus build now sees:

```
→ 05-edge · Now the API edge — the single front door in front of all twelve services.
  ⋯ Waiting for the edge to deploy and answer /health on both environments. About 5 minutes.
  · The edge PR is merged into main.
  · The edge deployed and the convergence run came back green.
  · Both /health endpoints answered.
✓ 05-edge · The edge is live on stage and prod, answering /health. 4m12s.
```

Every word of that is in `repo-blueprint.yaml`, reviewed in a pull request and
byte-identical on the next run. That is the whole difference from a model
paraphrasing a transcript.

### One departure: where the checks live

The plan put the narration checks in `manifest.test.sh`. They are in
`phases.test.sh` instead, and the reason is the same one that makes them worth
having: `manifest.test.sh` compares `blueprint*.yaml` — the **console
manifest** — against the flows that realize it. Narration lives in
`repo-blueprint.yaml`, which that test does not read. Putting them there would
have meant opening a second file in a test named after the first.

### Four checks, each proven to fail

`phases.test.sh` grew the conformance rules, and each was verified by breaking
the real file and watching it fail:

| Rule | What a violation looks like |
|---|---|
| Every phase declares all four keys | `phase 06-console declares no narrate.await` |
| Every `await` hook declares one | `await hook converge declares no narrate — a wait with no words reads as a stalled build` |
| No state word in prose | `narrate.done asserts 'complete' — state is the truth and narration is the caption` |
| Every reference resolves | `narrate.done names .inputs.nope, which is not a declared input` |

The fourth is the one with teeth, because it checks against **what the engine
emits at that moment**, not merely against a list of field names. `.meta`
carries `files` and `expectedMinutes` on `start`, `await` and `failed`, and
additionally `elapsed` and `next` on `done` — a phase has not run to a close
before `done`, so a `start` line naming `elapsed` would render empty at exactly
the moment it was written for. The test refuses it:

```
phase 01-scaffold narrate.start names .meta.elapsed;
the start event carries ['expectedMinutes', 'files']
```

### Verification

`orun new --status` against the real blueprint parses every line — orun
refuses an uncompilable narration template and a state word at parse time
(BE-O10), so a passing `--status` is itself a conformance check. All seven
contract tests pass.


## BE1a — the floor, and the check that was missing

**A regression fix, not a planned milestone.** BE1 and BE2 shipped a
`repo-blueprint.yaml` that **no released orun could read**, and every test in
this repository passed while that was true.

### What was broken

BE1 repointed every flow at `orun new --blueprint repo-blueprint.yaml --phase
<name>`. Against `v2.55.2`, the newest release at the time:

```
✕ unknown flag: --phase

✕ parse blueprint: yaml: unmarshal errors:
    line 613: cannot unmarshal !!map into []scaffold.Hook
    line 701: cannot unmarshal !!map into []scaffold.Hook   … ×5
```

All ten BE-O milestones were on orun's `main` and **none was in a release**.
`v2.55.2` sat fifteen commits earlier, at a `Phase` type carrying only
`name`/`description`/`modules`/`hooks`, with `hooks` a bare list rather than
`{pre,post,await}`. This repository's CI pinned `v2.52.6`, older still.

So `main` carried a bootstrap that could not start.

### Why nothing caught it

Every check in this repo reads `repo-blueprint.yaml` with **PyYAML**, which
parses anything well-formed. `phases.test.sh` asserts the module partition,
execution order, narration references — all of it true, and none of it the
question that mattered: *can the CLI at the pinned version read this?*

BE1's own verification had the same shape. Placement equivalence was proven
against an orun compiled from `main` minutes earlier. The two repositories were
each internally consistent; the seam between them was unchecked.

### The fix

**orun v2.56.0** is cut from `381eb74` (BE-O10), the first release carrying the
phase overlay. Every pin here moves to it:

| Where | Was | Now |
|---|---|---|
| `.github/workflows/ci.yml` (both lanes) | `v2.52.6` | `v2.56.0` |
| `flows/AGENT-PROMPT.md` installer | `v2.55.0` | `v2.56.0` |
| `BOOTSTRAP.md` floor (×2) | `≥ v2.52.6` | `≥ v2.56.0` |
| `ai/context/operations.md` | `≥ v2.52.4` | `≥ v2.56.0` |
| `flows/phases/01-scaffold/README.md` | `≥ v2.52.4` | `≥ v2.56.0` |
| `flows/phases/TIMINGS.md` | `≥ v2.52.4` | `≥ v2.56.0` |

The historical notes in `TIMINGS.md`'s defect log keep their old version
numbers: they record which release fixed what, and rewriting them would erase
the record.

### The guard

A new `blueprint-parses` CI job installs orun **at the pinned version** and
makes the CLI itself answer:

```yaml
orun new --blueprint repo-blueprint.yaml --status --out "$(mktemp -d)" \
  --set repoName=acme-cloud --set "productName=Acme Cloud" \
  --set productDomain=acme.dev --set githuborg=acme-inc
```

`--status` derives every phase's state: it parses the document, validates each
hook against the action registry, compiles every `when` and every narration
template, and writes nothing. It does **not** probe — derivation asks the tree,
not the network — so it needs no credential and no workspace.

This is the first check of BE5's Tier 0, brought forward because its absence is
what let the regression through. Run against `main` before this change, it
fails at the first line.


## BE5a — the coverage gate, and the leak the epic named

### The coverage gate (Tier 0)

`repo-blueprint.yaml` decides what a product is made of. A component that no
module names is simply not in the product — and nothing said so. The failure is
quiet and late: the fork builds, its CI goes green, and the missing piece
surfaces when somebody looks for a worker that was never copied.

orun enforces the other half already — every module in exactly one phase, and a
`dependsOn` naming an unknown module is a parse error. What it cannot know is
what this repository *contains*, because a blueprint declares what to place,
not what exists.

`flows/testing/coverage.test.sh` closes that. **43 of 44 components are
placed**; `tests/flows` is declared baseline-only with its reason, because it
tests `flows/`, which no product carries. Exemptions are a named map rather
than a pattern — `tests/*` would also hide the thirteen component suites a
product genuinely needs, and the next baseline-only directory should have to be
argued for in a diff.

It checks four things, each verified by breaking the real file:

| Rule | What a violation reads like |
|---|---|
| every component is placed | `packages/sdk is a component and no module places it` |
| by exactly one module | `packages/shared is placed by 2 modules (shared, shared-again)` |
| whose `from` exists | `module sdk takes its content from packages/sdk-gone, which does not exist — it would place nothing, and say nothing` |
| and an exemption is real | `tests/flows is declared baseline-only and does not exist — drop the entry` |

The third is the sharp one. orun resolves `from` against the source tree and an
**absent path is an empty module, not an error** — so a renamed directory would
silently stop shipping.

### The leak gate (Tier 1), and what it found

`BOOTSTRAP.md` describes a product as the thing cirrus makes, not a copy of
cirrus. The `ai-context` module copied the whole of `ai/context/`, so every
product shipped this repository's `current.md`, `decisions.md` and
`open-risks.md` — and `fork-from-baseline.md`, which opens:

> # Provenance — Cirrus from the Lumen baseline

After rebrand that is a sentence about the **customer's** product, telling them
it was forked from Lumen at a commit they have never seen. Not a leaked secret:
a false statement in the product's own voice, in the file an agent is pointed
at first.

`ai-context` is now `ai-deployment` + `ai-operations`, one module per file.
There is no file list on a copy module, and that is the feature rather than the
workaround — a new file in `ai/context/` cannot ship without somebody writing a
module and arguing for it in a diff.

`flows/testing/leak.test.sh` gates three things over the **derived** placement:
`ai/` is exactly the two declared files; no `flows/`, `agents/`, `tasks/`,
`specs/` or baseline tooling; and no *provenance prose* in the context pack.

That last check deliberately does **not** search for "cirrus". rebrand rewrites
this repository's name into the product's — that is its whole job — so flagging
it would mean failing on input rebrand is about to fix, and testing rebrand's
work in the wrong place against the wrong tree. It looks for what rebrand has
no rule for: another baseline's name, and "forked from" phrasing.

Run against the blueprint as it stood before this change, it names all four
leaking files. That is the plan's acceptance criterion — *"the leak gate is red
until `ai/context/` stops shipping"* — and it was, and it is fixed here.

### What is NOT here, and why

The plan's Tier 1 places the tree, brands it, and runs the product's own
`orun validate` / `orun plan --dry-run` inside it. **A whole-blueprint
`orun new` cannot run**, which Tier 1 discovered on its first execution:

```
✕ phase "02-foundation" requires 01-scaffold (pending) — run 01-scaffold first
```

Every phase's `requires` is checked before the first byte is written, so
`02-foundation` asks whether `01-scaffold` is on disk during the run that is
about to write it. A real bootstrap is unaffected — it runs phase by phase and
the tree accumulates — but a dry instantiation cannot place anything.

So BE5a gates the **derived** placement, which needs no run, and the placement
half moves to **BE5b** behind orun **BE-O11**. Recorded as open question 9.

### Verification

Nine contract tests pass: `track`, `land-pr`, `agent-build`, `phase-vars`,
`manifest`, `converge`, `phases`, `coverage`, `leak`. The coverage gate joins
the bash-only `flows-contract` job; the leak gate rides `blueprint-parses`,
which already installs orun at the pinned version.

## BE3 — inputs v3, and the two seams nobody was checking

### What shipped

`blueprint.yaml`'s `inputs` block, replaced whole and **byte-identical to
orun-cloud's `tests/fixtures/blueprint-manifests/cirrus.yaml`**. That is the
point of the exercise: the console's parser has a fixture claiming to be this
file, and the two are now the same bytes rather than the same intent.

`askedBy` is deleted. It divided inputs into ones a form collects and ones an
agent asked for in a session; the second half no longer exists, so the field
could only ever hold one value. **The cost lands on `pattern`** — an
`askedBy: agent` input was exempt from it, because prose asked for the value
and prose does not validate. All five inputs now carry the rule their value is
checked against before Continue, plus `help` and `example` for the field.

| Input | How it arrives |
|---|---|
| `reponame` | `from: repo.name` — the operator already picked the repository |
| `productname` | typed |
| `productdomain` | typed |
| `apibaseurl` | `derive: "https://api.{productdomain}"` |
| `subdomain` | typed |

**`subdomain` is not probed, though it is the obvious candidate.** Asking
someone to look a workers.dev subdomain up in a dashboard is a question the
Cloudflare connection could answer. The action that would answer it does not
exist: orun's registry is closed at nine and `orun.cloudflare/subdomain@v1` is
not among them, so declaring it would be a manifest promising a capability no
runner has. The manifest parser cannot catch that — it validates a `probe.uses`
for *shape*, not membership, which is the right call and exactly why it cannot
— so the reason is written at the input. It becomes a probe when the action
does.

### The two seams, both found by writing the gate before the change

**1. Nothing checked that the umbrella ACCEPTS what the manifest declares.**
`apibaseurl` is a new key. The manifest's keys are the umbrella's input names,
and orun's flow engine fails closed on a `--set` it has not declared
(`internal/flow/engine.go`: `unknown input %q`). So the new input was one of
two things, and which one depended on a detail neither file states: a bootstrap
that dies at step zero, or — worse, because it is silent — a value the console
resolves, shows the operator on the review step, and then drops on the floor.

It was the silent one, and on every path that exists today. `build.sh` forwards
ten fixed keys and `flows/agent/workflow.yaml` hands it three flags; neither
carries `apibaseurl`, and the console cannot invoke the umbrella at all yet —
that is orun-cloud **BE-K4**. So the derived value reaches the bootstrap
contract and stops there.

Which is harmless *because of the second seam*, and only because of it: with the
two rules held equal, a path that drops the console's value gets rebrand's, and
they are the same string. That is the difference between a fallback and a bug.
The umbrella accepting the key is groundwork for BE-K4 rather than a fix to a
live break — said plainly here because the gate now passes either way, and a
future reader should not have to infer which.

`manifest.test.sh` now checks every declared input against the umbrella's
parsed `inputs` — **one direction only**. The umbrella declares more than this
file does (`workspace`, `out`, `baselineref`, `watch`, `dryrun`, `track`,
`epicslug`, `domain`), and those are how the platform drives a build rather
than what a product is configured with. What must hold is that nothing this
file declares arrives at a flow that cannot take it. `apibaseurl` is now
threaded: declared on the umbrella and on `01-scaffold`, and handed to the
engine's existing `apiBaseUrl`.

**2. The derivation already existed, in JavaScript.** `tooling/rebrand/rebrand.mjs`:

```js
const apiBaseUrl = values.apiBaseUrl ?? `https://api.${productDomain}`;
```

So `derive: "https://api.{productdomain}"` is a second copy of a rule that was
already implemented — which is the failure this file's own header warns about:
*"a drift test between two files catches nothing."*

Both paths are live and neither is going away this milestone. A console
bootstrap resolves `derive` and the flow hands it down, so the manifest's rule
wins; a phase run by hand passes nothing and rebrand's fallback wins. One
value, two implementations. So the gate does not pick a winner — it holds them
equal, parsing rebrand's `?? ` fallback and comparing the expression to the
manifest's after normalizing `${productDomain}` to `{productdomain}`.

### What needed no change, and one thing that now cannot land

`flows/agent/BASELINE-TASK.md` was already correct. It defers to the contract's
`asks` list rather than naming its own intake (BC-K5), and it already handles
the empty case — *"If `asks` is empty there is nothing to ask"*. With inputs v3
`asks` **is** empty for every manifest, so section 1 of the brief is inert
prose in a file BE4 deletes. Nothing to do.

What this milestone found and did not fix is **open question 10**: all five
manifest keys are lowercase and all five blueprint inputs are camelCase (with
`subdomain` → `workersDevSubdomain` a rename, not a casing difference). The
only thing translating them is `01-scaffold`'s `--set` list — which BE4
deletes. That is a BE4 blocker, recorded with the evidence rather than
absorbed here.

### Verification

Eleven manifest rules, **each verified by breaking the real file** and
restoring it:

| Broken | What it reads |
|---|---|
| `askedBy` put back | `inputs[productname] declares askedBy — there is no agent to ask…` |
| a `pattern` removed | `inputs[reponame] declares no pattern — it is collected in a form…` |
| `derive` names nothing declared | `inputs[apibaseurl].derive references {nosuchthing}, which is not a declared input` |
| `derive` names itself | `inputs[apibaseurl].derive references itself` |
| `derive` is a constant | `…has no {key} reference — a constant is a default, not a derivation` |
| two sources | `inputs[apibaseurl] declares from and derive — an input has one source` |
| a malformed `probe.uses` | `…is 'not-an-action-id' — not an action id (<namespace>/<verb>@v<major>)` |
| the manifest's `derive` drifts | `…and tooling/rebrand/rebrand.mjs falls back to 'https://api.{productdomain}'` |
| rebrand's fallback drifts | the same message, from the other side |
| the umbrella drops the input | `inputs[apibaseurl] is not an input of flows/phases/00-all/workflow.yaml` |
| the umbrella's `inputs` vanish | `no inputs found in … — this check has gone blind` |

The umbrella's inputs are **parsed, not grepped**: a regex over the file would
also match a key in a step body, and the blindness guard cannot tell a wrong
match from a right one.

Nine contract tests pass against orun **v2.56.0**, the pinned version — not a
locally built one, which is the distinction BE1a exists to enforce. Both edited
workflows pass `orun workflow validate`, and the engine accepts the threaded
`--set apiBaseUrl=…`.

## BE5b — the tree is placed, branded, and made to answer

### What BE5a could not do, and why that mattered more than it looked

BE5a gated the **derived** placement: what every phase *would* write. It had
no choice — a whole-blueprint `orun new` refused before writing a byte. orun
**BE-O11** fixed that, and this milestone's first act was to run the thing
BE5a could only model.

Which turned up two defects in orun that made **a real bootstrap impossible**,
neither of them visible to any check in either repository.

**1. A requirement could not be satisfied by a branded predecessor.**

```
✕ phase "02-foundation" requires 01-scaffold (drifted) — run 01-scaffold first
```

`01-scaffold` places the tree and then rewrites the baseline's identity out of
every file it just wrote — BE1 moved that hook chain into it, correctly. So
from the moment phase 01 ends, `01-scaffold` derives `drifted`, permanently.
orun's `checkRequires` accepted only `done`. **The bootstrap died at step two**,
and every phase after it too.

**2. `--resume` reverted the product's identity.**

```
before resume:  "name": "acme-cloud"
after  resume:  "name": "cirrus"
```

`--resume` re-placed anything not `done`, which on a branded product is every
placed phase. A resume between phases — what an automated build runs — silently
overwrote the branded tree with the baseline's own rendering.

Both fixed in orun **BE-O12**, and the floor here moves to **v2.56.2**.
v2.56.0 was the first release that could *read* this blueprint; v2.56.2 is the
first that can *run* it past phase 01.

### And one defect of our own

```
✕ phase "05-edge" requires 04-workers-restore (unknown)
```

`04-workers-restore` places no files, so orun derives it as `unknown` — and
fails closed, deliberately, because its work is a landing in the task plane and
a deployment, neither of which the product repo can be asked about. A
requirement naming it can therefore **never** be satisfied.

The epic's own open question 7 says a hook-only phase "may not be relied on by
a `requires.phases` gate, **which is why nothing declares one on them**". That
clause was true of the intent and false of the file, with nothing comparing the
two — the same shape as BE1a's version pin. `05-edge` now requires
`04-workers`, which loses no ordering (phase order in the document is what
sequences a run; `requires` is the gate), and `phases.test.sh` gates the whole
class so it cannot recur.

### `testing/placement.test.sh`

Tier 1 in full, in about **ten seconds**, offline and with no credential:

| Step | What it proves |
|---|---|
| place the whole blueprint from `tests/fixtures/acme.json` | 1085 files, `domain` forced on so the conditional phase is covered |
| assert the repo-scale gate line appeared | `orun validate` + `orun plan --dry-run` and the two-parser check on every generated `component.yaml` ride *inside* `orun new` — which is exactly why they need asserting. A future orun that stopped running them would weaken this tier in silence, and BE1a exists because that already happened once |
| brand it as `01-scaffold`'s hooks do, then `rebrand.mjs --verify` | zero baseline-identity residue |
| the leak rules over the **real files** | `ai/` is exactly the two declared files; no factory; no provenance prose — now read from the *branded* tree rather than this repository's copy |
| `DEFAULT_API_URL` against `blueprint.yaml`'s `derive` | BE3 checked the rules against each other; this checks the value a product ends up with: `https://api.acme.dev` |
| **01 → 07, phase by phase, with the rebrand in the middle** | the step nothing here had ever taken, and where both BE-O12 defects lived |
| `--resume` over the branded tree | the product's identity survives it |

Run against **v2.56.1** — the release before BE-O12 — it reports seven
failures: every phase from 02 to 07 refused, and the resume reverting
`package.json`'s name to `cirrus`. That is the proof the file is worth having.

### Tier 2, and what is split out

**Resume determinism is here**, in the form the design asked for: the phased
sequence runs through a rebrand and a `--resume` afterwards leaves it alone.

**The recording-registry phase walk is not**, and it is not a bash test. It
needs orun's `Options.Actions` substitution seam, which is a Go-level
interface with no CLI surface — BE-O11 established that no *flag* was needed
for offline placement, which is a different thing from being able to inject a
recording runner from a shell. That walk belongs beside the actions in orun's
own suite, or behind a capability orun does not yet have.

### Verification

Ten contract tests pass against orun **v2.56.2**, the pinned version: `track`,
`land-pr`, `agent-build`, `phase-vars`, `manifest`, `converge`, `phases`,
`coverage`, `leak`, `placement`. The new one rides `blueprint-parses`, which
already installs orun, plus `setup-node` for rebrand.


## BE4 — `flows/` deleted

### What shipped

The shell layer is gone: `flows/common/` (eleven scripts), the eight
`flows/phases/*/workflow.yaml`, `flows/phases/00-all/`, the agent's brief,
build script and workflow, `flows/AGENT-PROMPT.md`, `flows/README.md`, and
the five test scripts that tested orun behaviour through fakes
(`track`, `land-pr`, `converge`, `agent-build`, `phase-vars`) along with the
`fake-orun` and `fake-gh` doubles. The `tests/flows` component is retired.

Kept, relocated:

| from | to | why |
|---|---|---|
| `flows/common/render-deployment-docs.sh` | `hooks/render-deployment-docs.sh` | `08-docs`'s `run:` hook — the renderer is this baseline's own business, not a verb any bootstrap needs |
| `flows/testing/{manifest,phases,coverage,leak,placement}.test.sh` | `testing/` | the five that test THIS repository's declarations |
| `flows/testing/provision-workspace.yaml` | `testing/` | throwaway prerequisites for an end-to-end rehearsal |
| `flows/phases/*/README.md`, `README.md`, `TIMINGS.md` | `docs/phases/*.md` | one page per phase, flat, because there are no folders to hold them |

`docs/phases/00-all.md` has no successor: the umbrella was a workflow that
invoked eight workflows, and `--resume` is the same thing as a flag. What was
true in it — why the bootstrap can run unattended, what still needs a human —
moved into `docs/phases/README.md` and `BOOTSTRAP.md`.

### Open question 10, answered in the same commit

The five inputs were renamed to the manifest's keys: `repoName`→`reponame`,
`productName`→`productname`, `productDomain`→`productdomain`,
`apiBaseUrl`→`apibaseurl`, `workersDevSubdomain`→`subdomain` — 55 references
in `repo-blueprint.yaml`, 40 in `rebrand.mjs`, and the rest across eight more
files. This had to be the same commit, because the translation table WAS
`flows/phases/01-scaffold/workflow.yaml`'s `--set` list: delete it alone and
the console sets the manifest's keys on a blueprint that declares different
ones, and orun fails closed on all five.

One `workersDevSubdomain` was deliberately left standing:
`apps/web-console-next/component.yaml`'s. That is an orun *composition
parameter* — a different namespace with its own contract — and renaming it
because it shares a spelling with a blueprint input would have broken the
console's deploy lane to make a grep come back clean.

### What the tests had to become

`manifest.test.sh` compared `blueprint.yaml` against files BE4 deletes: it
read the umbrella's `--set` lines for milestones and `create-secrets.sh`'s
`create` calls for secrets. It now reads `repo-blueprint.yaml`'s own hooks —
`orun.integrations/reconcile@v1` for the secret keys, `orun.task/ensure@v1`
for the milestones — which is a better test than the one it replaced, because
the manifest is now checked against the thing that actually runs rather than
against a script that described it. It also **refuses** `spec.bootstrap.umbrella`
and `spec.bootstrap.agentBrief` if either reappears: orun-cloud BE-K1c made
them optional, and this side makes them absent.

`phases.test.sh` lost its "every phase folder under `flows/` has a phase
declared here" check, which BE4 made vacuous, and gained its successor: every
phase has a page under `docs/phases/`, and every page a phase.
`04-workers-restore` is covered by `04-workers.md` by declaration, because the
two landings are one story. Its "what BE1 deleted stays deleted" guard now
also refuses `flows/` itself.

`coverage.test.sh`'s `BASELINE_ONLY` exemption map is **empty**, and that is
BE4's own result: its one entry was `tests/flows`, exempt because it tested
`flows/`. The mechanism stays — the check refuses an exemption whose directory
is absent, so a stale entry cannot linger, and the next baseline-only
directory should have to be argued for in a diff.

The two leak gates gained three entries they should always have had.
`testing/` and `hooks/` are directories BE4 itself created, and `docs/phases/`
is where the phase docs landed — all three are the factory, and nothing
gated them. (`blueprint.yaml` was missing from the list too.)

### The documentation is the contract change

`BOOTSTRAP.md` and `docs/phases/README.md` are rewritten around
`orun new --blueprint repo-blueprint.yaml --phase <name>` / `--resume` /
`--status`. The per-phase remote references — `orun workflow run
github:sourceplane/cirrus@<ref>//flows/phases/NN/workflow.yaml` — have no
successor and were never going to: one pinned artifact, selected with a flag.
Open question 4 anticipated this and asked for it in the release notes of the
tag that carries BE4; `BOOTSTRAP.md` carries the note inline as well, because
an operator with the old command in their shell history reads the file, not
the release.

Nine documents that described the shell layer as current now describe the
blueprint: `README.md`, the four `ai/context/` files, `ai/context/operations.md`
(whose `OPSFLOWS` placeholder ships to every product), and the ten phase
pages. The epic's own specs still name `flows/` throughout and deliberately
so — they are the record of the migration, and a plan that stopped naming what
it deleted would be a worse plan.

### One thing that got worse, and is recorded rather than hidden

The umbrella ran `create-secrets.sh` at about minute two as a deliberate
write-probe, so a builder/viewer API key failed there with the
re-mint-as-admin hint instead of thirty minutes later. The blueprint has no
equivalent: the first credential write is now `03-infrastructure`'s reconcile.
The failure is still exact and still actionable, but it costs an operator two
phases and a repo creation first. `docs/phases/README.md` says so in its
prerequisites, and it is open question 14.

### Verification

Five contract tests pass against orun **v2.56.2**, the pinned version:
`manifest`, `phases`, `coverage`, `leak`, `placement`. The count went from ten
to five because the other five tested orun's own behaviour through a fake
`orun` and a fake `gh` — `track`, `land-pr`, `converge`, `agent-build`,
`phase-vars` — and those verbs are typed actions now, testable beside their
implementations rather than through a double.

`placement.test.sh` is the one that matters here: it places all 1085 files,
brands them, and runs `01 → 07` phase by phase through the rebrand against the
renamed inputs. A rename that missed a reference would fail it.

## BE6 — the tag gate, and the half that is not code

### What shipped

`testing/tag-gate.sh` answers one question about one commit — *is there a
SUCCESSFUL Rehearsal run on exactly this sha* — and `.github/workflows/tag.yml`
is the door that asks it before creating a tag. A `baseline-vN` tag is what
every product built from this repository resolves; one cut from a commit whose
tier-3 rehearsal never ran publishes a bootstrap nobody has watched work, to
people who find out an hour in.

**Three answers, kept distinct**, because they need three different things done
about them: proven, UNPROVEN (run the rehearsal), and UNANSWERABLE (the API
could not be asked). The third is the one a gate gets wrong — an API error that
reads as "unproven" sends somebody to re-run a rehearsal that already passed;
one that reads as "proven" cuts the tag the file exists to stop.

**What it can and cannot enforce**, said plainly rather than implied. A
workflow cannot refuse a tag push: a tag is created and THEN the event fires,
and required status checks apply to branches, not tags. So `cut` is the gate
and `verify` (on `push: tags`) is the alarm, and making the refusal BINDING
needs one repository setting no file here can make — a ruleset on `baseline-v*`
with "Restrict creations". A gate that quietly is not one is worse than a gate
that says what it is.

### And then the gate found what it was written to find

`repo-blueprint.yaml`'s `github-workflows` module copies the WHOLE `.github`
directory, so anything added there travels into every product. Three things
were travelling, each verified by placing a real product rather than by
reading: every path-shaped `ignore` entry was INERT (orun matches an entry with
no glob metacharacter against each path SEGMENT), and both `rehearsal.yml`'s
nightly cron and `ci.yml`'s factory jobs were shipping into customer products.

### The half that is not code, and is not this repository's to finish

**Done when** a `baseline-vN` tag cannot be pushed without a green tier-3 run
on that commit, and `TIMINGS.md` carries measurements rather than estimates.
The first clause is now enforced as far as a file can enforce it. The second
exists only after a real ~60-minute bootstrap against a real Cloudflare
account, and that needs two credentials this repository deliberately does not
hold (open question 16) — a rehearsal workspace and a Cloudflare account, with
`secret://lumen/cirrus-rehearsal/rehearsal/…` and the `ORUN_REHEARSAL_WORKSPACE`
repository variable set.

Until the first green nightly, `TIMINGS.md` keeps saying its numbers are
estimates rather than being quietly blessed by a workflow that exists.

### What is waiting on the same thing

`baseline-v6`. This baseline's registry row still pins `baseline-v5`, whose
`blueprint.yaml` the platform's parser REJECTS — orun-cloud BE-K4b measured it,
and all five registered baselines fail the same way: BE-K1 made `pattern`
required on every input and no baseline has re-cut since. HEAD's
`blueprint.yaml` parses (five inputs, all patterned; eight milestones), so a
`baseline-v6` fixes the row — and cutting one goes through the gate above,
which is waiting on the rehearsal.
