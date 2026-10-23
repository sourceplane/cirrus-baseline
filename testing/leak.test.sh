#!/usr/bin/env bash
# THE LEAK GATE — what a product carries, and what stays in the factory
# (saas-bootstrap-engine BE5, Tier 1).
#
# `BOOTSTRAP.md` describes a product as the thing cirrus makes, not a copy of
# cirrus. Until BE5 the `ai-context` module copied the whole of `ai/context/`,
# so every product shipped this repository's planning state — and
# `fork-from-baseline.md`, which opens:
#
#     # Provenance — Cirrus from the Lumen baseline
#
# After rebrand that is a sentence about the CUSTOMER's product, telling them
# it was forked from Lumen at a commit they have never seen. Not a leaked
# secret — a false statement in the product's own voice, in the file an agent
# is pointed at first.
#
# WHAT THIS ASKS, AND WHAT IT CANNOT YET. It asks orun to DERIVE the placement
# — every file every phase would write — and gates that set. Derivation runs no
# hooks, contacts nothing and writes nothing.
#
# It does NOT place the tree and brand it. A whole-blueprint `orun new` cannot
# run today: `requires.phases` is checked for every phase BEFORE the first byte
# is written, so phase 02 asks whether phase 01 is on disk during a run that
# has not written phase 01 yet, and always answers no. Tracked as orun BE-O11.
# When that lands, this file grows the other half — rebrand --verify, and the
# product's own `orun validate` / `orun plan --dry-run` inside the placed tree.
#
# Needs: orun (the pinned version) + python3 with PyYAML. No network, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v orun >/dev/null || { echo "leak.test.sh needs orun on PATH" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "── deriving what every phase would place"
# Inputs come from the fixture, so a new required input fails HERE rather than
# in front of an operator.
sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$root/tests/fixtures/acme.json" <<'PY'
import json, sys
vals = json.load(open(sys.argv[1]))
for k, v in vals.items():
    if k.startswith("_"):
        continue
    print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)
orun new --blueprint "$root/repo-blueprint.yaml" --status --json \
  --out "$scratch/empty" "${sets[@]}" > "$scratch/status.json"

python3 - "$scratch/status.json" "$root" <<'PY'
import json, pathlib, sys

status = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
problems = []
def bad(m): problems.append(m)

# Against an empty output directory every file a phase places is "missing", so
# the union of those lists IS the product's file set.
placed = sorted({f for ph in status["phases"] for f in (ph.get("missing") or [])})
if len(placed) < 500:
    sys.exit(f"only {len(placed)} files derived — the tree is not a product")

# ── the product's context pack, exactly ─────────────────────────────────────
# An exact set, not a prefix. That is the whole point of one module per file:
# a new file in ai/context/ cannot ship without somebody writing a module for
# it and saying so in a diff.
ALLOWED_AI = {"ai/context/deployment.md", "ai/context/operations.md"}
shipped_ai = {p for p in placed if p.startswith("ai/")}
for extra in sorted(shipped_ai - ALLOWED_AI):
    bad(f"{extra} ships to the product and is this repository's own state")
for missing in sorted(ALLOWED_AI - shipped_ai):
    bad(f"{missing} is declared a product file and would not ship")

# ── the factory never ships ────────────────────────────────────────────────
# `.vscode/tasks.json` is this repository's agent loop: it runs agents with
# their sandbox and approvals bypassed against `agents/orchestrator.md` and
# `ai/state.json`, neither of which a product has. `.baseline/` is this tree's
# own identity, the FROM side of every rebrand.
NEVER = ("flows/", "agents/", "tasks/", "specs/", "testing/", "hooks/",
         "docs/phases/", "tooling/rebrand/", "tooling/bootstrap/",
         "tooling/fork/", "tooling/migrations/", ".vscode/tasks.json", ".baseline/",
         "FORKING.md", "BOOTSTRAP.md", "repo-blueprint.yaml", "blueprint.yaml")
for p in placed:
    for never in NEVER:
        if p == never or p.startswith(never):
            bad(f"{p} would ship — it is the factory, not the product")

