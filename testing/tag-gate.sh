#!/usr/bin/env bash
# NO `baseline-vN` IS CUT FROM AN UNPROVEN TREE (saas-bootstrap-engine BE6).
#
# A baseline tag is what the platform's registry resolves and what every
# product bootstrapped from this repository is built out of. Cutting one from a
# commit whose tier-3 rehearsal has never run — or ran and failed — publishes a
# bootstrap nobody has watched work, to people who will find out an hour in.
#
# So: this answers one question about one commit.
#
#     Is there a SUCCESSFUL run of the Rehearsal workflow on exactly this sha?
#
# # What this can and cannot enforce
#
# It cannot stop a tag being pushed. A tag is created and THEN the event fires,
# GitHub's required-status-checks apply to branches and not to tags, and no
# workflow can refuse one after the fact. What exists here instead is a pair:
#
#   - `.github/workflows/tag.yml` CUTS tags, and calls this first. Used as
#     intended, an unproven tag cannot be created.
#   - the same workflow also runs on `push: tags: baseline-v*` and calls this
#     again, so a tag created any other way is loudly red within a minute.
#
# Making the refusal BINDING needs one repository setting this file cannot
# make: a ruleset on tag `baseline-v*` with "Restrict creations", leaving the
# workflow's token as the only creator. That is written up in BOOTSTRAP.md
# rather than implied here, because a gate that quietly is not one is worse
# than a gate that says what it is.
#
# # The one thing it deliberately does not check
#
# Whether the rehearsal that passed was a rehearsal worth passing. A commit
# that guts `testing/rehearsal/assert.sh` and goes green is green here too.
# That is review's job, not a shell script's — and the reason `assert.sh`
# carries phase ANCHORS (BE6b) is that a hooks-off run had already passed with
# every phase skipped, which is the same failure one layer down.
#
# # Failing closed
#
# An API call that errors is NOT "no green run" and is NOT "a green run". It is
# "this cannot be proven", which refuses — with a different message, because a
# broken token and an unproven commit need different things done about them.
#
# bash + python3 + curl. Talks to the GitHub API and nothing else; point
# GH_API_BASE at a fake to test it, which is what testing/tag-gate.test.sh does.
set -euo pipefail

GH_API_BASE="${GH_API_BASE:-https://api.github.com}"
WORKFLOW="${WORKFLOW:-rehearsal.yml}"

usage() {
  cat >&2 <<'USAGE'
usage: tag-gate.sh --repo <owner/name> --sha <full-40-char-commit-sha>

  --repo   the repository to ask about, e.g. sourceplane/cirrus.
  --sha    the commit a tag would point at. Full 40 hex characters: an
           abbreviated sha would silently match nothing and read as "unproven".

env: GH_TOKEN (required), GH_API_BASE and WORKFLOW (overrides for testing)

exit 0  a successful Rehearsal run exists for that sha
exit 1  no such run — the commit is unproven
exit 2  bad usage
exit 3  the question could not be answered (API error, bad token)
USAGE
  exit 2
}

repo="" sha=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --sha)  sha="${2:-}";  shift 2 ;;
    -h|--help) usage ;;
    *) echo "tag-gate: unknown argument $1" >&2; usage ;;
  esac
done

[ -n "$repo" ] || { echo "tag-gate: --repo is required" >&2; usage; }
[ -n "$sha" ]  || { echo "tag-gate: --sha is required" >&2; usage; }

# A full sha, not a prefix. `?head_sha=` matches exactly, so an abbreviated one
# matches nothing — which would arrive as "this commit is unproven" and send
# somebody to re-run a rehearsal that had already passed.
case "$sha" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) : ;;
  *) echo "tag-gate: '$sha' is not a lowercase hex commit sha" >&2; exit 2 ;;
esac
if [ "${#sha}" -ne 40 ]; then
  echo "tag-gate: '$sha' is ${#sha} characters; a full 40-character sha is required." >&2
  echo "          An abbreviated sha matches no run and would read as 'unproven'." >&2
  exit 2
fi
[ -n "${GH_TOKEN:-}" ] || { echo "tag-gate: GH_TOKEN is not set" >&2; exit 2; }

url="${GH_API_BASE}/repos/${repo}/actions/workflows/${WORKFLOW}/runs?head_sha=${sha}&per_page=100"
body="$(curl -sS -H "Authorization: Bearer ${GH_TOKEN}" \
             -H "Accept: application/vnd.github+json" "$url")" || {
  echo "tag-gate: could not reach the GitHub API" >&2; exit 3; }

# `status` and `conclusion` are different fields, and the runs API accepts
# conclusion values in its `status=` filter — a quirk that works until it does
# not. So nothing is filtered server-side except the sha, and the verdict is
# read here from `conclusion`, explicitly.
#
# head_sha is re-checked too. The query already filters on it; a gate that
# trusts a filter it did not apply itself is a gate with a silent dependency
# on somebody else's parameter parsing.
VERDICT_PY='
import json, sys
body_text, want_sha, workflow = sys.argv[1:4]
try:
    body = json.loads(body_text)
except json.JSONDecodeError:
    sys.exit(90)
if not isinstance(body, dict) or "workflow_runs" not in body:
    # An error envelope ({"message": "Bad credentials"}) is not an empty list.
    print(body.get("message", "the API returned no workflow_runs") if isinstance(body, dict) else "unreadable")
    sys.exit(91)
green = [
    r for r in body["workflow_runs"]
    if r.get("head_sha") == want_sha
    and r.get("status") == "completed"
    and r.get("conclusion") == "success"
]
if not green:
    # No f-string: this block is a single-quoted shell string, so a backslash
    # escape inside one is both unreadable and a syntax error before 3.12.
    seen = ", ".join(
        str(r.get("status")) + "/" + str(r.get("conclusion")) for r in body["workflow_runs"]
    ) or "none at all"
    print(seen)
    sys.exit(1)
newest = max(green, key=lambda r: r.get("run_number") or 0)
print(newest.get("html_url") or ("run " + str(newest.get("id"))))
'

set +e
out="$(python3 -c "$VERDICT_PY" "$body" "$sha" "$WORKFLOW")"
rc=$?
set -e

case "$rc" in
  0)
    echo "✓ ${sha:0:12} has a green tier-3 rehearsal: $out"
    exit 0
    ;;
  1)
    echo "✕ ${sha:0:12} has NO green tier-3 rehearsal." >&2
    echo "  Runs of ${WORKFLOW} on this commit: $out" >&2
    echo "" >&2
    echo "  A baseline tag is what every product built from this repository" >&2
    echo "  resolves. Run the Rehearsal workflow on this commit and wait for" >&2
    echo "  it to pass:" >&2
    echo "    gh workflow run ${WORKFLOW} --ref ${sha}" >&2
    exit 1
    ;;
  90)
    echo "tag-gate: the GitHub API did not return JSON" >&2
    exit 3
    ;;
  91)
    echo "tag-gate: could not read the workflow runs: $out" >&2
    echo "          This is not 'unproven' — it is 'unanswerable'. Check GH_TOKEN's" >&2
    echo "          scope and that ${WORKFLOW} exists in ${repo}." >&2
    exit 3
    ;;
  *)
    echo "tag-gate: unexpected failure reading the workflow runs (rc=$rc)" >&2
    exit 3
    ;;
esac
