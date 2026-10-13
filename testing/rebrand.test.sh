#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Two defects, both found bootstrapping sourceplane/altocumulus into workspace
# `cirrus-test` (ws_79BDXAZQ):
#
# 1. A `secret://<workspace>/<project>/<env>/<KEY>` ref is verified by the
#    platform's resolve against the run's own workspace — by slug, public id or
#    ws_ ref. The blueprint hands rebrand.mjs the workspace as a ws_… id and no
#    slug, and rebrand used to skip ws_ ids and fall back to the REPO name:
#
#      Ref workspace "altocumulus" does not name this run's workspace
#
# 2. The rules run in sequence, and each wrote its value where every LATER rule
#    could match it again. A value containing a baseline word was rewritten a
#    second time — the workspace this was found in is literally `cirrus-test`:
#
#      secret://cirrus-test/altocumulus/…  →  secret://altocumulus-test/altocumulus/…
#
#    and a bootstrap re-runs the rebrand over the whole tree in every phase, so
#    even a value written correctly once was mangled by the next phase's pass.
#
# This drives the real rebrand.mjs over a one-file tree and compares the file.
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
#   PASSES — how many times the rebrand runs over the tree (default 1). A
#   bootstrap runs it once per phase, over everything already placed.
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

ref='TOKEN: secret://lumen/cirrus/stage/CLOUDFLARE_API_TOKEN'
base='"reponame":"altocumulus","productname":"Altocumulus","productdomain":"altocumulus.dev"'

echo "── rebrand: secret-ref workspace segment"
check "a ws_ id is the workspace segment" \
  "{$base,\"orunWorkspace\":\"ws_79BDXAZQ\"}" apps/w/component.yaml "$ref" \
  "TOKEN: secret://ws_79BDXAZQ/altocumulus/stage/CLOUDFLARE_API_TOKEN"
check "an explicit slug wins" \
  "{$base,\"orunWorkspace\":\"ws_79BDXAZQ\",\"orunWorkspaceSlug\":\"acme-space\"}" apps/w/component.yaml "$ref" \
  "TOKEN: secret://acme-space/altocumulus/stage/CLOUDFLARE_API_TOKEN"
check "a slug given as the workspace is kept" \
  "{$base,\"orunWorkspace\":\"acme-space\"}" apps/w/component.yaml "$ref" \
  "TOKEN: secret://acme-space/altocumulus/stage/CLOUDFLARE_API_TOKEN"

echo "── rebrand: a written value is not rewritten"
check "a slug containing a baseline word survives" \
  "{$base,\"orunWorkspaceSlug\":\"cirrus-test\"}" apps/w/component.yaml "$ref" \
  "TOKEN: secret://cirrus-test/altocumulus/stage/CLOUDFLARE_API_TOKEN"
check "…and survives every later phase's pass" \
  "{$base,\"orunWorkspaceSlug\":\"cirrus-test\"}" apps/w/component.yaml "$ref" \
  "TOKEN: secret://cirrus-test/altocumulus/stage/CLOUDFLARE_API_TOKEN" 3
check "a domain containing a baseline word survives the repo-slug rule" \
  '{"reponame":"acme","productname":"Acme","productdomain":"cirrus-weather.dev"}' \
  apps/w/wrangler.template.jsonc '"BASE_DOMAIN": "cirrus.app"' \
  '"BASE_DOMAIN": "cirrus-weather.dev"'
check "a class name containing the brand word survives the brand-word rule" \
  '{"reponame":"cirrus-next","productname":"Cirrus Next","productdomain":"cirrusnext.dev"}' \
  apps/w/src/ua.ts 'const UA = "Cirrus-Webhooks/1.0";' \
  'const UA = "CirrusNext-Webhooks/1.0";'
check "…in every later phase's pass too" \
  '{"reponame":"cirrus-next","productname":"Cirrus Next","productdomain":"cirrusnext.dev"}' \
  apps/w/src/ua.ts 'const UA = "Cirrus-Webhooks/1.0";' \
  'const UA = "CirrusNext-Webhooks/1.0";' 3

# A token takes the word/non-word class of its value's edges, so a later rule's
# `\b` sees the boundary the value would have given it. Here the trailing
# `cirrus` is glued to the domain and `\bcirrus\b` must NOT match it — which is
# what the engine did before tokens existed. A token with non-word edges would
# have manufactured a boundary and renamed it.
check "a token keeps the word boundaries its value had" \
  "{$base}" apps/w/notes.yaml 'id: cirrus.appcirrus' \
  'id: altocumulus.devcirrus'

# --verify runs in every phase of a bootstrap. Without the product's values it
# cannot tell the product's own identity from a baseline leftover, and a product
# whose domain contains `cirrus` failed it in every phase; with them it passes.
# A real leftover must still fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
weather='{"reponame":"acme","productname":"Acme","productdomain":"cirrus-weather.dev"}'
verify "given the values, a domain containing a baseline word passes" \
  "$weather" apps/w/wrangler.template.jsonc '"BASE_DOMAIN": "cirrus-weather.dev"' pass --values
verify "without them it cannot know, and fails" \
  "$weather" apps/w/wrangler.template.jsonc '"BASE_DOMAIN": "cirrus-weather.dev"' fail
verify "given the values, a real leftover still fails" \
  "$weather" apps/w/wrangler.template.jsonc '"BASE_DOMAIN": "cirrus.app"' fail --values

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
