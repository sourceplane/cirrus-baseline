# BOOTSTRAP — fresh product from this baseline, in phases

How to go from **nothing** to a **fully deployed, documented baseline**
(all terraform infra, the 12-worker fleet, api-edge, the console — live on
stage+prod) with ONE provider consent.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. Everything that used to live in a `flows/` shell
layer is now a typed action inside the binary, which is why the version floor
matters and why a phase can be run alone, months later, from a fresh
container.

Target wall-clock: **about half an hour** (it was under an hour; a rehearsal
has yet to measure the new number). Five landings instead of eight, each
pull request checked by `plan` alone because its merge runs the lanes on
main anyway, the worker fleet deployed in two parallel waves instead of in
binding order, and stage and prod deployed side by side until `08-docs`
restores the promotion gate — [docs/phases/README.md](docs/phases/README.md)
has the account. The Cloudflare-only data plane creates in seconds, which is
where this baseline is cheaper than a Postgres-backed one.

## 0. What you need

- GitHub org access (repo creation) and a machine with `git`, `gh`, `node`
  (≥20), `pnpm`, `python3`, and the `orun` CLI **≥ v2.58.11**. That is the
  floor for RUNNING the bootstrap; the product's own `ci.yml` lane pin is a
  separate, lower floor (≥ v2.56.2). v2.56.0 carried the phase overlay (before
  it there is no `--phase` and `hooks.{pre,post,await}` does not parse);
  v2.56.2 let a branded phase satisfy the next one's requirement; v2.58.4
  resolves a milestone name and a rendered bool; v2.58.5 is the first that
  can bootstrap at all — it writes each phase's files on that phase's turn,
  its landing commits, seeds an empty repository and deletes the branch it
  merged, and a convergence watches the commit it landed (`sha:`); and v2.58.6
  is the first whose landing waits for a PR's whole CI run — every phase here
  is a pull request that must go green before it merges; and v2.58.7 checks
  that the workspace's GitHub connection is to the account that owns the
  repository (`githubOwner`), without which no PR is ever seen by the platform;
  and v2.58.8 looks for the wiring secrets on the project's environments,
  where the infrastructure publishes them (`secrets/exists` `environments`);
  v2.58.10 treats a project the bootstrap has not created yet as "not yet"
  rather than a failed preflight, without which every fresh build stops before
  its first phase; and v2.58.11 fills `orunWorkspace` from the workspace the
  build runs in (`from: workspace`), which is the only way a console build has
  of saying it.
- A Cloudflare account (Workers paid plan for the fleet) and its **Account
  API token** (the console's Connect recipe lists the exact permission
  groups). It is the ONLY provider credential this baseline needs — and it
  must be able to mint both the `workers-deploy` and `d1-edit` scopes, i.e.
  its permission groups include D1 Write.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the workspace
  the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (builder/viewer keys can read but
  their secret writes are denied — masked as `not_found`).
- **The repo allow-listed in the workspace** (console → Settings → Git
  repos). This is the ONE console action a workspace-scoped token cannot
  self-heal (`cloud link` is refused for them) — do it up front or
  `02-foundation`'s provider check will stop and ask for it. Everything
  else is headless.

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in dependency order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus

orun new --blueprint repo-blueprint.yaml \
  --out ~/sourceplane/acme --run-hooks --resume \
  --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set githuborg=sourceplane \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repo is
created, nothing is landed, no convergence is watched, and no phase probes
its preconditions. That is deliberate — it is what makes a dry instantiation
of this baseline possible in CI with no workspace and no provider.

`--resume` is safe to re-run from anywhere, including a fresh container with
a fresh `--out`: **phase state is derived from the tree, never stored.** A
phase whose files are all present but differ from the blueprint — which is
every phase after `01-scaffold` brands the tree — derives as `drifted`, and
`--resume` leaves it placed rather than reverting your product's identity to
`cirrus`.

## 1b. Or phase by phase — the same document, at your pace

The phases are `01-scaffold`, `02-foundation` (the packages and the D1/KV
data plane), `04-workers` (the fleet's first wave, bindings stripped),
`05-edge` (the bindings restored, the edge and the console), `07-domain`
(only when `--set domain=true`), `08-docs`. The gaps in the numbering are
phases folded into a neighbour's landing (`03-infrastructure`,
`04-workers-restore`, `06-console`). Each is idempotent, each follows
one contract — **place its modules → land them → watch the convergence →
verify the outcome** — and each carries its own narration. Full guide:
[docs/phases/README.md](docs/phases/README.md), with a detailed page per
phase in that folder.

