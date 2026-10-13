# Epic: saas-bootstrap-console (BC) — the manifest is the contract, the console is the surface

**A baseline already knows what it needs; nothing asks it.** `blueprint.yaml`
has sat at the root of this repo since the BF work, declaring the providers a
bootstrap requires, the inputs it needs and who should ask for each — and
**nothing in orun-cloud reads it**. The console derives its checklist from a
`requires` column on the registry row instead, so the repo's own statement of
what it needs is decoration. The proof is in the file: its `spec.source.tag`
says `baseline-v1` while the registry serves `baseline-v4`. A field describing
the very tag the file is fetched at has been wrong for three releases, and no
test, page or build noticed.

BC makes the manifest load-bearing. The repo declares; the console collects and
*proves* preconditions; the agent executes. One new rule carries most of the
weight: **the manifest may not restate a fact the registry owns** — which is
why `spec.source.tag` is deleted rather than corrected.

## Status

| Field | Value |
|-------|-------|
| Status | **Draft (not started)** |
| Cluster | **BC** — two repos: **BC1–BC3** cirrus and the other baseline repos (this folder) · **BC-K1–BC-K5** orun-cloud (`specs/epics/saas-bootstrap-console/`, which carries the door, the flow, the build page, the draft and the contract in its own `design.md`) |
| Owner(s) | here: `blueprint.yaml`, `flows/testing/`, `tests/flows` · then `sourceplane/lumen`, `sourceplane/stratus` · orun-cloud: `apps/agents-worker/src/{blueprints.ts,handlers/blueprints.ts}`, `apps/web-console-next/src/components/baselines/*`, `apps/integrations-worker` (read-only) |
| Target branch | `main` |
| Builds on | `saas-baseline-tracking` (BT) — the programme this flow previews is the one `track.sh` and the umbrella already create · orun-cloud `saas-baseline-registry` (the declared catalogue at `infra/baselines-registry/baselines.yaml`, and its tag preflight) · `saas-blueprints-onboarding` BP3 (today's three-step flow, which BC replaces in place) · `saas-integrations` IR0 (the served `IntegrationDescriptor` registry, which is where a provider id acquires meaning) |
| Design target | **Pixel parity with the published reference UI.** The reference is an interactive artifact, not a picture: [Baseline Bootstrap Flow](https://claude.ai/code/artifact/8201dc71-2239-4fa5-9933-1a35f2d5f19d). Measurements, tokens and state rules are transcribed in [`pixel-parity.md`](./pixel-parity.md), which is normative where it and prose disagree. |
| End-state target | An operator picks a baseline, reads what it builds, chooses a repo, connects what it deploys to, sees the secrets and the programme it will create, and presses one button. They may leave at any point and be pulled back by a card on the Overview. On start they land on a build page: the work plan live, the agent in a side panel. Every screen is drawn from the baseline repo's `blueprint.yaml`; adding a provider to that file grows a row in the console with no console change. |

## Thesis

Three facts make this cheap, and one makes it urgent.

1. **The manifest already exists and already has the hard part.** `blueprint.yaml`
   carries `requires.integrations`, `requires.apiKeyRole`, and — the piece
   nobody has used — `inputs[].askedBy: console | agent`. That field is the
   whole console/agent division of labour, written down two epics ago and
   never wired.
2. **The console already refuses to hardcode.** `flow-model.ts` says it in a
   comment: everything a baseline declares is a connection the workspace makes,
   *"whatever it happens to be: an allowlist here would silently hide a new
   provider's row"*. `registry.ts` refuses a fallback provider catalogue for
   the same reason. The surface is already built to be told what to render.
   It is simply told by the wrong source.
3. **The things the UI would "create" already have owners.** Secrets come from
   `flows/common/create-secrets.sh`, brokered from connections so no credential
   is typed; epics and milestones come from `track.sh`, idempotent *by identity*.
   So BC's secrets and programme steps are **previews**, not forms — and that is
   a feature, not a compromise. A console that minted secrets would be a form
   where a human types credentials, which is strictly worse than what exists.

And the urgency: **the version field has already drifted three releases.** Any
design that keeps two descriptions of one baseline will drift again. BC's rule —
the registry owns identity and commerce, the manifest owns the build contract,
neither restates the other — is the only part of this epic that cannot be
deferred.

## Read order

1. This README — the thesis and the split.
2. [`pixel-parity.md`](./pixel-parity.md) — the reference UI, its tokens and the
   state rules. Normative for anything visual.
3. [`implementation-plan.md`](./implementation-plan.md) — milestones and their
   "done when".
4. [`risks-and-open-questions.md`](./risks-and-open-questions.md) — the decisions
   taken and the ones still open.

## Milestones at a glance

| ID | Repo | What | Depends on |
|----|------|------|------------|
| **BC1** | cirrus | `blueprint.yaml` v2: `overview`, `secrets`, `programme`; `spec.source.tag` deleted | — |
| **BC2** | cirrus | Manifest conformance test — providers exist, paths resolve, secrets and programme match the flows that create them | BC1 |
| **BC3** | lumen, stratus | Port the manifest; one schema, three repos | BC1, BC2 |
| **BC-K1** | orun-cloud | The manifest door: fetched at the registry's tag, strict-parsed, cached; readiness computed from it | BC1 |
| **BC-K2** | orun-cloud | The six-step bootstrap flow, pixel-matched | BC-K1 |
| **BC-K3** | orun-cloud | The build page: live work plan, agent side panel, four status states | BC-K2 |
| **BC-K4** | orun-cloud | The resumable draft and the Overview card — server-side, not browser storage | BC-K2 |
| **BC-K5** | orun-cloud | The bootstrap contract handed to the session, so the agent re-derives nothing | BC-K2, BC-K3 |

Sequencing: **BC1 → BC2 → BC-K1** is the spine; nothing in the console can be
honest before the door serves the manifest. **BC3** may land any time after BC2
and should land before BC-K2 ships to users, so the first operator to pick Lumen
does not meet a half-declared baseline.
