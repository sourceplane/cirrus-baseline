# saas-baseline-tracking — Risks & Open Questions

Live register. Remove entries when resolved; record the decision in
`IMPLEMENTATION-STATUS.md`.

## ⛔ Human-input gates (do NOT auto-pick)

| Item | Blocking decision | Unblock signal |
|------|-------------------|----------------|
| **The orun release and the flows' floor** | BT1 and BT2 shell to `orun task epic …`, `orun task create --epic …` and `orun pr open --branch-slug …`, which are orun's BT-O1/O2/O4 — not yet in any release. The flows pin `orun ≥ v2.52.6` today (`BOOTSTRAP.md`, `flows/AGENT-PROMPT.md`, `BASELINE-TASK.md`); the sandbox installs latest. Somebody names the release and the floor moves in the same week; until then `track.sh` degrades to "untracked" on the version probe. | A tagged orun release whose notes name `orun task epic`; the floor bump merged here. |
| **The sandbox MCP** | The sandbox agent's `orun mcp serve` embeds a 27-tool vendored manifest — no task tools at all (the plane is at 33). BT5's Step 1b (lay out the programme over MCP) needs orun's BT-O3; the brief skips the step when the tools are absent and the umbrella's `programme` step creates the same objects. | `orun mcp tools` in a sandbox lists `epic_create`. |
| **`task.write` for the run's principal** | Owner/admin/builder roles carry `task.write`; the bootstrap door lends admin for the session, and the operator runbook requires an admin API key. A viewer/builder-below-admin key would land untracked. Decide whether an untracked headless bootstrap is a warning (current lean) or a failure. | Decision recorded; `track.sh`'s refusal line names the role to grant. |

## Open design questions

| Item | Question | Current lean |
|------|----------|--------------|
| Epic slug per workspace | `infra-baselining` collides when a workspace bootstraps a second product. Adopt-by-slug would then club the second product's phases under the first product's epic. | Default `infra-baselining`; the umbrella checks the adopted epic's description names this repo and otherwise uses `infra-baselining-<reponame>` and says so. `--set epicslug=` always wins. |
| Key prefix | `BASE` reads well in a branch (`orun/BASE-3-03-infrastructure`) and leaves room for product work to mint `TSK`/`WEB` keys later. Alternative: derive from the repo name. | `BASE`, fixed — the sequence is per (workspace, prefix), so it is stable across re-runs and across products in one workspace. |
| Gates on the contract | `gates: []` lets the merge alone finish a task, which is honest for phases whose real gate is the *main* convergence run the flow watches (not a PR check). Phase 07 (`land-pr.sh` without `--no-wait`) does gate on PR checks; should its task declare them? | `[]` everywhere in BT3; revisit once `scm.check.completed` observations name the checks the plane can see on the PR head. |
| Phase 01's initial commit | `gh repo create --add-readme` adds a GitHub-templated README that the scaffold overwrites; a pre-created empty repo needs one bootstrap commit instead. Is a one-file initial commit acceptable history for a product repo? | Yes: one commit, `chore: initial commit`, replaced in `#1`. The alternative (keep the direct push, leave BASE-1 forever at `ready`) misreports the bootstrap's first and largest landing. |
| Where the agent reports | The brief's updates are chat; the rollup is a read. Should the agent also push a doc onto the epic (`PUT …/tasks/epics/<ref>/docs/<slug>`) with the completion report so it lives beside the tasks? | Yes, in BT5 as the last step — the deployment manifest (`ai/context/deployment.md`) is exactly the doc the epic should carry. Not blocking. |
| REST fallback | Should `track.sh` carry a `curl` path for binaries that predate BT-O1/O2, so tracking works before the floor moves? | No. One client (decision 4). A bootstrap on an old binary lands untracked and says so; the fix is the upgrade the message names, not a second client to maintain. |

## Standing risks

- **Ambiguity does not bind.** If a landing's PR body ever quotes a
  *different* task key on a `Task:` line (a copied body), the plane binds
  the PR to nothing and names the disagreement. `land-pr.sh` writes the
  trailer itself from the same variable that names the branch; callers
  must not pass a body that already carries one.
- **Observation lag.** The tasks-worker drains `scm.*` on a cron; a
  verdict read seconds after a merge may still say `in_review`. The
  umbrella's verify reads the rollup *after* the docs phase, minutes
  later, and treats a not-yet-`done` task as a warning with the
  observation ids it did see, never a hard failure.
- **The integration is the eye.** Binding needs the product repo's pushes
  to reach the workspace's event log — the same GitHub integration
  preflight already gates on. A repo linked after its first landings will
  have missed those observations; there is no backfill.
- **Deferred workflows.** When the push token lacks the Workflows grant,
  the `.github/workflows` follow-up push carries the task key only as a
  commit trailer (no PR), so BASE-1's evidence is the scaffold PR alone.
  Accepted: the scaffold *is* the landing; CI arriving later is the
  operator action the brief already names.
