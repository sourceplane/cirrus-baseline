#!/usr/bin/env bash
# THE TAG GATE REFUSES AN UNPROVEN COMMIT, AND SAYS WHICH KIND OF NO IT MEANS
# (saas-bootstrap-engine BE6).
#
# `testing/tag-gate.sh` decides whether a `baseline-vN` may be cut from a
# commit. Three answers have to stay distinct, because they need three
# different things done about them:
#
#   yes        — a green Rehearsal run exists for exactly this sha
#   unproven   — it does not; run the rehearsal          (exit 1)
#   unanswerable — the question could not be asked       (exit 3)
#
# The third is the one a gate gets wrong. An API error that reads as "unproven"
# sends somebody to re-run a rehearsal that already passed; an API error that
# reads as "proven" cuts the tag this whole file exists to stop.
#
# The API is a fake: a local HTTP server serving the workflow-runs endpoint.
# bash + python3. No network, no credential, no orun.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

echo "── the tag gate: what it lets through, and what it refuses"

problems=()
bad() { problems+=("$1"); }

SHA="aa11bb22cc33dd44ee55ff6677889900aabbccdd"
OTHER="00ffeeddccbbaa99887766554433221100ffeedd"

# ── the fake GitHub API ─────────────────────────────────────────────────────
# One repository, several shas, each with a different run history. The path
# carries which case to serve so one server covers them all.
fake_port_file="$(mktemp)"
python3 - "$fake_port_file" <<'FAKE' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

port_path = sys.argv[1]
SHA   = "aa11bb22cc33dd44ee55ff6677889900aabbccdd"
OTHER = "00ffeeddccbbaa99887766554433221100ffeedd"

def run(sha, status, conclusion, number=1):
    return {
        "id": 1000 + number, "run_number": number, "head_sha": sha,
        "status": status, "conclusion": conclusion,
        "html_url": "https://github.com/acme/x/actions/runs/%d" % (1000 + number),
    }

# Keyed by the OWNER segment, so each case gets its own world.
CASES = {
    # A green run on the sha. The tag may be cut.
    "green":      [run(SHA, "completed", "success", 7)],
    # Ran, and failed. The commit is unproven.
    "failed":     [run(SHA, "completed", "failure", 7)],
    # Still running. Not yet proven — `in_progress` is not `success`.
    "running":    [run(SHA, "in_progress", None, 7)],
    # Cancelled, which is a conclusion that is not success.
    "cancelled":  [run(SHA, "completed", "cancelled", 7)],
    # Never ran at all.
    "never":      [],
    # THE TRAP: a green run, on a DIFFERENT commit, returned anyway. A gate
    # that trusted the server-side `head_sha` filter it did not apply itself
    # would cut a tag from an unproven tree.
    "othersha":   [run(OTHER, "completed", "success", 7)],
    # A failure and then a pass: the newest green one counts.
    "recovered":  [run(SHA, "completed", "failure", 6), run(SHA, "completed", "success", 7)],
}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body, code=200):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def do_GET(self):
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]
        case = parts[1] if len(parts) > 1 else ""
        if case == "badcreds":
            # An error ENVELOPE, with a 200-shaped body. This is the case that
            # must not read as "no runs".
            return self._send({"message": "Bad credentials",
                               "documentation_url": "https://docs.github.com"})
        if case == "garbage":
            raw = b"<html>502 Bad Gateway</html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        runs = CASES.get(case)
        if runs is None:
            return self._send({"message": "Not Found"}, 404)
        # Deliberately NOT filtering by head_sha, even though the real API
        # does: the point of the `othersha` case is that the script must not
        # depend on a filter it did not apply itself.
        _ = parse_qs(urlparse(self.path).query)
        return self._send({"total_count": len(runs), "workflow_runs": runs})

srv = HTTPServer(("127.0.0.1", 0), H)
open(port_path, "w").write(str(srv.server_address[1]))
srv.serve_forever()
FAKE
fake_pid=$!
trap 'kill "$fake_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 100); do
  [ -s "$fake_port_file" ] && break
  sleep 0.05
done
port="$(cat "$fake_port_file")"
[ -n "$port" ] || { echo "the fake API never started"; exit 1; }
base="http://127.0.0.1:${port}"

