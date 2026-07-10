#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

cd "$ROOT"
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
export MOONSTONE_HOME="$ROOT/.moonstone-home"

cleanup_port() {
  while read -r pid; do
    if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi
  done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
}

cleanup_port
rm -rf fixtures/apps/static-site/dist fixtures/apps/static-site/.meteorite/release fixtures/apps/static-site/.meteorite/graph/static-site-basic-release
LUA_PATH="$LUA_PROJECT_PATH" luajit ../ballad/src/main.lua play fixtures/apps/static-site/partiture.lua >/tmp/meteorite-release-smoke-ballad.log

test -x fixtures/apps/static-site/dist/release/bin/server
test -f fixtures/apps/static-site/dist/release/meteorite-release.json
test -d fixtures/apps/static-site/dist/release/static
test -f deploy/Dockerfile.release
test -f deploy/README.md
grep -q 'FROM debian:bookworm-slim' deploy/Dockerfile.release
grep -q 'COPY --chown=meteorite:meteorite . /app/' deploy/Dockerfile.release
grep -q 'USER meteorite' deploy/Dockerfile.release
grep -q 'ENTRYPOINT \["/app/bin/server"\]' deploy/Dockerfile.release
grep -q 'dist/release' deploy/README.md
grep -q '__meteorite/info' deploy/README.md
test ! -e fixtures/apps/static-site/dist/server
! find fixtures/apps/static-site/dist/release -path '*/.moonstone/env*' -print -quit | grep -q .
! grep -R "${ROOT}/fixtures/apps/static-site/site/dist" fixtures/apps/static-site/dist/release >/tmp/meteorite-release-smoke-source-grep.log 2>&1
python3 - fixtures/apps/static-site/dist/release/meteorite-release.json <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["format"] == "meteorite.release.v0", manifest
assert manifest["mode"] == "static", manifest
assert manifest["route_count"] >= 3, manifest
assert manifest["retained_lua_nodes"]["count"] == 0, manifest["retained_lua_nodes"]
assert manifest["static"]["guarantee"] == "no_lua_runtime_execution_nodes", manifest["static"]
assert manifest["static"]["lua_runtime_execution_nodes"] == 0, manifest["static"]
assert manifest["static"]["count"] >= 3, manifest["static"]
assert not manifest["runtime_source"]["artifact_path"], manifest["runtime_source"]
assert manifest["target"]["abi"] == "native", manifest["target"]
PY

deploy_root="$(mktemp -d /tmp/meteorite-release-deploy.XXXXXX)"
cp -R fixtures/apps/static-site/dist/release/. "$deploy_root/"
test -x "$deploy_root/bin/server"
test -f "$deploy_root/meteorite-release.json"
test -d "$deploy_root/static"
! find "$deploy_root" -path '*/.moonstone/env*' -print -quit | grep -q .
! find "$deploy_root" -path '*/src/*' -print -quit | grep -q .
! find "$deploy_root" -path '*/site/dist/*' -print -quit | grep -q .
! find "$deploy_root" -path '*/runtime/lua/*' -print -quit | grep -q .

hidden_source_parent="$(mktemp -d /tmp/meteorite-release-source-hidden.XXXXXX)"
hidden_source="$hidden_source_parent/dist"
restore_static_source() {
  if [ -d "$hidden_source" ] && [ ! -e fixtures/apps/static-site/site/dist ]; then
    mv "$hidden_source" fixtures/apps/static-site/site/dist
  fi
}
trap 'restore_static_source; cleanup_all' EXIT INT TERM HUP
mv fixtures/apps/static-site/site/dist "$hidden_source"
test ! -e fixtures/apps/static-site/site/dist

(
  cd "$deploy_root"
  "$deploy_root/bin/server" >/tmp/meteorite-release-smoke-server.log 2>&1
) &
server_pid=$!
register_pid "$server_pid"
# cleanup.sh handles EXIT/INT/TERM/HUP automatically
# cleanup_port is still called explicitly below
for _ in $(seq 1 100); do
  if curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsS http://127.0.0.1:8080/ >/dev/null

expect_body() {
  local expected="$1"
  local url="$2"
  local actual
  actual="$(curl -sS "$url")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $url -> $expected, got $actual" >&2
    exit 1
  fi
}

expect_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl -sS -o /tmp/meteorite-release-status.out -w '%{http_code}' "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected status $expected for curl $*, got $actual" >&2
    cat /tmp/meteorite-release-status.out >&2 || true
    exit 1
  fi
}

