# saas-bootstrap-engine — Design

Status: Normative for the BE cluster's cirrus half. The engine contract it
depends on is orun `specs/orun-bootstrap-engine/design.md`; the console half is
orun-cloud `specs/epics/saas-bootstrap-engine/design.md`. Where this document
and those disagree about a shared artifact, the owning repo wins: orun owns the
Blueprint schema, orun-cloud owns the manifest parser's vendored twin, this repo
owns what it declares.

## §1 — What moves, and the line it moves along

A script belongs in the binary if its mechanism is true for **any** baseline;
its facts stay here as declared data. This is orun-scaffolding's invariant 8
(*"orun's core names no ecosystem"*) applied to the bootstrap.

| `flows/` today | Becomes | Owner after |
|---|---|---|
| `common/preflight.sh` (103) | `uses: orun.doctor/check@v1` | orun |
| `common/track.sh` (210) | `orun.task/ensure@v1`, `orun.task/rollup@v1` | orun |
| `common/create-secrets.sh` (99) | `orun.integrations/reconcile@v1` | orun |
| `common/land-pr.sh` + `push-main.sh` (253) | `orun.pr/land@v1` | orun |
| `common/converge.sh` + `ghrest.sh` (222) | `orun.run/watch@v1` | orun |
| `common/verify-endpoints.sh` (41) | `orun.http/probe@v1` | orun |
| `common/ctx.sh` (59) | Blueprint `context` | orun |
| `common/apply-blueprint.sh` (142) | `orun new` + one `run:` hook | orun (mostly) |
| `agent/build.sh` (145) | the engine's event stream | orun |
| `common/render-deployment-docs.sh` (200) | a `run:` hook | **here** |
| the 8 phase workflows (2,904) | `phases:` in `repo-blueprint.yaml` | **here** |
| `flows/testing/manifest.test.sh` (200) | kept, widened | **here** |

`run:` survives for genuine ecosystem escapes. Today that is
`node tooling/rebrand/rebrand.mjs` and the docs renderer, and nothing else.

## §2 — The phase, declared

`repo-blueprint.yaml` already carries `phases:` as an input to
`split-phases.py`. BE1 makes it the real thing: orun's own `Phase` type, which
already imposes the placement barrier and already forbids a `dependsOn` edge
pointing forward across it. That last property is load-bearing — it is exactly
what `split-phases.py` fakes by *pruning* cross-phase edges, and the prune
disappears with the script.

```yaml
phases:
  - name: 05-edge
    title: The API edge
    modules: [api-edge, api-edge-tests]
    expectedMinutes: 5
    when: "true"                          # CEL over inputs; 07-domain's condition
    retry: { attempts: 3, backoff: 60s }
    requires:
      phases: [03-infrastructure]         # placement — derived, never trusted
      probe:                              # reality — what a lock file cannot know
        - uses: orun.secrets/exists@v1
          with: { keys: [WIRING_D1, WIRING_KV], envs: [stage, prod] }
    narrate:
      start:  "Now building the API edge — the single front door to all 12 services."
      await:  "Waiting for the deploy to converge. Usually about five minutes."
      done:   "The edge is live on stage and prod, answering /health."
      failed: "The edge did not come up. The deploy log above says why."
    hooks:
      pre:
        - id: task
          uses: orun.task/ensure@v1
          with: { kind: task, epic: "{{ .inputs.epicslug }}", milestone: "{{ .phase.name }}",
                  title: "phase({{ .phase.name }}): api-edge",
                  contract: "tasks/05-edge.TaskContract.yaml" }
      post:
        - id: rebrand
          run: [node, "{{ .baseline.dir }}/tooling/rebrand/rebrand.mjs",
                --values, .rebrand/values.json, --allow-dirty]
        - id: land
          uses: orun.pr/land@v1
          narrate: "Opened and merged the edge PR."
          with: { task: "{{ .phase.hooks.task.outputs.key }}",
                  branchSlug: "{{ .phase.name }}", wait: false }
      await:
        - id: converge
          uses: orun.run/watch@v1
          with: { exec: "{{ .phase.hooks.land.outputs.execId }}", resumeBudget: 3 }
        - id: verify
          uses: orun.http/probe@v1
          with: { urls: "{{ .manifest.verify.urls }}", envs: [stage, prod] }
```

`requires.probe` is what makes a phase genuinely independent. Today
`flows/phases/04-workers/README.md` carries the same knowledge as prose —
*"Lane fails resolving `WIRING_*`: phase 03 incomplete — re-run phase 03"* — and
prose cannot gate anything.

## §3 — Derivation: the rule that makes a later session possible

**Phase state is derived. A stored file is a cache and must be safe to delete.**

