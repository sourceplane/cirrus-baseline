#!/usr/bin/env bash
# THE TEARDOWN DELETES THIS RUN'S RESOURCES AND REFUSES EVERYTHING ELSE
# (saas-bootstrap-engine BE6, open question 18).
#
# `testing/teardown.sh` runs against a live Cloudflare account and deletes by
# NAME PREFIX. That is the right query — orun has no `destroy` verb and the
# terraform roots apply through a published composition, so there is no state
# file to read — and it is also one bad argument away from deleting somebody's
# product. This file is why the prefix is validated rather than trusted.
#
# The API is a fake: a local HTTP server that serves the three list endpoints
# and RECORDS every DELETE it is asked for. So the assertions are about what
# the script actually asked the cloud to remove, not about what it printed.
#
# bash + python3. No network, no credential, no orun.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── the teardown's safety rule, and what it actually deletes"

problems=()
bad() { problems+=("$1"); }

# ── the fake Cloudflare API ─────────────────────────────────────────────────
# Two runs' resources live side by side, plus a production-looking product that
# must survive every case below.
fake_log="$(mktemp)"
fake_port_file="$(mktemp)"
python3 - "$fake_log" "$fake_port_file" <<'FAKE' &
import json, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path, port_path = sys.argv[1], sys.argv[2]

WORKERS = ["scratch-34945609766-api-edge", "scratch-34945609766-identity-worker",
           "scratch-11111111111-api-edge", "acme-cloud-api-edge", "cirrus-api-edge"]
D1 = [{"uuid": "d1-a", "name": "scratch-34945609766-stage"},
      {"uuid": "d1-b", "name": "scratch-34945609766-prod"},
      {"uuid": "d1-c", "name": "acme-cloud-prod"}]
KV = [{"id": "kv-a", "title": "scratch-34945609766-idem-stage"},
      {"id": "kv-b", "title": "acme-cloud-idem-prod"}]

def ok(result): return {"success": True, "errors": [], "result": result}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body):
        raw = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def do_GET(self):
        # The error case is checked FIRST: every /boom/ path also ends with a
        # real endpoint suffix, so an endpoint match would shadow it.
        if "/boom/" in self.path:
            self._send({"success": False,
                        "errors": [{"message": "Authentication error (10000)"}],
                        "result": None})
        elif self.path.endswith("/workers/scripts"):
            self._send(ok([{"id": n} for n in WORKERS]))
        elif self.path.endswith("/d1/database"):
            self._send(ok(D1))
        elif self.path.endswith("/storage/kv/namespaces"):
            self._send(ok(KV))
        else:
            self._send(ok([]))
    def do_DELETE(self):
        with open(log_path, "a") as fh:
            fh.write(self.path + "\n")
        self._send(ok({"id": self.path.rsplit("/", 1)[-1]}))

srv = HTTPServer(("127.0.0.1", 0), H)
with open(port_path, "w") as fh:
    fh.write(str(srv.server_address[1]))
srv.serve_forever()
FAKE
fake_pid=$!
trap 'kill "$fake_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  [ -s "$fake_port_file" ] && break
  sleep 0.1
done
port="$(cat "$fake_port_file")"
[ -n "$port" ] || { echo "the fake API never came up" >&2; exit 1; }

export CF_API_BASE="http://127.0.0.1:${port}"
export CLOUDFLARE_API_TOKEN="fake-token-for-testing"
ACCT="acct123"
RUN="scratch-34945609766"

run_teardown() { bash "$root/testing/teardown.sh" "$@" 2>&1; }
deletes() { cat "$fake_log" 2>/dev/null || true; }
reset_log() { : > "$fake_log"; }

# ── 1. the refusals, which are the reason this file exists ──────────────────
#
# Each of these is a prefix that WOULD delete more than one run's resources.
# The assertion is not only that the script exits non-zero — it is that it made
# NO DELETE CALL AT ALL, because an exit code after the damage is not a refusal.
# Each case ISOLATES one half of the rule wherever it can, so a mutant that
# deletes one check cannot hide behind the other. `scratch-1` is short but has
# a digit, so only the length floor can refuse it; `cirrus-baseline` is long
# but has none, so only the digit rule can. Mutation-tested: dropping either
# check turns exactly one of these red. `scratch-` and `acme-cloud` fail both
# and are here because they are what a real mistake looks like.
for spec in \
  "empty::--prefix|" \
  "too-short-with-digit:scratch-1:--prefix|scratch-1" \
  "too-short:scratch-:--prefix|scratch-" \
  "no-digit:cirrus-baseline:--prefix|cirrus-baseline" \
  "product-name:acme-cloud:--prefix|acme-cloud" \
