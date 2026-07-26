#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/ballad_plugin/?.lua;${ROOT}/src/ballad_plugin/?/init.lua;${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

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
moon orbit sync static-site --update >/tmp/meteorite-release-static-site-sync.log
missing_static_root="$(mktemp -d /tmp/meteorite-release-missing-static.XXXXXX)"
mkdir -p "$missing_static_root/src"
cat > "$missing_static_root/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "missing-static-source" })
app:get("/missing.txt", m.file("site/dist/missing.txt", { content_type = "text/plain" }))
return app
LUA
cat > "$missing_static_root/partiture.lua" <<LUA
local ballad = require("ballad")

return ballad.partiture(function(p)
  local meteorite = p:use("meteorite.ballad")
  local release = meteorite.release({
    input = "$missing_static_root/src/main.lua",
    output = "$missing_static_root/.meteorite/release/server",
    graph_output = "$missing_static_root/.meteorite/graph/release",
    mode = "static",
    backend = "std_http",
  })
  p.sink.directory(release, { out = "$missing_static_root/dist/release", file_graph = true })
end)
LUA
set +e
(
  cd "$ROOT"
  LUA_PATH="$LUA_PROJECT_PATH" luajit ../ballad/src/main.lua play "$missing_static_root/partiture.lua" \
    >/tmp/meteorite-release-missing-static.log 2>&1
)
missing_static_status=$?
set -e
if [ "$missing_static_status" -eq 0 ]; then
  echo "expected static release export with deleted site/dist source to fail" >&2
  exit 1
fi
grep -q 'static file not found' /tmp/meteorite-release-missing-static.log
grep -q 'site/dist/missing.txt' /tmp/meteorite-release-missing-static.log

(
  cd "$ROOT/fixtures/apps/static-site"
  LUA_PATH="$LUA_PROJECT_PATH" luajit "$ROOT/../ballad/src/main.lua" play partiture.lua
) >/tmp/meteorite-release-smoke-ballad.log

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
python3 - fixtures/apps/static-site/dist/release "$ROOT" <<'PY'
import json
import os
import pathlib
import sys

release_root = pathlib.Path(sys.argv[1])
source_root = sys.argv[2]
forbidden = [
    source_root,
    "/Users/",
    ".moonstone/env",
    "fixtures/apps/static-site/site/dist",
    "fixtures/apps/static-site/src",
]
text_suffixes = {".json", ".zon", ".txt", ".lua", ".zig", ".toml", ".md"}

for path in release_root.rglob("*"):
    if not path.is_file():
        continue
    rel = path.relative_to(release_root).as_posix()
    if path.suffix not in text_suffixes and rel != "meteorite-release.json":
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    for needle in forbidden:
        assert needle not in text, f"host/source path leak in {rel}: {needle}"

manifest = json.loads((release_root / "meteorite-release.json").read_text(encoding="utf-8"))
assert manifest["runtime_source"]["status"] == "not_required", manifest["runtime_source"]
assert manifest["target_lua"]["status"] == "not_required", manifest["target_lua"]
for asset in manifest["static"]["assets"]:
    assert not os.path.isabs(asset["artifact_path"]), asset
    assert asset["artifact_path"].startswith("static/"), asset
PY
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
