# Bootstrap timings — what to budget, and where the numbers come from

**Provenance matters here.** Cirrus forked the Lumen baseline and replaced
its data plane, so the numbers below split into two kinds:

- **Inherited (measured on Lumen).** Phases 01, 02, 04, 05, 06 do the same
  work over the same content; their timings carry over. What changed under
  them is where the mechanism lives — a shell layer, then typed actions in
  the orun binary — not what any phase does.
- **Not yet measured on Cirrus.** Phase 03 is a different phase here —
  Cloudflare D1 and KV instead of a managed Postgres project — so Lumen's
  phase-03 number does NOT apply, and no Cirrus bootstrap has been measured
  end to end yet. The estimate below is reasoned from what the phase now
  does, and is labeled as an estimate until a real run replaces it.

## Per-phase wall-clock

| phase | time | provenance | dominated by |
|---|---|---|---|
| 01 scaffold | **~2m** | inherited | blueprint render + rebrand ~1m · repo create + push ~30s · link ~10s |
| 02 foundation | **~5–9m** | inherited | PR verify lanes · main convergence |
| 03 infrastructure | **~3m (estimate)** | **not measured** | terraform apply for `cloudflare-d1` + `cloudflare-kv` (both create in seconds) then `db-migrate` |
| 04 workers | **~21–31m** | inherited | the two landings and their convergences |
| 05 edge | **~5m** | inherited | apply→land→converge→`/health` probes |
| 06 console | **~14–16m** | inherited | console builds are heavy |
| 08 docs | **~1m** | inherited | probe + render + commit |
| tracking (BT) | **seconds per landing (estimate)** | **not measured** | one `orun task list` and at most two creates per landing, one epic + seven milestones up front; the rehearsal (BT6) replaces this row |
| **total** | **~50–65m (estimate)** | | the worker phase dominates |

Phase 03 is where being Cloudflare-only shows up in the clock. On the Lumen
baseline that phase measured ~10–15m and was dominated by managed-Postgres
project creation (5–7m per environment, irreducible from our side). Creating
a D1 database is an API call that returns in seconds, so the phase collapses
to the cost of running a convergence at all.

**Replace the estimate with a measurement.** After the first full Cirrus
bootstrap, take the per-step timestamps from the umbrella's output and edit
this table — an estimate that survives its first real run unchanged is a
document nobody checked.

## Things that shape the total

1. **One convergence per landing.** A phase's `orun.pr/land@v1` merges
   without waiting on PR checks: the phase content comes from the PINNED
   baseline and was verified there, so PR lanes would deploy the fleet a
   second time. The `orun.run/watch@v1` await hook is the gate. Waiting on
   checks remains right for incremental changes on a live product, which is
   what a normal PR does.
2. **Watch GitHub Actions billing.** A full bootstrap is hundreds of runner
   minutes. A tripped spending limit presents as lanes that "fail" with NO
   logs anywhere — the message lives only in the check-run ANNOTATIONS
   (`gh api repos/<o>/<r>/check-runs/<job-id>/annotations`).
3. **Mint `ORUN_TOKEN` per phase** — it is short-lived (~30m). The container
   contract in BOOTSTRAP.md §2 covers this.
4. **A converge that follows a commit touching NO components** plans zero
   lanes and reads "green". The phase's verify step is the real gate; never
   trust a green run without it.

## Inherited defect log

These were found and fixed during Lumen's measured bootstraps. They are
listed so nobody re-hits them — every one is already landed in the shared
flow scripts this baseline carries.

| fix | what broke on a fresh product |
|---|---|
| #50 | `secret://` refs: segment 1 is the WORKSPACE — the repo-slug rebrand rewrote both segments; every resolve failed `Validation failed` |
| #52 | `cloud check` passes without the LOCAL link cache (fresh HOME) — preflight now links unconditionally |
| #53 | the workspace-slug self-heal dirtied the tree before its own clean-tree check |
| #54 | later phases branded fresh baseline content with the product's scaffold-era rebrand copy — the tool now always runs from the pinned baseline |
| #56/#57 | phase 03's PR lanes are structurally red on first boot → `--no-wait` landing |

And what the workspace-scoped (`sk_`) token path surfaced, all fixed:

1. `sk_` tokens see NO memberships list → slug resolution needs
   `orun workspace <ws>` (v2.52.1) — the direct org read.
2. `sk_` tokens cannot write repo links → the intent must declare
   `project:` (the scaffold writes it; preflight self-heals).
3. Intent declares the project SLUG; config-surface and state routes take
   `prj_…` ids → CLI-side slug resolution (v2.52.2 secrets, v2.52.4 run).
   The lane pin in `ci.yml` must be ≥ v2.56.2 (the phase overlay's floor was
   v2.56.0; v2.56.2 is where a branded tree stopped refusing its next phase).
4. Step `timeout:` didn't kill grandchildren — a wedged git held the step's
   pipes past its deadline → process-group kill + WaitDelay (orun v2.52.3).
5. git has NO transfer timeout → `http.lowSpeedLimit/Time` on every flow git.
6. git's credential `store` fires EVERY configured helper (system
   osxkeychain included) → in a keychain-less HOME securityd can raise a
   BLOCKING dialog on the console user's screen, hanging the step until a
   human clicks. Get-only credential helper everywhere.
