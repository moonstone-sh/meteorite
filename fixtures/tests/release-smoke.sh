#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

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
test ! -e fixtures/apps/static-site/dist/server
! find fixtures/apps/static-site/dist/release -path '*/.moonstone/env*' -print -quit | grep -q .
! grep -R "${ROOT}/fixtures/apps/static-site/site/dist" fixtures/apps/static-site/dist/release >/tmp/meteorite-release-smoke-source-grep.log 2>&1

deploy_root="$(mktemp -d /tmp/meteorite-release-deploy.XXXXXX)"
source_copy="$(mktemp -d /tmp/meteorite-release-source.XXXXXX)"
cp -R fixtures/apps/static-site/. "$source_copy/"
cp -R fixtures/apps/static-site/dist/release/. "$deploy_root/"
rm -rf "$source_copy/site/dist"

"$deploy_root/bin/server" >/tmp/meteorite-release-smoke-server.log 2>&1 &
server_pid=$!
register_pid "$server_pid"
# cleanup.sh handles EXIT/INT/TERM/HUP automatically
# cleanup_port is still called explicitly below
sleep 0.5

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
expect_status 404 http://127.0.0.1:8080/../../moonstone.toml

unregister_pid "$server_pid"
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
cleanup_port

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
