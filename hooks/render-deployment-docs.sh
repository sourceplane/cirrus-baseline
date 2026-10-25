#!/usr/bin/env bash
# Render the product's LIVE-DEPLOYMENT documentation from verified state.
# Called by phase 08-docs as a `run:` hook (and safe to run by hand).
# Idempotent: the
# generated files and the README section are fully re-rendered on every run,
# so re-running after an owner sets the domain, or any redeploy, refreshes them.
#
#   hooks/render-deployment-docs.sh <out> <workspace> <baseline-dir>
#
# What it writes (in <out>):
#   ai/context/deployment.md   — REGENERATED: the deployment manifest (URLs
#                                with live probe results, identity, and the
#                                secrets the product uses BY NAME, with where
#                                each one lives)
#   ai/context/operations.md   — healed from the baseline template if absent
#                                (static operator/agent guide; never rewritten)
#   README.md                  — the section between <!-- 08-docs:begin/end -->
#                                markers is replaced (markers appended if the
#                                README predates them)
#
# No secret VALUE is ever read or written here — secrets are named, not read.
#
# IT ASKS THE PLATFORM NOTHING. The record used to carry the workspace's slug,
# its secrets listed per rung and its integrations — five CLI calls, one after
# another, from the build box — and all of it is what the console shows live
# and this file could only show as it was the day it was written. The record
# keeps what the repository is the right place for: the identity the code
# names, what answered at the URLs, the secrets the product's manifests name
# and where each lives, and where to look for the rest.
set -euo pipefail

out="${1:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"
ws="${2:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"
L="${3:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"

cd "$out"
vals=".rebrand/values.json"
[ -f "$vals" ] || { echo "render-docs: $vals missing — is this a scaffolded product?" >&2; exit 1; }

repo="$(python3 -c "import json;print(json.load(open('$vals'))['reponame'])")"
sub="$(python3 -c "import json;print(json.load(open('$vals'))['subdomain'])")"
domain="$(python3 -c "import json;print(json.load(open('$vals')).get('productdomain',''))")"

# CI lane pin (what version the deploy lanes run).
lanepin="$(sed -n 's/^ *version: *\(v[0-9.]*\) *$/\1/p' .github/workflows/ci.yml 2>/dev/null | head -1)"
[ -n "$lanepin" ] || lanepin="?"

# curl emits the -w format even on connection failure (000) — capture, don't
# append, or a failed probe reads "000000".
probe() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null)" || true; printf '%s' "${c:-000}"; }
badge() { case "$1" in 2*|3*|401|403) echo "LIVE ($1)" ;; 000) echo "unreachable" ;; *) echo "answering $1" ;; esac; }

edge_stage="https://${repo}-api-edge-stage.${sub}.workers.dev"
edge_prod="https://${repo}-api-edge-prod.${sub}.workers.dev"
con_stage="https://${repo}-web-console-next-stage.${sub}.workers.dev"
con_prod="https://${repo}-web-console-next-prod.${sub}.workers.dev"

p_es="$(probe "$edge_stage/health")"; p_ep="$(probe "$edge_prod/health")"
p_cs="$(probe "$con_stage")";        p_cp="$(probe "$con_prod")"

# Custom domain: probe only if one is declared. A product built with no domain
# (the console asks for none) records `"productdomain": ""` in $vals and skips
# this; an owner who sets the domain later sets it there too. An unreachable domain is
# reported as pending, never a failure.
dom_rows=""
if [ -n "$domain" ]; then
  p_da="$(probe "https://api.${domain}/health")"
  p_dc="$(probe "https://app.${domain}")"
  dom_rows="| edge (custom domain) | https://api.${domain}/health | $( [ "$p_da" = 000 ] && echo 'pending (zone not wired yet, or DNS propagating)' || badge "$p_da" ) |
| console (custom domain) | https://app.${domain} | $( [ "$p_dc" = 000 ] && echo 'pending (zone not wired yet, or DNS propagating)' || badge "$p_dc" ) |"
fi

# The Workers' RUNTIME secrets, by name, from the product's own manifests
# (each Worker's `optionalSecretEnv`): wire-now-seed-later, so a Worker
# deploys without them and pushes each one once an owner has seeded it. Read
# from the tree rather than listed here, because adding one is an ordinary
# change in the product, and this file is re-rendered long after it.
runtime_rows="$(python3 -c '
import pathlib, re, sys
repo = sys.argv[1]
keys = {}
for f in sorted(pathlib.Path("apps").glob("*/component.yaml")):
    block = False
    for line in f.read_text().splitlines():
        if re.match(r"^  optionalSecretEnv:\s*$", line):
            block = True
            continue
        if not block or not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^    ([A-Z0-9_]+):", line)
        if not m:
            block = False
            continue
        keys.setdefault(m.group(1), set()).add(f.parent.name)
for k in sorted(keys):
    who = ", ".join(sorted(keys[k]))
    print(f"| `{k}` | `{repo}` per environment, once an owner seeds it | a runtime secret of {who}, optional until then |")
