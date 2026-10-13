#!/usr/bin/env bash
# DESTROY EVERYTHING ONE REHEARSAL RUN CREATED, AND NOTHING ELSE
# (saas-bootstrap-engine BE6, open question 18).
#
# Tier 3 bootstraps a whole product into a real Cloudflare account. One green
# run leaves 14 workers on two environments, a D1 database per environment and
# a KV namespace per environment — on the order of thirty paid resources, at
# roughly thirty runs a month. The designed teardown listed the workspace, the
# repo and the secrets and never mentioned these, which is the only part of
# cleanup that costs money if it is missing.
#
# # Why a name query and not a state file
#
# orun has no `destroy` verb, and the terraform roots apply through a
# composition published as an OCI artifact — so there is no `terraform destroy`
# this repository can reach, and no state file it can read. What it does have
# is the naming rule: every Cloudflare resource a bootstrap creates is prefixed
# with `reponame`, and tier 3's reponame is `scratch-<run-id>`. So "everything
# this run made" is answerable as a name query, which survives a half-applied
# run, a cancelled job and a lost state file alike — the three cases a state
# file handles worst and a teardown most needs to handle.
#
# # The safety rule, which is the whole point of this file
#
# A prefix-delete against a live cloud account is one bad argument away from
# deleting somebody's product. So the prefix is VALIDATED, not trusted:
#
#   - at least 12 characters, and
#   - containing at least one digit.
#
# `scratch-34945609766` passes. `scratch-` (8, no digit) does not. `acme` does
# not. `cirrus` does not. The digit is not decoration: it is what makes a
# prefix run-specific rather than product-generic, because a run id is a number
# and a product name is not. A caller who cannot satisfy both is a caller who
# has lost track of what it is deleting, and this refuses rather than guesses.
#
# Dry-run is the DEFAULT. Nothing is deleted without --apply.
#
# bash + python3 + curl. Talks to the Cloudflare API and nothing else; point
# CF_API_BASE at a fake to test it, which is what testing/teardown.test.sh does.
set -euo pipefail

CF_API_BASE="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"

usage() {
  cat >&2 <<'USAGE'
usage: teardown.sh --prefix <name-prefix> --account <cloudflare-account-id> [--apply]

  --prefix    delete resources whose name starts with this. Must be >= 12
              characters and contain a digit (see the header).
  --account   Cloudflare account id.
  --apply     actually delete. Without it, every deletion is reported and
              nothing is removed.

env: CLOUDFLARE_API_TOKEN (required), CF_API_BASE (override for testing)
USAGE
  exit 2
}

prefix="" account="" apply=false
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)  prefix="${2:-}"; shift 2 ;;
    --account) account="${2:-}"; shift 2 ;;
    --apply)   apply=true; shift ;;
    -h|--help) usage ;;
    *) echo "teardown: unknown argument $1" >&2; usage ;;
  esac
done

[ -n "$account" ] || { echo "teardown: --account is required" >&2; exit 2; }

# ── the safety rule, before anything is listed let alone deleted ────────────
if [ -z "$prefix" ]; then
  echo "teardown: REFUSING an empty --prefix: it would match every resource in account $account" >&2
  exit 3
fi
if [ "${#prefix}" -lt 12 ]; then
  echo "teardown: REFUSING the prefix '$prefix' — it is ${#prefix} characters and the floor is 12." >&2
  echo "          A short prefix matches more than one run's resources. Tier 3 names are" >&2
  echo "          'scratch-<run-id>', which clears the floor comfortably." >&2
  exit 3
fi
case "$prefix" in
  *[0-9]*) : ;;
  *)
    echo "teardown: REFUSING the prefix '$prefix' — it contains no digit." >&2
    echo "          A run-specific prefix carries its run id; a prefix without one is a" >&2
    echo "          PRODUCT name, and deleting by product name is how a rehearsal takes out" >&2
    echo "          something real. If this is genuinely a run prefix, it is malformed." >&2
    exit 3
    ;;
esac
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || {
  echo "teardown: CLOUDFLARE_API_TOKEN is not set" >&2; exit 2; }

cf() { # cf <method> <path>
  curl -sS -X "$1" "${CF_API_BASE}$2" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json"
}

# Cloudflare wraps everything as {success, result: [...]}. Pull the id/name
# pairs whose name starts with the prefix, and say so when the call itself
# failed rather than treating a failure as "nothing to delete" — a listing that
# errors and a listing that is empty look identical downstream, and only one of
# them means the account is clean.
#
# The JSON arrives as an ARGUMENT, not on stdin: `python3 -` reads its script
# from stdin, so a script that also read its data from there would get nothing.
MATCH_PY='
import json, sys
body_text, id_key, name_key, what, prefix = sys.argv[1:6]
try:
    body = json.loads(body_text)
except json.JSONDecodeError:
    sys.exit(f"teardown: {what}: the API did not return JSON")
if not body.get("success", False):
    errs = "; ".join(e.get("message", "?") for e in body.get("errors") or []) or "no message"
    sys.exit(f"teardown: listing {what} failed: {errs}")
for item in body.get("result") or []:
    name = item.get(name_key) or ""
    if name.startswith(prefix):
        print(f"{item.get(id_key)}\t{name}")
'
matching() { # matching <json> <id-key> <name-key> <what>
  python3 -c "$MATCH_PY" "$1" "$2" "$3" "$4" "$prefix"
}

deleted=0 would=0 failed=0

sweep() { # sweep <what> <list-path> <delete-path-template> <id-key> <name-key>
  local what="$1" list_path="$2" del_tmpl="$3" id_key="$4" name_key="$5"
  local body hits id name
  body="$(cf GET "$list_path")"
  # NOT a process substitution: `while read < <(matching ...)` runs the listing
  # in a subshell whose failure `set -e` never sees, and a listing that ERRORED
  # would then read as an empty account — the one way this script could report
  # success while leaving every resource live and billing.
  hits="$(matching "$body" "$id_key" "$name_key" "$what")" || exit 1
  [ -n "$hits" ] || return 0
  while IFS=$'\t' read -r id name; do
    [ -n "$id" ] || continue
    if [ "$apply" = true ]; then
      if cf DELETE "${del_tmpl//\{id\}/$id}" | python3 -c '
import json,sys
try: ok = json.load(sys.stdin).get("success", False)
except Exception: ok = False
sys.exit(0 if ok else 1)'; then
        echo "   ✓ deleted $what $name"
        deleted=$((deleted + 1))
      else
        echo "   ✕ FAILED to delete $what $name" >&2
        failed=$((failed + 1))
      fi
    else
      echo "   · would delete $what $name"
      would=$((would + 1))
    fi
  done <<<"$hits"
}

echo "── tearing down everything named '${prefix}*' in account ${account}"
[ "$apply" = true ] || echo "   (dry run — pass --apply to delete)"

sweep "worker"    "/accounts/${account}/workers/scripts" \
                  "/accounts/${account}/workers/scripts/{id}"        id id
sweep "d1"        "/accounts/${account}/d1/database" \
                  "/accounts/${account}/d1/database/{id}"            uuid name
sweep "kv"        "/accounts/${account}/storage/kv/namespaces" \
                  "/accounts/${account}/storage/kv/namespaces/{id}"  id title

if [ "$failed" -gt 0 ]; then
  echo "teardown: $deleted deleted, $failed FAILED — resources are still live and still billing" >&2
  exit 1
fi
if [ "$apply" = true ]; then
  echo "teardown: $deleted resource(s) deleted"
else
  echo "teardown: $would resource(s) would be deleted"
fi
