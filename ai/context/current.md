# Current Context (compact)

Last updated: 2026-08-04.

## Where this baseline stands

Cirrus is the **Cloudflare-only** baseline, forked from Lumen at `e1fbee6`
and diverged on its data plane. Two things landed on top of the fork:

1. **The data plane is Cloudflare D1.** Supabase Postgres and Cloudflare
   Hyperdrive are gone: `infra/terraform/cloudflare-d1` provisions a database
   per environment, every Worker binds it as `PLATFORM_DB`, the migrations
   are SQLite, and `db-migrate` applies them over D1's REST API.
   `packages/db/src/d1` is the seam — see
   [decisions.md](decisions.md) for what that costs (no interactive
   transaction, SQLite types, no schemas).
2. **The baselining machinery is one blueprint.** `repo-blueprint.yaml`
   declares the phases `01-scaffold … 08-docs`, their hooks, their barriers
   and their narration; `orun new --phase <name>` runs them. The blueprint
   card at `blueprint.yaml` is what the console reads. The phase sequence is
   lumen-standard, with `03-infrastructure` rewritten for D1 and its
   preflight/secrets down to a single provider.

## Ground truth (verify, don't trust — re-derive on boot)

- **What is verified:** the workspace typechecks, lints, and passes its test
  suite, including a suite that applies every migration to a real SQLite
  engine and round-trips repositories through it
  (`tests/db/src/sqlite-schema.test.ts`).
- **What is NOT verified:** no Cirrus product has been bootstrapped end to
  end. Nothing in this repo should claim a live deployment until
  `08-docs` has written one into
  [deployment.md](deployment.md).

## Next

1. Run a full bootstrap into a scratch workspace
   (`testing/provision-workspace.yaml` provisions the throwaway
   prerequisites) and record the real timings.
2. Review the `executor.transaction(...)` call sites individually now that
   rollback is gone.
3. Tag `baseline-v1` once a bootstrap has proven the phases, and point the
   platform's blueprint registry at that tag.
