# saas-bootstrap-console — Pixel parity

Status: **Normative** for anything visual in BC-K2, BC-K3 and BC-K4. Where this
document and prose elsewhere disagree, this wins.

## The reference

[**Baseline Bootstrap Flow**](https://claude.ai/code/artifact/8201dc71-2239-4fa5-9933-1a35f2d5f19d)
— an interactive artifact, not a picture. It runs the real state machine: pick a
baseline and the steps change shape; leave mid-flow and the Overview card
appears; start the build and the work plan runs. Read it by *using* it, and
treat its four "Preview state" buttons on the build page as the four states to
implement, not as a demo affordance to copy.

Three things in the reference are **scaffolding, not design**, and must not be
ported:

- the **Baseline** picker in the top bar (the real console arrives with a
  baseline already chosen),
- the **Preview state** switcher on the build page,
- the **Card / Banner / Both** switcher on the Overview — pick one treatment per
  the decision in `risks-and-open-questions.md` and ship that.

## Tokens — already ours

The reference was built against this repo's console tokens, so parity is a
matter of *using* them rather than matching hexes. Everything below already
exists in `apps/web-console-next/src/styles/globals.css`.

| Reference name | Token | Light | Dark |
|---|---|---|---|
| ground | `--background` | `#FAFAFA` | `0 0% 7%` |
| card | `--card` | `#FFFFFF` | `0 0% 9%` |
| ink | `--foreground` | `#171717` | `0 0% 94%` |
| muted | `--muted-foreground` | `#737373` | `0 0% 60%` |
| border | `--border` | `#E5E5E5` | `0 0% 17%` |
| success | `--success` + `--success-soft` / `--success-border` | `#3A8159` / `#E7F3EC` / `#D5E5DA` | per the dark block |
| warning | `--warning` + `--warning-wash-soft` / `--warning-soft-border` | `#9A7B2D` / `#F7EFDC` / `#EBDDBB` | per the dark block |
| destructive | `--destructive` + `--destructive-soft` | `#C94A44` / `#FBEBEA` | per the dark block |

Type: `--font-sans` (Hanken Grotesk) throughout; `--font-mono` (IBM Plex Mono)
for identifiers only — secret keys, `owner/repo@tag`, manifest paths, branch
names, the contract JSON. Mono is a signal that a string is a name the machine
uses, so it must not leak onto prose.

Radii: cards `12px` (`--radius`), controls `8px`, rows `11px`. The `11px` row
radius is deliberate and already in use in `flow-parts.tsx`; keep it.

### Where the reference is off the console's type ladder — the ladder wins

Sizes are the one place the reference drifted from the console it was drawn
against. `web-console-next` has a **nine-rung ladder** — 12 / 12.5 / 13 / 13.5
/ 14 / 15 / 16 / 28 / 32 — with a test that fails the build on anything else
(`tests/web-console-next/src/type-ladder.test.ts`), and two further rules:
machine text (mono) stays at 12–13px, in one weight.

Three reference values fall outside it, and BC-K2 shipped the ladder's:

| Reference | Shipped | Why |
|---|---|---|
| rail mark `11px` | `12px` | the ladder's floor |
| eyebrow `10.5px` | the console's `.kicker` | one eyebrow, defined once, not a local rule per surface |
| mono chips `11.5px` | `12px` | machine text is held to 12–13px |

A secret key was also drawn bold-mono; shipped in a single weight, because the
ladder holds machine text to one register — being mono is already the
distinction.

This is the rule for anything else that disagrees: **the ladder is the living
system and it is enforced; the reference is a drawing.** Everything else in the
tables above is matched as written.

## Measurements

| Element | Value |
|---|---|
| Shell | `max-width: 1080px`, side padding `20px` |
| Step rail | `252px` column, `20px` gap to the panel; sticky at `top: 16px` |
| Rail item | `9px 10px` padding, `20px` mark, `11px` gap, `4px` between items |
| Rail connector | `1.5px`, from `top: 31px` to `bottom: -5px`, `left: 19px` |
| Panel | head `18px 20px 0`, body `16px 20px 20px` with `12px` gap, foot `13px 20px` on `--muted` |
| Row | `11px 13px`, `12px` gap, `32px` provider tile |
| Build panes | `minmax(0,1fr) 340px`, `16px` gap; agent panel sticky, `max-height: 560px` |
| Phase row | `11px 14px`, `19px` mark, `12px` gap |
| Type scale | page title `21px/700`, panel title `16px/650`, row title `13px/600`, body `13px`, sub `12px`, eyebrow `10.5px/600` at `.08em` uppercase |

Breakpoints: the rail goes horizontal and scrolls at `≤820px`; the build panes
stack at `≤900px`. Both are already in the reference's CSS.

## State rules

These are the rules that make the surface honest. Each exists because its
opposite was tried and was wrong.

1. **The meter counts gates, not steps.** Only the repo and the providers can
   block a build, so the meter reads `n / 2` even though the flow has six steps.
   A meter over six would imply the previews can block, which they cannot.
2. **A preview step takes no input and says so twice** — a `Preview` badge in the
   panel head, and rows on a filled, dashed surface with no controls. Verify
   whether both are needed once it is in the real console; the reference ships
   both deliberately so the choice can be made from the built thing.
3. **A blocked phase does not spin.** During `ACTION REQUIRED` the current phase
   shows an amber mark and *waiting on you* — never a spinner and never the word
   "running". A spinner that does not mean progress teaches people to ignore
   spinners.
4. **Elapsed, never percent.** `21:37 elapsed of ~60 min`, sourced from
   `bootstrap.expectedMinutes`. A percentage on an agent build is a guess
   wearing a fact's clothes.
5. **One thing shouts.** Of the four states only `ACTION REQUIRED` gets the
   warning wash, the lift shadow and the dimmed plan behind it. Running is
   deliberately quiet and says *nothing needs you right now*, which is the most
   useful sentence in a forty-minute stretch.
6. **A finished phase carries its PR.** The number is the receipt, and it is the
   thing people click. Sourced from BT's landing, not synthesised.

## The four build states

| State | Source | Strip | Plan row | Agent dot |
|---|---|---|---|---|
| Running | `UPDATE:` | quiet, card ground, "nothing needs you right now" | spinner + `running` | green |
| Needs you | `ACTION REQUIRED:` | warning wash + lift, the ask verbatim, two actions, plan dimmed | amber mark + `waiting on you` | amber |
| Failed | `FAILED:` | destructive, the failure and why it stopped, retry offered | red mark + `stopped` | red |
| Done | `DONE` | success, counts, and the `verify.urls` from the manifest | all done | green |

The four map exactly to the line kinds the agent brief already emits
(`flows/agent/BASELINE-TASK.md` §3), so the console renders a stream it does not
have to interpret.

## Accessibility floor

Focus visible on every control (`2px` ring, `2px` offset); the rail is a list of
buttons with `aria-current="step"`; the meter carries `role="progressbar"`;
`prefers-reduced-motion` stops the spinner and every transition; both themes
carry their own token set, and no colour is defined only inside a media query.