```bash
# phase 01 takes the identity once:
orun new --blueprint repo-blueprint.yaml --out ~/sourceplane/acme --run-hooks \
  --phase 01-scaffold \
  --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set githuborg=sourceplane \
  --set orunWorkspace=ws_XXXXXXXX --set subdomain=<workers-dev-subdomain>

# every later phase reads identity back from the placed tree — but the
# blueprint's required inputs are still validated, so keep passing them
# (a --values file is easier than repeating --set):
orun new --blueprint repo-blueprint.yaml --out ~/sourceplane/acme --run-hooks \
  --phase 02-foundation --values ~/acme.values.yaml
# … 04 (workers), 05 (bindings, edge, console), 08 (docs);
#    07 (domain) only with domain=true.
```

Three flags shape a run:

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. This is the preview — it parses the document, validates each hook against the action registry, compiles every `when` and every narration template, and does **not** probe. It needs no credential and no network. |
| `--phase <name>` | places exactly that phase. Its `requires.phases` still gates: a predecessor that is `pending` refuses the run and names it. |
| `--until <name>` | places every phase through that one and stops. |

What lands in the product is PRODUCT-ONLY: source, infra, CI, configs, and
its own docs. None of this baseline's machinery (the blueprint, rebrand
tooling, its specs, its own `ai/context/`) ships, and nothing in the product
presents it as a copy of anything. That promise is a test —
`testing/leak.test.sh` derives what every phase *would* place and gates the
set.

The workspace needs its two integrations connected once (GitHub and
Cloudflare). `02-foundation`'s `requires.probe` polls for up to 10
minutes, so the consent can be clicked while it waits:

- **Cloudflare**: paste the Account API token (in-console recipe). If the
  token's permission groups omit D1 Write, the `d1-edit` mint is refused
  (`parent_grant_insufficient`) and `02-foundation` stops with that
  message — re-issue the token with D1 Write, re-connect, and re-run the
  phase. Its three secret hooks are a *reconcile*: keys that exist are kept,
  keys that are missing are re-minted against the ACTIVE connection.

## 2. Headless / container mode (Daytona, CI, any sandbox)

The blueprint's source is this repo itself (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two tokens.
orun pins the checkout by digest into its object store before any module
reads it, so the run is reproducible and provenanced.

```bash
# The whole container contract:
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (scopes below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus

orun new --blueprint repo-blueprint.yaml \
  --out /work/acme --run-hooks --resume --progress json \
  --values /work/acme.values.yaml
```

`--progress` is four renderings of ONE stream — they differ in what they
show, never in what happened. `json` emits the raw event objects, one JSON
object per line, `schema: bootstrap-event/v1` (a hosted runner or a console
build page reads these); `plain` prints the narration alone, one line per
event, for a CI log; `verbose` adds every detail line; `auto` is narration
with the engine's facts under it.

**The stream is hook execution, not placement.** A run WITHOUT `--run-hooks`
emits one `skipped` event per declared-but-unplaced phase and nothing else —
so `--resume --progress json` with hooks off, which places every phase and
skips none, prints no events at all. That is not a broken flag: the events
describe phases starting, waiting, finishing and failing, and with hooks off
none of that happens. If you want to see the stream, you are asking for a
real run. If you want to see the *shape* without one, `--status` derives
every phase's state and is the flag for that.

| requirement | detail |
|---|---|
| image deps | `git`, `gh`, `node` (≥20), `pnpm`, `python3`, `curl`, `orun` ≥ v2.58.11 to run the bootstrap. The product's `ci.yml` lane pin (≥ v2.56.2) is its own floor |
| `ORUN_TOKEN` | orun access token; the typed actions authenticate with it (no login flow) |
| `GITHUB_TOKEN` | fine-grained PAT: **read** on `sourceplane/cirrus` (the clone); on the PRODUCT repo: **contents write** (pushes), **pull-requests write** (landings), **actions read+write** (`orun.run/watch@v1` watches runs and auto-resumes via `gh run rerun`), **checks read**; **repo create** on the org if `01-scaffold` creates the repo (or pre-create it — supported) |
| pinning | the clone's `--branch <tag>` pins EVERYTHING: the blueprint, its modules, and the hooks' scripts all come from that one commit. Use a tag for reproducible bootstraps; `main` for latest |
| workdir | `--out` is the product tree and is stable across phases and re-runs (idempotent). The baseline checkout is `{{ .baseline.dir }}` to every hook |
| classic-token caveat | a CLASSIC PAT or gh OAuth token additionally needs the `workflow` scope to push `.github/workflows/` (hit live); fine-grained PATs need only `contents: write` |
| identity | commits fall back to `bootstrap-bot` when no git identity is configured |

> **Contract change (BE4).** Earlier baselines were bootstrapped with
> `orun workflow run github:sourceplane/cirrus@<ref>//flows/phases/NN/workflow.yaml`.
> There are no per-phase remote references any more, because there are no
> per-phase workflows: one pinned artifact, selected with `--phase <name>`.
> The five inputs were renamed to the manifest's keys in the same change —
> `repoName`→`reponame`, `productName`→`productname`,
> `productDomain`→`productdomain`, `apiBaseUrl`→`apibaseurl`,
> `workersDevSubdomain`→`subdomain` — so what an operator types in the
> console form and what the blueprint declares are now the same words.

