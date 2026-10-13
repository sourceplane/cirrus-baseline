# Phase 07 — domain (OPTIONAL)

Lands the **custom product domain** (`repo-blueprint.yaml`, phase `07-domain`): DNS +
routing terraform that puts the product on `<productdomain>` instead of
workers.dev.

Skip it entirely until you own the domain — the baseline is fully
functional on workers.dev URLs after phase 05.

## What it does today — read this first

**`cloudflare-domain` ships parked.** Its `component.yaml` declares
`subscribe.environments: []`, so CI plans no lanes for it: the phase lands
the component and its PR, and the convergence after the merge is a run with
nothing in it, which reads green. The domain is not attached. This is the
"a green run that deployed nothing" trap the other phases guard against with
a probe; this phase has no probe to catch it, so its narration says so
instead of claiming the domain resolves.

Wiring it for real means, in the product, restoring the `subscribe` block the
component carries commented out (and finishing the provider-v5 re-import its
comment names), once the zone exists — then landing that as a normal PR.

## Prerequisite (hard)

The product zone (e.g. `acme.dev`) must **already exist in the Cloudflare
account** — created manually in the dashboard (zone creation is an
account-plan operation the platform does not broker). The terraform here
manages records/routes IN the zone, not the zone itself. Without the zone
the apply fails at plan.

## What it lands

`infra/terraform/cloudflare-domain`: the `cloudflare-domain` component
(records, worker routes/custom domains for edge + console per
environment).

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation (a `--values` file beats repeating
`--set`); everything else this phase needs it reads back from the placed
tree. See [the phases README](README.md).

## Steps

1. **place** → **land** → **converge** — the standard contract
   (PR `feat(domain): the custom-domain component`).

The phase carries `when: inputs.domain`, so it is SKIPPED unless
`--set domain=true`. A skipped phase does not block `08-docs`, which
requires `05-edge` rather than this one.

## Verify / done means

The convergence run is green. Then check the product resolves on its own
domain (DNS propagation applies). Re-run
[phase 08](08-docs.md) afterwards so the deployment manifest
records the custom-domain URLs.

## Troubleshooting

- **Plan fails: zone not found** — the zone does not exist in this
  Cloudflare account yet, or the brokered token's account differs from the
  zone's account. Create the zone, re-run.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 07-domain --values ~/acme.values.yaml
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/cirrus
cd cirrus
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 07-domain --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no repo, no landing, no convergence watch and no probe. Add
`--status` to derive every phase's state and write nothing at all.
Re-running a completed phase is always safe (idempotent): the placement is a
no-op, the landing finds nothing, and the `await` hooks re-assert.

Run ONLY after the product zone (e.g. `acme.dev`) exists in the Cloudflare
account — the apply fails at plan without it.
