# saas-bootstrap-console — Risks and open questions

Status: Decisions taken, with their reasons, and the questions still open.

## Decisions taken

| Decision | Why |
|---|---|
| **Secrets and programme are previews, never forms.** | Both already have owners that are better than a form: `create-secrets.sh` mints from connections so no credential is typed, and `track.sh` is idempotent by identity. A console that created either would add a second writer for one fact and a worse security posture. |
| **`spec.source.tag` is deleted, not corrected.** | A file fetched at a tag cannot name its own version without duplicating the registry. It read `baseline-v1` against a live `baseline-v4` for three releases — the field is not fixable, only removable. |
| **The registry's `requires` column becomes derived.** | Same fact in two places is the failure this epic exists to end. The manifest authors it; the sync caches it so list endpoints stay cheap. |
| **The meter counts two gates, not six steps.** | Only the repo and the providers can block a build. A meter over six would imply the previews gate, which they do not. |
| **Elapsed time, never a percentage.** | A percentage on an agent build is invented. Elapsed against `expectedMinutes` is a fact, and reassures just as well. |
| **A phase blocked on a human shows "waiting on you", not a spinner.** | A spinner that does not mean progress teaches people to distrust spinners everywhere else in the console. |
| **The draft lives on the workspace, not in `localStorage`.** | The reference uses browser storage because it is a single page. A half-finished bootstrap must survive a new laptop; anything less makes "come back later" a lie. |
| **No generic `steps:` renderer.** | Each step needs bespoke UI — an OAuth popup, a repo picker, a read-only key list. A generic renderer collapses into a switch on step kind with an extra layer of indirection. Rated and rejected during design. |

## Open questions

| # | Question | Leaning |
|---|---|---|
| 1 | **Card or banner on the Overview?** The reference ships both behind a switch so the choice can be made from the built thing. | The **card**. It carries the step chips, which answer "how much is left?" without a click; the banner is one line and easy to scroll past. Revisit if the Overview turns out dense. |
| 2 | **Preview badge *and* dashed rows — is one enough?** | Ship both, then remove one after looking at the real console. Belt-and-braces is cheap now and hard to add later. |
| 3 | **Where does tier/price belong?** Today the tier pill sits in the flow header. The "What you get" step is the natural home for what it *costs*. | Move it into step 1 when a paid baseline needs a clearer moment; leave it in the header until then. |
| 4 | **Does the build page own the session, or link to it?** The reference embeds a side panel. | Embed. A build the operator cannot answer from is a build they will miss an `ACTION REQUIRED` on. |
| 5 | **What happens to a draft whose baseline has been retired or re-tagged mid-flow?** | Unresolved. A retired baseline should refuse to start with a clear line; a re-tagged one probably just re-reads the manifest. Needs a decision before BC-K4. |
| 6 | **Should the flow show the agent's first question before the build starts?** The `askedBy: agent` inputs are known at review time. | Show them as "the agent will ask for these", which the reference does. Collecting them in the console would contradict `askedBy`. |

## Risks

| Risk | Mitigation |
|---|---|
| **`tests/flows` does not run in CI.** The lane dies at the workspace OIDC exchange before any test body runs; lumen's green lane runs four setup steps and no tests. A conformance test that cannot fail a PR is a comment. | BC2 fixes the lane or states plainly that its guard is local-only. Do not let BC2 close on a suite that cannot go red. |
| **Account-owned baselines make the manifest untrusted input.** It would drive privileged UI and name broker templates. | Strict schema, provider allowlist from the served registry, template allowlist from the broker. Refuse with a line number; never sanitise and continue. |
| **The manifest and the flows drift the way the tag did.** | BC2 checks the manifest against the *scripts that do the work*, not against a copy of itself. A drift test that compares a file to another file catches nothing. |
| **Pixel parity decays after the first ship.** | `pixel-parity.md` is normative and cites tokens rather than hexes, so the console's own theme carries it forward. Anything that needs a literal colour is a bug in the token set. |
| **Six steps feels longer than three.** | Two of the six take no input and exist to be read; the meter says `n / 2` precisely so the flow does not *feel* six long. Watch the first live bootstraps for abandonment at step 1. |