# `--repo <case>/x` selects the world; the script neither knows nor cares.
#
# The output is RETURNED, never piped. `gate never | grep -q ...` looks right
# and is not: this file runs under `pipefail`, so the pipeline carries the
# gate's own exit code — 1, for every refusal — and the `|| bad` fires whether
# or not grep matched. Every message assertion below would have been vacuous.
# (Found by running it: seven assertions failed that should have passed.)
gate() { # gate <case> [sha] -> prints combined output, never fails
  set +e
  GH_TOKEN=fake GH_API_BASE="$base" WORKFLOW=rehearsal.yml \
    bash "$here/tag-gate.sh" --repo "$1/x" --sha "${2:-$SHA}" 2>&1
  set -e
}
rc_of() { # rc_of <case> [sha]
  set +e
  GH_TOKEN=fake GH_API_BASE="$base" WORKFLOW=rehearsal.yml \
    bash "$here/tag-gate.sh" --repo "$1/x" --sha "${2:-$SHA}" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}
says() { # says <case> <sha-or-empty> <needle> <what-was-missing>
  local out
  out="$(gate "$1" ${2:+"$2"})"
  case "$out" in
    *"$3"*) : ;;
    *) bad "$4" ;;
  esac
}

# ── 1. the tag may be cut ───────────────────────────────────────────────────
echo "  · a green rehearsal on the sha lets the tag through"
[ "$(rc_of green)" = "0" ] || bad "a green run on the sha was refused"
says green "" "has a green tier-3 rehearsal" "the pass did not say so"
says green "" "actions/runs/1007" "the pass did not name the run"

echo "  · a rehearsal that failed and then passed is proven by the pass"
[ "$(rc_of recovered)" = "0" ] || bad "a recovered commit was refused"

# ── 2. unproven, which is exit 1 ────────────────────────────────────────────
echo "  · a commit whose rehearsal failed, was cancelled, is still running, or never ran"
for case in failed cancelled running never; do
  rc="$(rc_of "$case")"
  [ "$rc" = "1" ] || bad "case '$case' exited $rc, expected 1 (unproven)"
done
says never "" "NO green tier-3 rehearsal" "the refusal did not say why"
says never "" "gh workflow run rehearsal.yml" "the refusal did not say what to do"
# `in_progress` is not `success`, and a gate that read `status` as the verdict
# would cut a tag from a rehearsal that had not finished.
says running "" "in_progress" "the refusal did not report the run's real state"

# ── 3. THE TRAP ─────────────────────────────────────────────────────────────
# A green run on a DIFFERENT commit, returned by a server that did not filter.
# The script re-checks head_sha itself precisely so this is a refusal.
echo "  · a green run on another commit does NOT prove this one"
rc="$(rc_of othersha)"
[ "$rc" = "1" ] || bad "a green run on a different sha exited $rc — it must not prove this commit"

# ── 4. unanswerable, which is exit 3 and not exit 1 ─────────────────────────
echo "  · an API error is 'cannot be proven', never 'unproven' and never 'proven'"
for case in badcreds garbage; do
  rc="$(rc_of "$case")"
  [ "$rc" = "3" ] || bad "case '$case' exited $rc, expected 3 (unanswerable)"
done
says badcreds "" "Bad credentials" "the API's own message was swallowed"
says badcreds "" "unanswerable" "the refusal did not distinguish itself from 'unproven'"

# ── 5. usage, refused before any call ───────────────────────────────────────
echo "  · an abbreviated sha is refused rather than silently matching nothing"
rc="$(rc_of green aa11bb22cc33)"
[ "$rc" = "2" ] || bad "a 12-character sha exited $rc, expected 2 (bad usage)"
says green aa11bb22cc33 "full 40-character sha" "the refusal did not say why"

echo "  · a sha that is not hex is refused"
rc="$(rc_of green ZZ11bb22cc33dd44ee55ff6677889900aabbccdd)"
[ "$rc" = "2" ] || bad "a non-hex sha exited $rc, expected 2"

# `env -u`, not an unset assignment: this suite runs in CI, where GH_TOKEN is
# set in the environment, so `GH_TOKEN= bash ...` would still inherit nothing
# useful but a plain call would inherit the real one and pass for the wrong
# reason. (It did, the first time this ran.)
echo "  · a missing token is refused before the API is reached"
set +e
env -u GH_TOKEN -u GITHUB_TOKEN GH_API_BASE="$base" \
  bash "$here/tag-gate.sh" --repo green/x --sha "$SHA" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "2" ] || bad "a missing GH_TOKEN exited $rc, expected 2"

# ── verdict ─────────────────────────────────────────────────────────────────
if [ ${#problems[@]} -gt 0 ]; then
  echo ""
  echo "✕ the tag gate is not gating:"
  for p in "${problems[@]}"; do echo "  - $p"; done
  exit 1
fi
echo "✓ the tag gate refuses an unproven commit, and says which kind of no it means"