# ── nor an operator's local secrets and state ─────────────────────────────
# `orun new` snapshots the working tree, so these reach a product only if the
# blueprint's `ignore` misses them. Matched as the ignore list means them: by
# basename at any depth, and `.terraform` as any path segment. Any `.env*`
# counts — a per-environment `.env.production` holds secrets as surely as
# `.env` does.
import fnmatch
LOCAL = (".env*", ".dev.vars", ".dev.vars.*", "*.tfstate", "*.tfstate.backup")
for p in placed:
    segs = p.split("/")
    if ".terraform" in segs[:-1] or any(fnmatch.fnmatchcase(segs[-1], g) for g in LOCAL):
        bad(f"{p} would ship — an operator's local secret or state file, "
            f"which the blueprint's `ignore` must exclude")

# ── and by content: PROVENANCE, which rebrand has no rule for ──────────────
# Deliberately NOT a search for "cirrus". rebrand.mjs rewrites this
# repository's own name into the product's — that is its whole job — so
# flagging it here would mean failing on input rebrand is about to fix, and
# testing rebrand's work in the wrong place against the wrong tree.
#
# What rebrand cannot fix is a sentence about where the baseline CAME FROM.
# `fork-from-baseline.md` opened "Provenance — Cirrus from the Lumen baseline";
# rebrand turns the first name into the product's and leaves the rest standing,
# so the customer is told their product was forked from Lumen. The file no
# longer ships — the set gate above sees to that — and this catches the same
# prose reappearing inside a file that does.
#
# The product's own docs are read from the file their module places them FROM,
# which is not always the same path here: the README, AGENTS.md and the
# deployment placeholder come from `.baseline/product/`, because this
# repository's own README and deployment record are the baseline's.
import posixpath, re
import yaml
bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
source_of = {m["to"]: m["from"] for m in bp.get("modules") or []
             if m.get("from") and m.get("to")}

# What an agent handed this repository reads first. A finished build's prompt
# ends "clone <repo> and start building on it", so these must ship, and must be
# the PRODUCT's.
PRODUCT_DOCS = {"README.md", "AGENTS.md"} | ALLOWED_AI
for missing in sorted(PRODUCT_DOCS - set(placed)):
    bad(f"{missing} would not ship — a product's agent starts there")

PROVENANCE = re.compile(
    r"\blumen\b|\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit)\b",
    re.I,
)
# A placeholder that only some later step fills (the old `OPSFLOWS` clone URL,
# which nothing filled) is a broken instruction in the product's voice.
PLACEHOLDER = re.compile(r"\bOPSFLOWS\b|TBD_08DOCS")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
def ships(target):
    return target in placed or any(p.startswith(target.rstrip("/") + "/") for p in placed)

for rel in sorted(PRODUCT_DOCS & set(placed)):
    src = root / source_of.get(rel, rel)
    if not src.exists():
        bad(f"{rel} is declared a product file and its source {src.relative_to(root)} "
            f"is not in this repository")
        continue
    text = src.read_text(errors="replace")
    for n, line in enumerate(text.splitlines(), 1):
        if PROVENANCE.search(line):
            bad(f"{rel}:{n} tells the product where the BASELINE came from, "
                f"which rebrand cannot rewrite: {line.strip()[:70]}")
        if PLACEHOLDER.search(line):
            bad(f"{rel}:{n} ships a placeholder nothing fills: {line.strip()[:70]}")
    # Every relative link lands on a file the product has. The baseline's own
    # README linked BOOTSTRAP.md, docs/phases/ and specs/ — none of which ship.
    for target in LINK.findall(text):
        if re.match(r"^[a-z][a-z0-9+.-]*:|^#", target):
            continue
        path = posixpath.normpath(posixpath.join(posixpath.dirname(rel), target.split("#")[0]))
        if not ships(path):
            bad(f"{rel} links {target}, which the product does not carry")

if problems:
    print("FAIL: the product would carry the baseline:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(placed)} files derived across every phase")
print(f"   ai/context is exactly {len(ALLOWED_AI)} declared file(s)")
print(f"   none of the {len(NEVER)} factory paths; "
      f"{len(PRODUCT_DOCS)} product docs ship, with no baseline provenance, "
      f"no unfilled placeholder and no link outside the product")
PY

echo "leak.test.sh: ok"
