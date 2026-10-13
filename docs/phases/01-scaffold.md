# Phase 01 — scaffold

Births the product repo from `repo-blueprint.yaml`'s `01-scaffold` phase and
connects it to its Orun Cloud workspace. After this phase the repo exists on GitHub, CI runs on every
push, and every later phase can find the product's identity inside the
repo itself.

This is the only phase that takes identity inputs.

## What it lands

The repo ROOT — no deployable components yet:

- `intent.yaml` (workspace AND project written in), `.github/workflows/ci.yml`
  (resume-capable CI: exec-id = run id, conditional `--retry`,
  `max-parallel: 8`, lane pin orun ≥ v2.56.2)
- `tooling/` — ONLY what product builds use: `eslint`, `tsconfig`, `wire`
- `ai/context/` — fresh, product-only agent context: `current.md`,
  `decisions.md`, `open-risks.md`, plus the `operations.md` contract and
  the `deployment.md` placeholder that phase 08 fills
- `.rebrand/values.json` — the identity record every later phase reads
- root files: `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`,
  `turbo.json`, `kiox` locks, `.gitignore`, `README.md` (product-only —
  the forking narrative is stripped), `.vscode/`
- empty discovery roots `apps/ infra/ packages/ tests/` (with `.gitkeep`)
  so `orun new`'s repo-scale gate and the product CI can plan from birth

**What deliberately does NOT land**: this baseline's machinery —
`repo-blueprint.yaml`, `agents/`, `specs/`, `testing/`, `hooks/`,
rebrand/fork/blueprint tooling, baseline working notes, provenance files. A
product carries product files only and its docs never present it as a copy
of anything. `testing/leak.test.sh` derives what this phase would place and
gates the set, so the promise is a test rather than a claim.

## Inputs

| input | example | notes |
|---|---|---|
| `--out` | `$HOME/sourceplane/acme` | a flag, not an input; created if absent |
| `reponame` | `acme` | REQUIRED. Lowercase slug (`^[a-z][a-z0-9-]*$`); repo becomes `<githuborg>/<reponame>` |
| `productname` | `Acme Cloud` | REQUIRED. Display name |
| `productdomain` | `acme.dev` | REQUIRED. Product domain |
| `githuborg` | `sourceplane` | REQUIRED. The org or user the repo is created under |
| `orunWorkspace` | `ws_FGBDTQ8T` | workspace id. Unset, the workspace the build runs in (ORUN_WORKSPACE); with none anywhere, a placeholder that fails loudly rather than silently cross-tenanting |
| `subdomain` | `rahulvarghesepullely` | workers.dev subdomain — keeping the baseline's is supported (worker names are brand-prefixed) |
| `apibaseurl` | `https://api.acme.dev` | CLI default API base; empty derives from `productdomain` |
| `epicSlug` | `infra-baselining` (default) | the epic every phase clubs its task under |
| `domain` | `false` (default) | `true` also runs `07-domain` (the zone must already exist) |

The five that used to be spelled differently on the flow — `repoName`,
`productName`, `productDomain`, `apiBaseUrl`, `workersDevSubdomain` — are
the keys above now, so what an operator types in the console form and what
the blueprint declares are the same words. Every other input has a default;
see `repo-blueprint.yaml`'s `inputs:` block for the full set.

## Steps

1. **place** — the engine writes this phase's modules into `--out`.
2. **the identity chain**, as `post` hooks in order: `git init` → `git add`
   → `tooling/rebrand/rebrand.mjs --values .rebrand/values.json` → the
   intent `workspace:` rewrite → `git add` → `rebrand.mjs --verify` →
   `pnpm install --lockfile-only`. This chain used to be the blueprint's
   global `postInstantiate`, because a one-shot instantiation has only one
   end; in a phased bootstrap the end of `01-scaffold` IS that moment —
   every later phase places into a tree that is already a git repo and
   already branded. It is also why every later phase derives as `drifted`
   rather than `done`.
3. **repo — THE GitHub repo creation step**, an `orun.repo/ensure@v1` hook.
   This is where the repo comes to exist on the git side; no other phase
   touches repo creation. Three states are supported, in order:
   - `origin` already wired locally → push;
   - the repo was **pre-created on GitHub** (org policy may restrict repo
     creation to admins — create it empty, no README) → the action detects
     it, wires `origin`, and pushes;
   - nothing exists anywhere → it is created private under `githuborg` and
     pushed.

   Requires a `GITHUB_TOKEN` with repo-creation (or at least push) rights
   on `githuborg`.
4. **land** — `orun.pr/land@v1`. It runs after **repo** because a landing
   resolves the git remote — which is also why repo creation lives in THIS
   phase and not later: everything after `01-scaffold` assumes a pushed,
   linked repo.

## Verify / done means

The repo is on GitHub, main is pushed, and `orun cloud check` passes. The
first CI run plans zero components and is trivially green. Tracked (the
default): main was seeded with one commit and the scaffold arrived as
PR #1 from `orun/BASE-n-01-scaffold`, bound to the phase's task in the
epic; `track=false` pushes the scaffold straight to main as before.

## Re-running

Idempotent: placement is additive, rebrand is a no-op on branded files, and
`git init` / repo-ensure are guarded. Note that once the tree is branded this
phase derives as **`drifted`**, not `done` — so `--resume` will leave it
alone rather than reverting the product's identity to `cirrus`. Re-place it
deliberately with `--phase 01-scaffold`. If the repo is not allow-listed,
grant it in the console (Git Repos) and re-run.

## Example commands

From the baseline checkout (local mode):

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sourceplane/acme --run-hooks --phase 01-scaffold \
  --set reponame=acme \
  --set productname="Acme Cloud" \
  --set productdomain=acme.dev \
  --set githuborg=sourceplane \
  --set orunWorkspace=ws_ABCD1234 \
  --set subdomain=rahulvarghesepullely
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme --run-hooks --phase 01-scaffold \
  --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
into `--out` and stops, with no `git init`, no rebrand, no repo and no
landing. Add `--status` to derive every phase's state and write nothing at
all.

Pre-created repo: if `sourceplane/acme` already exists on GitHub (empty —
org policy may restrict creation to admins), the repo step detects it,
wires `origin`, and pushes into it instead of creating.

## Next

[`02-foundation`](02-foundation.md).