expect_status 200 http://127.0.0.1:8080/
expect_status 200 http://127.0.0.1:8080/benchmarks.json
expect_status 200 http://127.0.0.1:8080/assets/app.js
expect_status 404 http://127.0.0.1:8080/../../moonstone.toml
curl -fsS http://127.0.0.1:8080/__meteorite/info > /tmp/meteorite-release-info.json
python3 - /tmp/meteorite-release-info.json "$ROOT" <<'PY'
import json
import sys

info_text = open(sys.argv[1], encoding="utf-8").read()
root = sys.argv[2]
info = json.loads(info_text)
assert info["format"] == "meteorite.info.v0", info
assert info["meteorite_mode"] == "release-static", info
assert info["backend"] == "std_http", info
assert info["lua_runtime"] is False, info
assert info["router_dispatch"] == "param_matchers", info
assert info["target"], info
assert root not in info_text, info_text
assert "/Users/" not in info_text, info_text
assert "fixtures/apps" not in info_text, info_text
assert "site/dist" not in info_text, info_text
PY

guard_state="$(mktemp -d /tmp/meteorite-release-guard.XXXXXX)"
printf '%s\n' "$server_pid" > "$guard_state/server.pid"
METEORITE_DEV_STATE_DIR="$guard_state" \
METEORITE_DEV_PID_FILE="$guard_state/server.pid" \
METEORITE_DEV_PORT=8080 \
METEORITE_DEV_SERVER="$deploy_root/bin/server" \
  scripts/guard.sh cleanup >/tmp/meteorite-release-guard-cleanup.log 2>&1
unregister_pid "$server_pid"
wait "$server_pid" 2>/dev/null || true
grep -q 'guard: stopping Meteorite dev server' /tmp/meteorite-release-guard-cleanup.log
grep -q 'Shutting down' /tmp/meteorite-release-smoke-server.log
METEORITE_DEV_STATE_DIR="$guard_state" \
METEORITE_DEV_PID_FILE="$guard_state/server.pid" \
METEORITE_DEV_PORT=8080 \
METEORITE_DEV_SERVER="$deploy_root/bin/server" \
  scripts/guard.sh assert-free >/tmp/meteorite-release-guard-assert-free.log 2>&1
if lsof -tiTCP:8080 -sTCP:LISTEN >/tmp/meteorite-release-port-after.log 2>&1 && [ -s /tmp/meteorite-release-port-after.log ]; then
  echo "expected port 8080 to be free after graceful shutdown" >&2
  cat /tmp/meteorite-release-port-after.log >&2
  exit 1
fi
cleanup_port
restore_static_source

LUA_PATH="$LUA_PROJECT_PATH" luajit <<'LUA'
local release_assets = require("ballad.release_assets")
local graph = require("ballad.graph")
local tmp = os.getenv("TMPDIR") or "/tmp"
local root = tmp .. "/meteorite-package-assets-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000))
os.execute("mkdir -p " .. string.format("%q", root .. "/files/share/lua/5.4/luasql"))
os.execute("mkdir -p " .. string.format("%q", root .. "/files/lib/lua/5.4/luasql"))
local function write(path, body)
  local f = assert(io.open(path, "wb")); f:write(body); f:close()
end
write(root .. "/files/share/lua/5.4/pure.lua", "return true\n")
write(root .. "/files/share/lua/5.4/luasql/init.lua", "return {}\n")
write(root .. "/files/lib/lua/5.4/lfs.so", "fake\n")
write(root .. "/files/lib/lua/5.4/luasql/sqlite3.so", "fake\n")
local collected = {}
local ctx = { graph = { add_asset = function(_, asset) local wrapped = graph.Asset.new(asset); collected[#collected + 1] = wrapped; return wrapped end } }
local assets = release_assets.new_set()
release_assets.add_package_assets(ctx, assets, {
  { name = "pure", kind = "lua_module", artifact_path = root },
  { name = "lfs", kind = "lua_cmodule", artifact_path = root },
  { name = "luasql.sqlite3", kind = "lua_cmodule", artifact_path = root },
}, { target = "native" })
local found = {}
for _, asset in ipairs(collected) do found[asset.virtual_path] = true end
assert(found["lua/5.4/pure.lua"], "pure Lua module must be deploy-local under lua/")
assert(found["lua/5.4/luasql/init.lua"], "pure Lua package trees must be deploy-local under lua/")
assert(found["lib/5.4/lfs.so"], "lfs C module must be deploy-local under lib/")
assert(found["lib/5.4/luasql/sqlite3.so"], "luasql.sqlite3 C module must be deploy-local under lib/")
LUA

echo "PASS: Meteorite release smoke"
