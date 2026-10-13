# saas-bootstrap-console — Implementation Plan

Status: Normative for the BC cluster. Visual detail lives in
[`pixel-parity.md`](./pixel-parity.md); decisions and human gates in
[`risks-and-open-questions.md`](./risks-and-open-questions.md). As-built goes in
`IMPLEMENTATION-STATUS.md`, created when BC1 lands.

Two repos: **BC1–BC3** here and in the other baseline repos, **BC-K1–BC-K5** in
orun-cloud (`specs/epics/saas-bootstrap-console/implementation-plan.md`). Each milestone is independently landable; edges are named per
milestone.

Three invariants hold across the cluster:

- **One fact, one owner.** The registry (`infra/baselines-registry/baselines.yaml`)
  owns identity and commerce — `id`, `visibility`, `tier`, `tag`, `sourceRepo`,
  the brief and umbrella paths. The manifest owns the build contract — what it
  needs, what it asks, what it will make. Neither restates the other. The
  registry's `requires` column becomes derived, not authored.
- **The console proves, the agent does.** Every step either collects a value or
  verifies a precondition against live state. No step in the console creates a
  secret or a task; those have owners already and re-running them must stay
  idempotent by identity.
- **A half-finished bootstrap is a first-class object.** It survives a closed
  tab, a new laptop and a re-login, because it lives on the workspace and not in
  browser storage.

## BC1 — `blueprint.yaml` v2 (cirrus)

**Scope.** Extend the manifest to carry everything the console renders, and
remove the one field that cannot be true.

- **Delete `spec.source.tag`.** A file fetched *at* a tag cannot also name one;
  this field has read `baseline-v1` since the registry moved to `baseline-v4`.
  `spec.source.repo` stays — it is a fact about identity, not version.
- **Add `spec.overview`** — `lede`, `architecture[] { layer, items[] }`,
  `outcome[]`. This is what the flow's first step draws. Layers are free text so
  a baseline with a different shape is not forced into ours.
- **Add `spec.secrets[]`** — `key`, `provider`, `template`, `why`, `fact: true`
  for a non-secret connection fact. Transcribed from
  `flows/common/create-secrets.sh`'s own table, which is today the only place
  these are written down.
- **Add `spec.programme`** — `epicSlug`, `epicName` (with `{productname}`),
  `milestones[]`. Transcribed from `flows/phases/00-all/workflow.yaml`'s
  `ensure-milestone` calls.
- **Keep** `requires`, `inputs` (including `askedBy`), `bootstrap`, `verify`.

**Done when** `blueprint.yaml` parses under the schema in BC2, declares every
key `create-secrets.sh` creates and every milestone the umbrella ensures, and
carries no `tag`. A reviewer can read the file and predict every screen.

## BC2 — Manifest conformance (cirrus, needs BC1)

**Scope.** A contract test in `flows/testing/`, wired into `tests/flows` beside
`track`, `land-pr`, `agent-build` and `phase-vars`. Static, no network, no fakes.

It fails when:

- a `requires.integrations` entry is not a provider id the platform serves
  (checked against `listIntegrationManifests()` — same guard as orun-cloud's
  `baselines-requires-providers` test, applied at the source this time);
- `spec.secrets[]` and `create-secrets.sh` disagree about which keys exist;
- `spec.programme.milestones[]` and the umbrella's `ensure-milestone` calls
  disagree;
- `bootstrap.umbrella`, `bootstrap.agentBrief` or a `verify.urls` placeholder
  names a path or input that does not exist;
- `spec.source.tag` reappears;
- an `inputs[].askedBy` is neither `console` nor `agent`, or a `console` input
  has no `pattern`.

**Done when** the suite is green, and each check has been shown to fail on a
deliberately broken copy. The last point matters more than the rest: this test
exists because `spec.source.tag` drifted for three releases under a repo that
already had four contract tests.