; do
  label="${spec%%:*}"; rest="${spec#*:}"; value="${rest%%:*}"
  reset_log
  set +e
  out="$(run_teardown --prefix "$value" --account "$ACCT" --apply)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || bad "prefix '$value' ($label) was ACCEPTED — it must be refused"
  case "$out" in *REFUSING*) : ;; *) bad "prefix '$value' ($label) failed without saying it refused: $out" ;; esac
  [ -z "$(deletes)" ] || bad "prefix '$value' ($label) was refused but still issued DELETEs: $(deletes)"
done

# A prefix that clears BOTH halves of the rule is accepted — otherwise the
# cases above would pass against a script that refuses everything.
reset_log
out="$(run_teardown --prefix "$RUN" --account "$ACCT")" || bad "the real run prefix was refused: $out"
case "$out" in *REFUSING*) bad "the real run prefix '$RUN' was refused" ;; esac

# ── 2. dry run is the default ───────────────────────────────────────────────
reset_log
out="$(run_teardown --prefix "$RUN" --account "$ACCT")"
[ -z "$(deletes)" ] || bad "a run WITHOUT --apply deleted something: $(deletes)"
case "$out" in *"would delete"*) : ;; *) bad "a dry run did not say what it would delete: $out" ;; esac

# ── 3. --apply deletes THIS run's resources ─────────────────────────────────
reset_log
out="$(run_teardown --prefix "$RUN" --account "$ACCT" --apply)"
got="$(deletes | sed 's|.*/||' | sort | tr '\n' ' ')"
for want in scratch-34945609766-api-edge scratch-34945609766-identity-worker d1-a d1-b kv-a; do
  case " $got " in *" $want "*) : ;; *) bad "--apply did not delete $want (deleted: $got)" ;; esac
done

# ── 4. …and NOTHING else. This is the assertion that matters ────────────────
for survivor in scratch-11111111111-api-edge acme-cloud-api-edge cirrus-api-edge d1-c kv-b; do
  case " $got " in
    *" $survivor "*) bad "--apply deleted $survivor, which belongs to another run or another product" ;;
  esac
done
# Another run's resources are the sharpest case: same shape, same account, one
# digit different. A prefix compared with anything looser than startswith would
# take them out.
case "$got" in *11111111111*) bad "--apply reached into run 11111111111's resources" ;; esac

# ── 5. a listing that ERRORS is not an empty account ────────────────────────
# The failure this guards is the quiet one: if a failed list read as "nothing
# matched", teardown would report success over an account still full of live,
# billing resources.
reset_log
set +e
out="$(CF_API_BASE="http://127.0.0.1:${port}/boom" run_teardown --prefix "$RUN" --account "$ACCT" --apply)"
status=$?
set -e
[ "$status" -ne 0 ] || bad "a failing listing was reported as success (would leave everything live)"
case "$out" in *"listing"*|*"failed"*) : ;; *) bad "a failing listing did not say so: $out" ;; esac

# ── 6. the account is required, and no token is a refusal not a no-op ───────
set +e
out="$(run_teardown --prefix "$RUN" --apply)"; status=$?
set -e
[ "$status" -ne 0 ] || bad "a missing --account was accepted"

reset_log
set +e
out="$(CLOUDFLARE_API_TOKEN="" run_teardown --prefix "$RUN" --account "$ACCT" --apply)"; status=$?
set -e
[ "$status" -ne 0 ] || bad "a missing CLOUDFLARE_API_TOKEN was accepted"
[ -z "$(deletes)" ] || bad "a run with no token still issued DELETEs"

if [ "${#problems[@]}" -gt 0 ]; then
  echo "FAIL: the teardown does not hold its contract:" >&2
  for p in "${problems[@]}"; do echo "  - $p" >&2; done
  exit 1
fi

echo "   5 unsafe prefixes refused with zero DELETE calls, each isolating a rule"
echo "   5 of this run's resources deleted; 5 belonging to others untouched"
echo "   a dry run is the default, and a failing listing is not an empty account"
echo "teardown.test.sh: ok"