This is not a preference. `.orun/*` is gitignored in this repo (`.gitignore:21`)
and phase 01 writes `.orun/` into every product's `.gitignore`, so the per-phase
provenance `apply-blueprint.sh` archives has **never** survived a container. The
bootstrap's headline property — *"run one phase today and the next whenever"*,
from a fresh container with two env tokens — works today precisely because
nothing is stored.

Where the truth lives:

| Layer | Where | Survives a new session | Answers |
|---|---|---|---|
| product repo (git) | `sourceplane/acme` | yes | which modules are placed; `.rebrand/values.json` — the inputs |
| task plane | platform | yes | epic/milestone/task rungs and their derived verdicts |
| provider | live | yes | is it actually deployed |
| `.orun/run.state` | container, gitignored | **no** | which exec id is being watched *right now* |

Each phase answers "am I done?" by re-deriving, the way the flows already do:
re-apply (`orun new` is byte-deterministic, so an empty diff means placed —
today's `land-pr: nothing to land`), read the task's rung, ask the platform
about the landing commit's run, probe the declared URLs.

Two rules follow, and neither exists today:

- **Inputs on resume are a conflict, not an override.** `InputsHash` is already
  in orun's provenance. If `--set` values differ from what the product repo
  records, refuse. Half a product branded *Acme* and half *Acme Cloud* is a
  silent failure; changing inputs after the fact is `upgrade`'s job.
- **A lease, because sessions are plural.** An operator re-pressing Build while
  a runner is mid-phase must be told *"04-workers is being run by run_… since
  09:12"*, not race it inside git.

## §4 — Narration: pre-authored prose, printed from state

The engine emits one event stream; the CLI and the console are two renderings
of it. Every event carries two text fields with different jobs:

- **`detail`** — the machine's line, verbatim, high volume. CLI stdout; a
  collapsible log in the console.
- **`narration`** — the line authored *here*, in `narrate:`, one per
  transition. The progress feed.

Four rules keep narration honest:

1. **It is a template over state, never prose about facts.**
   `"{{ .phase.title }} is live on {{ .envs | join }}"` cannot assert what the
   state does not hold.
2. **It may not set state.** The `state` field is the truth; narration is the
   caption. A missing `narrate.done` degrades to a generated line — never to
   silence, and never to a claim.
3. **It is conformance-tested** in `manifest.test.sh`'s existing discipline:
   every phase declares `start`/`done`/`failed`, every `await` hook declares
   `await`, and no narration references a state field that does not exist.
4. **It is prose in YAML** — reviewed in a pull request, diffed like code,
   byte-identical on every run. That is the whole difference from a model
   paraphrasing a transcript.

The *"done, summary, now next"* line is **composed by the engine**, not
authored: the previous phase's `narrate.done`, plus derived facts, plus the next
phase's `narrate.start` and `expectedMinutes`.

```
✓ 05-edge · The edge is live on stage and prod, answering /health.
    3 modules placed · PR #14 merged · convergence green in 4m12s
→ 06-console · Now building the web console. The longest phase — about 15 minutes.
```

The YAML supplies the prose, the engine supplies the numbers, and neither can
lie about the other.

## §5 — Inputs: the agent leaves, and the cost is validation

`askedBy: console | agent` is deleted. The deletion is not the work — this is:
in orun-cloud's manifest contract a `console` input **requires** a `pattern`
and an `agent` input does not, so every migrated input acquires validation it
has never had, plus what a form needs and a conversation did not.

```yaml
inputs:
  - key: productdomain
    label: Product domain
    help: Where the console and API will live. You point DNS at it later.
    example: acme.dev
    pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z]{2,})+$"
    required: true
  - key: apibaseurl
    label: API base URL
    derive: "https://api.{productdomain}"          # prefilled, editable
    pattern: "^https://.+"
  - key: subdomain
    label: workers.dev subdomain
    probe: { uses: orun.cloudflare/subdomain@v1 }  # fetched from the connection
    pattern: "^[a-z0-9][a-z0-9-]{0,62}$"
```

`probe:` is the upgrade worth taking while the field is open: the workers.dev
subdomain is a fact Cloudflare already knows and the operator has to hunt for.
The agent asks; a form can fetch. `derive:` and `from:` (the existing
repo-facts path) stay as they are.

This deletes `flows/agent/BASELINE-TASK.md` and, with it, a documented failure:
*"an operator who picks 'custom' hands you back no value at all, costing two
more turns (observed live)."* A form cannot do that.

## §6 — The CI ladder

Today this repository's CI is three jobs — `flows-contract`, `plan`, `run` — with
**no schedule and no end-to-end bootstrap ever run**. `flows/phases/TIMINGS.md`
says so: *"no Cirrus bootstrap has been measured end to end yet."* The principle
is to push maximum coverage into the tiers that are free.

### Tier 0 — static · every PR · seconds

`orun validate --blueprint repo-blueprint.yaml`: schema; DAG acyclic modulo
declared `cycleBreak`; no `dependsOn` edge crossing a phase barrier forward;
every `uses:` action id resolvable and its `with:` parameters typechecked
against the registry. Plus two gates that do not exist today:

- **Coverage gate.** Every discovered component directory is named by exactly
  one module in exactly one phase. Coverage is complete today (42 of 44 tree
  directories; `infra/terraform` via its children, `tests/flows` excluded by
  intent) — **and nothing enforces it.** Add an app, forget the blueprint, and
  it is silently absent from every future fork.
- `manifest.test.sh`, unchanged. It is the strongest test in the repository and
  its rule — compare the manifest to *the thing that does the work*, never to
  another copy of the claim — is the rule BE2's narration checks inherit.

### Tier 1 — dry instantiation · every PR · ~1 min · no network

`orun new --blueprint repo-blueprint.yaml --out $(mktemp -d) --values
tests/fixtures/acme.json --dry-run`, then:

- the two-parser output gate on every generated `component.yaml` (orun's
  `gate.go` already does this — it is simply not wired here);
- `orun validate` + `orun plan --dry-run` **inside the produced tree**;
- `rebrand.mjs --verify` → zero residue. This is the only defence the rename-map
  model has, and it catches a new identity literal *on the PR that adds it*;
- **the leak gate.** Assert the produced tree contains no baseline-identity
  strings and none of this repository's own agent state. The `ai-context`
  module copies `ai/context/` wholesale, which includes
  `fork-from-baseline.md`, `decisions.md`, `open-risks.md` and `current.md` —
  so every product built from cirrus today ships this repo's provenance, and
  after rebrand it ships it as a *false* statement about the customer's
  product. `BOOTSTRAP.md` promises the opposite: *"None of this baseline's
  machinery (flows, rebrand tooling, agent state, forking docs) ships, and
  nothing in the product presents it as a copy of anything."* Tier 1 makes the
  promise a test it currently fails.

### Tier 2 — phase simulation · every PR · ~2 min · fakes

Re-point the existing `fake-orun`/`fake-gh` harness from testing the bash to
testing the phase graph: walk phases in order, place, assert `requires.phases`
satisfied, run hooks against a **recording action registry**, assert the
expected action sequence and parameters. Catches a phase added without a task
contract, a `verify` entry or a probe; and an action whose parameter shape
changed.

Plus **resume determinism**: instantiate through phase N, delete everything
except the product repo, run `orun baseline status`, assert it derives exactly
N. That makes §3's rule a test rather than a claim, on every PR, for free.

### Tier 3 — live bootstrap · nightly + pre-tag · ~60 min · real cloud

| | |
|---|---|
| Triggers | nightly on `main` · any PR labelled `e2e` · **mandatory before a `baseline-vN` tag is cut** — the tag is what customers get |
| Provision | `flows/testing/provision-workspace.yaml`, which already creates a throwaway workspace, connects Cloudflare from `$CLOUDFLARE_API_TOKEN` and makes an empty private repo. Per-run names (`scratch-<run-id>`) so runs never collide |
| Run | `orun baseline new cirrus@<sha> --org <scratch-ws> --repo sourceplane/scratch-<id> --local --resume --progress json` |
| Assert | every phase `done` · `baseline status --json` matches the expected set · every `verify.urls` 200 on stage+prod · the epic rolls up complete · **the narration sequence matches the declared one** |
| And the properties nothing tests today | **idempotence** — re-run `--resume`, expect zero phases run, exit 0 · **cross-session resume** — kill after phase 04, delete the working directory entirely, re-clone in a fresh container, `--resume`, expect completion · **timings** — record per-phase wall clock and write it back to `TIMINGS.md` |
| Teardown | an `always()` step retiring the workspace, deleting the repo and revoking the brokered secrets. Today cleanup is *"manual and YOUR job"*, which leaks real Cloudflare resources the first night this runs |
| Cost | ~30 runs/month, `concurrency: 1`; needs an admin-role workspace key and a Cloudflare token with D1 Write. Blast radius is one throwaway tenant per run |

The timings step closes an open loop: the registry claims `expectedMinutes` is
*"measured, not guessed"* while `TIMINGS.md` carries estimates and asks to be
corrected — *"an estimate that survives its first real run unchanged is a
document nobody checked."*

### Tier 4 — the reciprocal, in the other repos

orun-cloud's `catalog-sync plan` already preflights the brief and umbrella at
every declared tag; BE-K adds the manifest, parsed by the **console's own**
parser, asserting `served` — so a baseline that would silently degrade to
`not_found` fails the registry PR instead of quietly falling back. And orun runs
tiers 0–1 against every registered baseline's blueprint **at its published
tag**, so a change to an action tells you which baselines it breaks. That is the
vendored-parity discipline `orun-mcp` UM0–UM6 established for the tool manifest,
applied to the action registry.
