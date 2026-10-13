#!/usr/bin/env bash
# WHAT A FINISHED BOOTSTRAP MEANS (saas-bootstrap-engine BE6b).
#
# Reads the engine's own event stream — `--progress json`, one
# `bootstrap-event/v1` object per line — and the placed tree, and decides
# whether the rehearsal actually bootstrapped a product.
#
# # Placed, not `done`
#
# `01-scaffold` brands the tree it places, so every phase after it derives as
# `drifted` PERMANENTLY and by design. "Every phase done" is therefore
# unsatisfiable and any resume-until-done loop never terminates — open
# question 12, answered in the plan. What a finished bootstrap means is every
# declared phase PLACED: it reached `done` or it reached `drifted`, and
# neither is `failed` and neither is still `waiting`.
#
# # Against the stream, not a re-derivation
#
# The alternative is re-deriving state from the tree afterwards, which asks a
# different question: whether the files are there NOW, not whether the phases
# ran. A phase that failed and left its files behind passes the second and
# fails this.
#
# bash + python3. No network, no credential — it reads two paths.
set -euo pipefail

events="${1:?usage: assert.sh <events.jsonl> <product-dir>}"
product="${2:?usage: assert.sh <events.jsonl> <product-dir>}"

python3 - "$events" "$product" <<'PY'
import json, pathlib, sys

events_path, product = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
problems = []
def bad(msg): problems.append(msg)

if not events_path.is_file():
    sys.exit(f"FAIL: no event stream at {events_path} — the build produced nothing to assert")

events = []
for n, line in enumerate(events_path.read_text().splitlines(), 1):
    line = line.strip()
    if not line or not line.startswith("{"):
        continue                      # the human summary shares stdout
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError as exc:
        bad(f"event stream line {n} is not JSON: {exc}")

# AN EMPTY STREAM IS A FAILURE, NOT A QUIET SUCCESS. A run without
# --run-hooks emits nothing at all (open question 19), and a rehearsal that
# accepted that would be green having bootstrapped nothing.
if not events:
    sys.exit("FAIL: the event stream is empty. A build with --run-hooks emits one "
             "object per transition; none means no phase ran.")

for e in events:
    if e.get("schema") != "bootstrap-event/v1":
        bad(f"unknown event schema {e.get('schema')!r} — this asserts against v1")
        break

# Last state wins, in seq order: a phase that waited and then finished is done.
by_phase = {}
for e in sorted(events, key=lambda e: e.get("seq", 0)):
    phase = e.get("phase") or ""
    if phase and not e.get("step"):          # phase-level, not hook-level
        by_phase[phase] = e.get("state")

if not by_phase:
    bad("no phase-level events — the stream carried only hook lines")

PLACED = {"done", "drifted"}
for phase, state in sorted(by_phase.items()):
    if state in PLACED:
        continue
    if state == "skipped":
        # Legitimate for a conditional phase. 07-domain is skipped unless the
        # run asked for a domain, and a rehearsal does not.
        continue
    bad(f"phase {phase} ended {state!r} — a finished bootstrap leaves every phase "
        f"placed (done or drifted), and this one is not")

# …AND SOMETHING MUST ACTUALLY HAVE BEEN PLACED.
#
# The loop above passes a stream in which every phase is `skipped`, because a
# skip is legitimate per-phase. A run where they are ALL skipped placed
# nothing at all — which is exactly what a hooks-off `--phase` invocation
# emits, and this assertion accepted one until a real stream was put through
# it. The anchors are the first phase and the last: `01-scaffold` creates the
# repo and `08-docs` records the live deployment, so a bootstrap that reached
# neither did not happen, and one that reached both ran the whole sequence.
for anchor in ("01-scaffold", "08-docs"):
    state = by_phase.get(anchor)
    if state is None:
        bad(f"{anchor} never appears in the stream — a finished bootstrap runs it")
    elif state not in PLACED:
        bad(f"{anchor} ended {state!r} rather than placed. It is an anchor: "
            f"01-scaffold creates the repo and 08-docs records the deployment, "
            f"so a run that skipped either did not bootstrap anything")

# The tree the phases claim to have placed must actually be there. Not a file
# count — a count passes against a tree half of which is the wrong product.
if not product.is_dir():
    bad(f"{product} is not a directory — the build placed nothing")
else:
    for required in ("intent.yaml", ".rebrand/values.json", ".github/workflows/ci.yml"):
        if not (product / required).exists():
            bad(f"the product is missing {required}")

print(f"   {len(events)} events, {len(by_phase)} phases")
for phase, state in sorted(by_phase.items()):
    print(f"   {phase:22} {state}")

if problems:
    print("FAIL: the rehearsal did not bootstrap a product:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)
PY

echo "assert.sh: ok"
