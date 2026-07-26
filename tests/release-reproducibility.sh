#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/ballad_plugin/?.lua;${ROOT}/src/ballad_plugin/?/init.lua;${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"
RELEASE_ROOT="$ROOT/fixtures/apps/static-site/dist/release"
FIRST_MANIFEST="$(mktemp /tmp/meteorite-release-manifest-first.XXXXXX)"
SECOND_MANIFEST="$(mktemp /tmp/meteorite-release-manifest-second.XXXXXX)"

cleanup() {
  rm -f "$FIRST_MANIFEST" "$SECOND_MANIFEST"
}
trap cleanup EXIT INT TERM HUP

cd "$ROOT"
bash fixtures/tests/release-smoke.sh
cp "$RELEASE_ROOT/meteorite-release.json" "$FIRST_MANIFEST"

(
  cd "$ROOT/fixtures/apps/static-site"
  LUA_PATH="$LUA_PROJECT_PATH" luajit "$ROOT/../ballad/src/main.lua" play partiture.lua
) >/tmp/meteorite-release-reproducibility-ballad.log
cp "$RELEASE_ROOT/meteorite-release.json" "$SECOND_MANIFEST"

python3 - "$FIRST_MANIFEST" "$SECOND_MANIFEST" <<'PY'
import json
import sys

first = json.load(open(sys.argv[1], encoding="utf-8"))
second = json.load(open(sys.argv[2], encoding="utf-8"))

for manifest in (first, second):
    assert manifest["format"] == "meteorite.release.v0", manifest
    assert manifest["mode"] == "static", manifest
    assert manifest["runtime_source"]["status"] == "not_required", manifest
    assert manifest["target_lua"]["status"] == "not_required", manifest

assert first["graph_hash"] == second["graph_hash"], (first, second)
assert first["static"] == second["static"], (first, second)
assert first["contract"] == second["contract"], (first, second)
PY

echo "PASS: static release reproducibility"