' "$repo")"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Heal the static operator guide from the baseline when the product predates it.
mkdir -p ai/context
if [ ! -f ai/context/operations.md ] && [ -f "$L/ai/context/operations.md" ]; then
  cp "$L/ai/context/operations.md" ai/context/operations.md
  # The template speaks the source repo's name; the product copy must
  # speak the product's. Reuse the rebrand values — after staging the copy,
  # because rebrand.mjs rewrites only what `git ls-files` lists.
  #
  # Nothing else needs filling. The guide used to carry an `OPSFLOWS`
  # placeholder that this step replaced with the baseline's repository (its
  # default the retired `sourceplane/cirrus`); it now names no repository and
  # tells the reader to fetch the phases with `orun baseline new`, which asks
  # the registry where the baseline lives.
  git add ai/context/operations.md >/dev/null 2>&1 || true
  node "$L/tooling/rebrand/rebrand.mjs" --values "$vals" --allow-dirty >/dev/null 2>&1 || true
  echo "render-docs: healed ai/context/operations.md"
fi

cat > ai/context/deployment.md <<EOF
# ${repo} — live deployment manifest

> GENERATED by the docs flow on ${now}; re-run it to refresh (idempotent;
> command in [operations.md](operations.md)). Hand-edits here are
> overwritten. No secret values appear in this file — secrets are named
> only.

## Identity

| | |
|---|---|
| product / project slug | \`${repo}\` |
| Orun workspace | \`${ws}\` |
| declared in | \`intent.yaml\` → \`execution.state.workspace\` / \`.project\` |
| CI lane CLI pin | orun \`${lanepin}\` (\`.github/workflows/ci.yml\`) |

## Public URLs (probed ${now})

| surface | URL | status |
|---|---|---|
| edge API (stage) | ${edge_stage}/health | $(badge "$p_es") |
| edge API (prod) | ${edge_prod}/health | $(badge "$p_ep") |
| console (stage) | ${con_stage} | $(badge "$p_cs") |
| console (prod) | ${con_prod} | $(badge "$p_cp") |
${dom_rows}

A 401/403 on \`/health\` still counts as deployed (alive but unauthorized);
000/5xx does not. The \`dev\` environment is verify-only by design — no
deployed URLs.

## Environments

- \`stage\` and \`prod\` are fully provisioned (D1 database, idempotency KV,
  migrations applied) and serve the URLs above.
- \`dev\` is verify-only: plan/verify lanes run, nothing is deployed.

## Secrets (names only)

| secret | where | what it is |
|---|---|---|
| \`CLOUDFLARE_API_TOKEN\` | the workspace | BROKERED from its Cloudflare connection (\`workers-deploy\`): deploys the Workers and applies the KV namespace |
| \`CLOUDFLARE_D1_TOKEN\` | the workspace | BROKERED (\`d1-edit\`): applies the D1 database and runs its migrations — the deploy token cannot touch D1 |
| \`CLOUDFLARE_ACCOUNT_ID\` | the workspace | the connection's account id — a fact, not a credential |
| \`WIRING_CLOUDFLARE_D1\` | \`${repo}\` on stage and on prod | written by the D1 root's apply: the database's id and name, read by the migrations and by every Worker that binds it — not a credential |
| \`WIRING_CLOUDFLARE_KV\` | \`${repo}\` on stage and on prod | written by the KV root's apply: the edge's idempotency namespace, read by api-edge — not a credential |
${runtime_rows}

Brokered secrets are minted per run, so no long-lived value is at rest. What
the workspace holds right now (every secret by name, and its integrations
and their health) is on the console's Secrets and Integrations pages for
\`${ws}\`.

## How this deployment changes

Merges to \`main\` converge automatically: CI plans changed components and
runs each lane via \`orun run --remote-state\` against the workspace above.
See [operations.md](operations.md) for the full operating contract
(convergence, resumes, secrets, verification, troubleshooting).
EOF
echo "render-docs: wrote ai/context/deployment.md"

# README section between markers (append the section if the README predates it).
python3 - "$repo" <<'PY'
import re, sys
repo = sys.argv[1]
begin, end = "<!-- 08-docs:begin -->", "<!-- 08-docs:end -->"
body = f"""{begin}
This product is **live**. Verified URLs, identity, and the secrets it
uses are recorded in
[ai/context/deployment.md](ai/context/deployment.md) (regenerated by the
docs flow — command in the operating contract); how it deploys and how to
operate it: [ai/context/operations.md](ai/context/operations.md).
{end}"""
s = open("README.md").read()
if begin in s and end in s:
    s = re.sub(re.escape(begin) + r".*?" + re.escape(end), body, s, count=1, flags=re.S)
else:
    # READMEs that predate the markers get the section right after the title.
    lines = s.splitlines(keepends=True)
    insert_at = 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1
    section = f"\n## Live deployment\n\n{body}\n"
    lines.insert(insert_at, section)
    s = "".join(lines)
open("README.md", "w").write(s)
print("render-docs: README live-deployment section rendered")
PY

# The contract for verify: no placeholder tokens survive a render.
if grep -rn "TBD_08DOCS" ai/context README.md 2>/dev/null | grep -v Binary; then
  echo "render-docs: placeholder tokens remain (above)" >&2
  exit 1
fi
echo "render-docs: done"