## 3. After the baseline is live

- **Custom domain**: create the product zone in Cloudflare, then run
  `--phase 07-domain --set domain=true` (see
  [docs/phases/07-domain.md](docs/phases/07-domain.md)), and re-run
  `--phase 08-docs` so the docs pick up the domain URLs.
- **Runtime secrets** (OAuth client secrets, billing keys, …): seed with
  `orun secrets set <KEY> --org <org> --env <env>`; the next deploy pushes
  them to the workers (`wire-now-seed-later` — nothing blocks on them).
- **Incremental rollouts**: normal PRs — merges to `main` converge
  automatically.

## 4. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag. One cut
from a commit whose tier-3 rehearsal never ran publishes a bootstrap nobody has
watched work, to people who find out an hour in — so the tag is cut by a
workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v25          # from main
gh workflow run tag.yml -f version=baseline-v25 -f ref=<sha>
```

It refuses unless the commit has a **green run of the Rehearsal workflow on
that exact sha**. If it refuses, the fix is to prove the commit rather than to
go around it:

```bash
gh workflow run rehearsal.yml --ref <sha>   # ~60 minutes, tier 3
```

The rule is `testing/tag-gate.sh` — a script, so it can be run before you need
it, and tested (`testing/tag-gate.test.sh`) against a fake API. It distinguishes
three answers on purpose: proven, **unproven** (run the rehearsal), and
**unanswerable** (the API could not be asked, which is not the same thing and
needs a different fix).

### The half no file in this repository can enforce

A workflow cannot refuse a tag push. A tag is created and *then* the event
fires, and GitHub's required status checks apply to branches, not tags. So
there are two layers, and only one of them is a gate:

| | |
|---|---|
| `tag.yml` → `cut` | **The gate.** Verifies, then creates. An unproven tag cannot be cut this way. |
| `tag.yml` → `verify` | **The alarm.** Runs on `push: tags: baseline-v*` and goes red if the commit was never proven. It cannot undo the tag. |

Making the refusal binding needs one repository setting: a **ruleset on tag
`baseline-v*` with "Restrict creations"**, leaving the workflow's token the only
creator. Until that is set, `cut` is the paved road and `verify` is the alarm —
which is written here rather than left implied, because a gate that quietly is
not one is worse than a gate that says what it is.

## Troubleshooting (everything we hit doing this for real)

| Symptom | Cause → fix |
|---|---|
| `02-foundation` waits on connections, then stops | Consent not granted yet — console → Integrations, then re-run the phase (idempotent). The probe is a *wait*, not a failure: a consent nobody has clicked is not a broken build. |
| A phase refuses with `requires: 02-foundation (pending)` | Its predecessor has not been placed into this `--out`. Run that phase, or `--resume`. A predecessor that is `drifted` SATISFIES the requirement — its files are all there. |
| `--resume` prints "leaving 01-scaffold as placed" | Expected after branding. Every file is present but differs from the blueprint, so the phase is `drifted` and re-placing it would revert your product's identity. Re-place one deliberately with `--phase <name>`. |
| Secrets listed `orphaned` | Their connection was revoked/replaced (e.g. OAuth app scopes changed). Re-connect the provider and re-run `--phase 02-foundation`: `orun.integrations/reconcile@v1` re-mints only the missing keys against the ACTIVE connection. |
| Secret WRITE fails `not_found` while listings work | The API key's role is below ADMIN (resource-hiding masks the denial). Re-mint the key with the admin role; the reconcile says so in the error and is idempotent. |
| D1 or KV lane: resource name already taken | The account already has `<repo>-<env>`. Adoption imports it at plan time when it's the *same* product re-bootstrapping; otherwise rename or delete the stray resource. |
| Terraform: resource already exists (10014 etc.) with empty platform state | `adopt.tf` handles this by importing at plan time — present in the d1 and kv roots. Roots without adoption must be state-migrated or the resource deleted. |
| Convergence run fails, lanes look transient | `orun.run/watch@v1` already resumes it ×3 (`gh run rerun --failed` = true resume: exec-id + `--retry`). Re-running the phase re-enters the watch on the same run. |
| Convergence failed AFTER the phase's PR merged; re-running the phase lands nothing and redeploys nothing | Expected on its own: the merge put every file in place, phase state is derived from the tree, and `plan --changed` deploys only what changed. Re-run the phase (`--phase <name>`, `--redo <name>` under `--resume`, or the console's Retry): its `retouch` hook writes `# orun: redeploy <phase> <stamp>` as the last line of each affected `component.yaml`, so the landing has a diff and the phase's components redeploy. If the landing is still empty, the hook did not run (`--run-hooks`) or the contract names no component — `node tooling/bootstrap/retouch.mjs --check …` in the product tree says which. |
| Worker verify lane: missing `WIRING_*` secret | Its terraform upstream hasn't applied (check that lane first) — inside one convergence run the DAG guarantees order; across manual partial runs it does not. `04-workers` guards this with a `requires.probe` on both keys. |
| D1 lane or db-migrate: `Authentication error (10000)` | The lane resolved `CLOUDFLARE_API_TOKEN` (workers-deploy), which cannot touch D1. Both D1 components must bind `CLOUDFLARE_D1_TOKEN`. |
| 01-scaffold parks: `waiting for github for <org> (connected: <account>)` | The workspace's GitHub connection is to a different account than the one the product repository will live under, so the platform would never see its pull requests. Connect the GitHub App installation on `<org>` to the workspace (console → Integrations → GitHub), then `--resume`. |
| CLI login dies with 429 `rate_limited` | Fixed ≥ v2.48.1 (redeem honors Retry-After). Upgrade the CLI. |
| `unknown flag: --phase`, `cannot unmarshal !!map into []scaffold.Hook`, or `orun.run/watch@v1 has no parameter "sha"` | The CLI is below the v2.58.11 floor. This blueprint is not readable by an older one. |
| A fresh build stops before 01-scaffold: `✕ phase "04-workers" precondition "wiring" is not met: … project "<repo>" not found` | The CLI is below v2.58.10, which asks the preflight about the product's project before phase 01 has created it and calls the answer a failure. Upgrade; the probe is then deferred to phase 04. |
| The product's `intent.yaml` says `workspace: ws_SET_ME`, or its secret refs name the repository (`secret://<repo>/…`) | `orunWorkspace` was empty: set it, or run the build in the workspace (ORUN_WORKSPACE) with a CLI ≥ v2.58.11, which fills it from there. |
| `✕ input "productdomain" is required` | Required inputs are validated before anything else, so this names the key nobody typed. All four requireds — `reponame`, `productname`, `productdomain`, `githuborg` — must be set on every invocation, including single-phase ones. |
| Console/edge smoke fails right after the FIRST deploy of a worker | workers.dev route propagation race — the deploy lane's smoke retries with backoff (stack-tectonic ≥ 0.18.2); a convergence resume clears older pins. |
| Terraform lane: "state already locked" by ITS OWN plan | Backend lock-release race — a convergence resume clears it. |
| Environment cannot observe GitHub Actions (gh 403) | `orun.pr/land@v1` and `orun.run/watch@v1` fall back to plain REST automatically. If even REST Actions is blocked, the watch reports it rather than hanging — verify the run out-of-band before the next phase. |
| Many lanes queued, none claiming | Runner-pool starvation — `max-parallel: 8` in ci.yml is deliberate (resolve-herd); patience, or check the run isn't superseded. |