> **Known gap, tracked not hidden.** `tests/flows` does not currently execute in
> CI — the lane dies at the workspace OIDC exchange before any test body runs,
> and the same suite on lumen runs four setup steps and no tests. BC2 must fix
> the lane or say plainly that its guard is local-only. A conformance test that
> cannot fail a PR is a comment.

## BC3 — Port the manifest (lumen, stratus; needs BC1, BC2)

One schema, three repos. The conformance test ports with it, so each repo
checks its own manifest against its own flows. Lumen's fleet is deliberately
uncounted in `overview.architecture` until someone verifies the number — a
plausible-looking wrong number is worse than "Worker fleet".

**Done when** all three manifests parse under one schema and each repo's
conformance test is green against its own flows.

## BC-K1 — The manifest door (orun-cloud, needs BC1)

**Scope.** `GET /v1/organizations/{org}/baselines/{id}/manifest` — fetches
`blueprint.yaml` from `sourceRepo` at the registry's `tag`, parses it strictly,
caches it per `repo@tag` (immutable by construction, so cache freely).

- **Strict, with a line number.** Same posture as the catalogue reader: unknown
  key, wrong shape or missing required field is a refusal naming the line, not a
  silent default. This file drives privileged UI.
- **`requires` becomes derived.** `computeReadiness` reads the manifest's
  `requires.integrations` instead of the registry row's `requires` column; the
  column becomes a cached projection the sync writes, never an authored value.
- **Account-owned baselines are untrusted input.** A manifest from a
  customer-controlled repo may declare only provider ids the platform serves and
  may not name a `template` the broker does not have. Refuse, do not sanitise.

**Done when** the door serves all three baselines, readiness is computed from
the manifest, and a malformed manifest fails with a line number in the response.

## BC-K2 — The bootstrap flow (orun-cloud, needs BC-K1)

Six steps, replacing today's three in place: **What you get · Product repo ·
Providers · Secrets · Programme · Review**. Pixel-matched per
[`pixel-parity.md`](./pixel-parity.md).

- Steps 1, 4 and 5 are rendered entirely from the manifest.
- The repo step keeps today's picker and dialog; `askedBy: console` inputs are
  validated against their `pattern` before Continue is offered.
- The providers step keeps today's rows and connect dialog — the change is that
  its list comes from the manifest.
- Secrets and Programme are **previews**: no controls, no writes.

**Done when** adding a provider or a secret to a baseline's `blueprint.yaml`
grows a row in the console with no console change, and the flow matches the
reference at the measurements in `pixel-parity.md`.

## BC-K3 — The build page (orun-cloud, needs BC-K2)

The plan *is* the progress view: one live row per phase, the running row is the
active task, finished rows carry their PR. The agent session is a collapsible
side panel. One status strip carries the four states.

- Phase state comes from the task plane BT already writes — `branch_seen`,
  `pr_opened`, `pr_merged` — not from parsing the agent's prose.
- The strip's content comes from the agent's four line kinds.
- Collapsing the panel gives the plan full width and leaves a pill to return.

**Done when** all four states render from real session data, a blocked phase
never shows a spinner, and the page is legible with the panel collapsed.

## BC-K4 — The resumable draft (orun-cloud, needs BC-K2)

The draft lives on the workspace: baseline, step, repo choice, collected inputs,
timestamps. The Overview carries one card reading that draft — *baselining in
progress*, steps left, next step — and, once started, the build's live state
with a door straight to the build page.

**Done when** a draft survives a new browser, the card's state cannot disagree
with the flow's, and discarding is explicit and reversible until confirmed.

## BC-K5 — The bootstrap contract (orun-cloud, needs BC-K2, BC-K3)

What the console resolved, handed to the session as one object: baseline and
source, repo, inputs, connection statuses, the secrets that will be minted, the
programme, and the `askedBy: agent` keys still outstanding. The agent re-derives
nothing.

**Done when** the session receives the contract instead of three `--set` flags,
and the brief's intake asks only for the keys the contract lists as outstanding.
