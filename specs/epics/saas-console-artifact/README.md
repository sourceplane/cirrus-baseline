# Epic: saas-console-artifact (CA) — build the console once, deploy it anywhere

**The console is the slowest job in a bootstrap, and it is rebuilt from cold
for every environment of every product.** In the v13 bootstrap, phase 05 went
green 8m22s into its deploy run: the console waited for the edge (~1.5m), then
built Next.js from nothing (~4–5m). It builds three times, once per
environment, because `NEXT_PUBLIC_DEPLOY_ENV` is compiled in, and every
product builds its own because the product's name, workers.dev subdomain and
API URL are compiled in too.

None of that has to be in the build. CA moves it to the Worker's runtime
`vars`, so one build of a baseline tag serves every environment of every
product made from it, then publishes that build with the tag and lets a
bootstrap deploy it instead of building.

## Status

| Field | Value |
|-------|-------|
| Status | **CA1 done (#14) · CA2 done (#15) · CA3 + CA4 done (#16, #18) — first artifact: baseline-v17 · CA5 open** |
| Owner(s) | `apps/web-console-next` (runtime config), `.github/workflows/tag.yml` (publish), `repo-blueprint.yaml` 05 (consume) |
| Target | phase 05 deploy run ~8m → ~3–4m; URLs live ~5m earlier |

## Milestones

| | What | Done when |
|---|---|---|
| **CA1** | **Runtime identity.** Product name, workers.dev subdomain, API worker prefix, storage prefix, sales email and deploy environment are read per request from the Worker's `vars` (OpenNext copies string vars into `process.env`), falling back to today's compiled-in values. `wrangler.jsonc` declares them, so the rebrand sets a product's. | A build made with one identity serves another's when only `vars` differ. Behaviour unchanged with no vars. |
| CA2 | **One build per commit.** The deploy environment comes from `CONSOLE_DEPLOY_ENV`, else the `-<env>` the console Worker's workers.dev host carries, instead of a compiled-in `NEXT_PUBLIC_DEPLOY_ENV`; the component stops setting it. (The shared composition still builds once per environment job; the builds are now identical, which is what CA3 and CA4 need.) | A build with no deploy env serves stage on the stage host and prod on the prod host. |
| CA3 | **Publish with the tag.** `tag.yml`'s `publish-console` job builds the console at the tagged commit and uploads `web-console-next-<source-hash>.tar.gz` and its `.sha256` to the rolling `console-artifacts` release (`publish_only` re-runs it for an existing tag). Content-addressed by a hash of the sources that produce the build (`apps/web-console-next/scripts/console-artifact.mjs`), so a bootstrap finds it from the baseline's files alone, and an artifact can only match the exact code it was built from. | Every new tag's console sources have an asset. |
| CA4 | **Deploy, don't build, while the product's console is the baseline's.** Phase 05 pins the baseline's artifact into the product (`console-artifact.pin.json`: URL, sha256, the product's own branded source hash). The component's build command fetches and verifies it while the product's sources still hash to the pin, and builds from source once they don't; a digest mismatch fails. No artifact, no pin: the product builds as before. The rebrand never rewrites the pin. | A bootstrap's 05 shows no Next.js build. |
| CA5 | **Measure.** A real bootstrap's phase timings before and after (rehearsals now run from a separate orchestration repository, #13), promoted into `docs/phases/TIMINGS.md`. | Measured, not estimated. |

## Decisions

- **Defaults stay in the source.** `src/lib/app-config.ts` keeps today's
  literals as the fallback, so the rebrand keeps working and a deploy without
  `vars` behaves exactly as before. The `vars` win when present.
- **Runtime names are not `NEXT_PUBLIC_*`.** Next inlines `NEXT_PUBLIC_*` at
  build time; the runtime keys are `CONSOLE_*` and read on the server only.
  The root layout (already `force-dynamic`) resolves them per request and
  hands them to the client through a provider.
- **The artifact serves only the first deploy.** Provenance gap of one deploy:
  the product runs baseline-built code until its first own push, pinned by
  digest to the baseline tag.
- **`SOLO_MODE` stays a build flag.** It is a property of the baseline, not of
  a product, so every product from one tag shares it.
- **The artifact is the bundled worker, not OpenNext's raw output.** `.open-next`
  `require()`s files by absolute build-machine path, which `wrangler deploy`
  resolves when it bundles, so the raw output only deploys on the machine that
  built it. `pack` bundles there (`wrangler deploy --dry-run --outdir`) and
  ships the self-contained `worker.js` plus `assets` (#18; 9.0 → 2.9 MB). The
  first v17 asset had the raw form and was replaced with `publish_only` +
  `replace` before anything used it.

## Verified (v17)

A product placed from `baseline-v17` and rebranded to `acme-cloud` pinned
`web-console-next-8c0e9568….tar.gz` from the live `console-artifacts` release,
its build command downloaded and verified it (no build), and the result,
served from the product's own directory with no build tree reachable,
answered on the stage and prod hosts as "acme-cloud Console", locked to each
environment, calling only that environment's api-edge.

