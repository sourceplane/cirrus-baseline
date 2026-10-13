#!/usr/bin/env bash
# WHAT THE REHEARSAL ACTUALLY COST (saas-bootstrap-engine BE6b).
#
# Turns the event stream into the table `docs/phases/TIMINGS.md` has been
# asking for since it was written: that file labels every number as an
# inherited measurement or a Cirrus ESTIMATE, and says an estimate that
# survives its first real run unchanged is a document nobody checked.
#
# This emits measurements. Promoting them into TIMINGS.md is a commit a
# person makes from a green run — deliberately not automatic, because a
# number that writes itself into a document is a number nobody read.
#
# bash + python3. Reads one path.
set -euo pipefail
events="${1:?usage: timings.sh <events.jsonl>}"

python3 - "$events" <<'PY'
import json, pathlib, sys
from datetime import datetime

path = pathlib.Path(sys.argv[1])
events = []
for line in path.read_text().splitlines() if path.is_file() else []:
    line = line.strip()
    if line.startswith("{"):
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass

if not events:
    sys.exit("no events — nothing to measure")

def at(e):
    raw = (e.get("at") or "").replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None

# started → the next terminal state for the same phase, in seq order.
spans, open_at = {}, {}
for e in sorted(events, key=lambda e: e.get("seq", 0)):
    phase, state, when = e.get("phase") or "", e.get("state"), at(e)
    if not phase or e.get("step") or when is None:
        continue
    if state == "started":
        open_at[phase] = when
    elif state in ("done", "drifted", "failed", "skipped") and phase in open_at:
        spans[phase] = (when - open_at.pop(phase)).total_seconds()

def human(sec):
    m, s = divmod(int(sec), 60)
    return f"{m}m{s:02d}s" if m else f"{s}s"

print("| phase | measured |")
print("|---|---|")
total = 0.0
for phase in sorted(spans):
    total += spans[phase]
    print(f"| `{phase}` | {human(spans[phase])} |")
print(f"| **total** | **{human(total)}** |")

# A phase that started and never reached a terminal state is the interesting
# one: it is where the rehearsal was when it stopped.
for phase in sorted(open_at):
    print(f"\n> `{phase}` started and never finished — this is where the run stopped.")
PY