## Architecture invariants this depends on

- **Phase state is derived, never stored.** Nothing in `--out` records which
  phases have run; the engine asks the tree. A stored file would be a cache,
  and it must always be safe to delete — which is what makes a phase runnable
  alone, months later, from a fresh container.
- **The product's CI holds one credential: `GITHUB_TOKEN`.** Provider
  credentials are brokered per run from workspace integrations; terraform
  state lives on the platform (`backend "http"`, run-token auth); terraform
  outputs travel as lease-published job-output secrets. No AWS, no Secrets
  Manager, no long-lived provider tokens on any deploy path. The bootstrap's
  own secret hooks hold no value either: a brokered secret is a pointer at a
  connection and a scope template, minted just-in-time at resolve.

  The baseline's own tier-3 rehearsal lane is the one exception, and it is
  why the account it runs against is not the one anything is deployed to: a
  run that bootstraps a whole product from nothing has to hold the credential
  the first consent would otherwise be clicked for, so it holds one for a
  dedicated rehearsal account that can reach no production resource.

  That token is an **orun-managed secret**, not a GitHub one — declared as
  `secretEnv` on `testing/rehearsal/component.yaml`, resolved lease-bound at
  claim time and redacted from the logs, revocable without a commit. So the
  sentence above stays literally true of GitHub: `GITHUB_TOKEN` is still the
  only credential this repository's CI holds. What is stored is a long-lived
  provider token for an account nothing is deployed to, held by the platform
  rather than by the forge, and the separation of the account — not the
  storage — is what bounds that lane. It never touches a product, and no
  product ever carries it.
- **Resume-capable CI**: exec-id is the GitHub run id (no attempt suffix) and
  every lane passes `--retry` — `gh run rerun --failed` is a true resume.
- **Parked-by-default fleet** at instantiation; the bootstrap un-parks it in
  one push. `cloudflare-domain` is the only component parked by design.
