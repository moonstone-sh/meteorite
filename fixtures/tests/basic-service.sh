#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

cd "$ROOT"
export MOONSTONE_HOME="$ROOT/.moonstone-home"
while read -r pid; do
  if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi
done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
sleep 0.2
LUA_PATH="$LUA_PROJECT_PATH" luajit ../ballad/src/main.lua play fixtures/apps/basic-service/partiture.lua >/tmp/meteorite-partiture-test.log

test -f fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
test -f fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
test -f fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
test -x fixtures/apps/basic-service/dist/server

grep -q 'base_url = "http://localhost:8888"' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'data_cruncher = "zig/helpers/data_cruncher.zig"' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q '"strategy": "class_dfa"' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"alphabet_classes": 10' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"backtracking": false' fixtures/apps/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q 'PUT' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'PATCH' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'DELETE' fixtures/apps/basic-service/.meteorite/graph/current/capabilities.zon
grep -q 'field put fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
grep -q 'field patch fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
grep -q 'field delete fun(self: MeteoriteApp' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.meta.lua
test -f fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.lua
grep -q 'return meteorite' fixtures/apps/basic-service/.meteorite/aids/lua/meteorite.lua
grep -q 'memory profile: default' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'peak route memory:' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'max URI: 8kb' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'DFA tables:' fixtures/apps/basic-service/.meteorite/graph/current/build-report.txt
grep -q 'max_uri_bytes = 8192' fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
grep -q 'RouteMemory' fixtures/apps/basic-service/.meteorite/graph/current/graph.zig
grep -q 'memory = .{' fixtures/apps/basic-service/.meteorite/graph/current/runtime.zon

fixtures/apps/basic-service/dist/server >/tmp/meteorite-basic-service.log 2>&1 &
server_pid=$!
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
register_pid "$server_pid"
# cleanup.sh handles EXIT/INT/TERM/HUP automatically
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
  actual="$(curl -sS -o /tmp/meteorite-status.out -w '%{http_code}' "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected status $expected for curl $*, got $actual" >&2
    cat /tmp/meteorite-status.out >&2 || true
    exit 1
  fi
}

expect_body ok http://127.0.0.1:8080/health
expect_body 123 http://127.0.0.1:8080/users/123
[[ "$(curl -sS -X PUT --data 'replace user' http://127.0.0.1:8080/users/123)" == "123" ]]
[[ "$(curl -sS -X PATCH --data 'patch user' http://127.0.0.1:8080/users/123)" == "123" ]]
[[ "$(curl -sS -X DELETE http://127.0.0.1:8080/users/123)" == "123" ]]
expect_body router_01 http://127.0.0.1:8080/devices/router_01
expect_body report-01.txt http://127.0.0.1:8080/files/report-01.txt
expect_body release_64 http://127.0.0.1:8080/slugs/release_64
expect_body 550e8400-e29b-41d4-a716-446655440000 http://127.0.0.1:8080/uuids/550e8400-e29b-41d4-a716-446655440000
expect_body 0123456789abcdef0123456789abcdef http://127.0.0.1:8080/hex/0123456789abcdef0123456789abcdef
expect_body lua 'http://127.0.0.1:8080/search?q=lua&page=2&exact=true'
[[ "$(curl -sS -X POST --data 'hello body' http://127.0.0.1:8080/echo)" == "hello body" ]]
expect_status 404 http://127.0.0.1:8080/missing
expect_status 405 -X POST http://127.0.0.1:8080/health
expect_status 405 -X PUT http://127.0.0.1:8080/health
expect_status 404 http://127.0.0.1:8080/users/not-a-number
expect_status 404 http://127.0.0.1:8080/devices/INVALID
expect_status 404 http://127.0.0.1:8080/files/../../secret
expect_status 404 http://127.0.0.1:8080/slugs/bad.slug
expect_status 404 http://127.0.0.1:8080/uuids/not-a-uuid
expect_status 404 http://127.0.0.1:8080/hex/abc
expect_status 400 http://127.0.0.1:8080/search
expect_status 400 'http://127.0.0.1:8080/search?q=lua&page=abc'
too_many_pairs="$(python3 - <<'PY'
print('&'.join('q%d=x' % i for i in range(70)), end='')
PY
)"
expect_status 414 "http://127.0.0.1:8080/health?${too_many_pairs}"
python3 - <<'PY' >/tmp/meteorite-big-body.txt
print('x' * 9000, end='')
PY
expect_status 413 -X POST --data-binary @/tmp/meteorite-big-body.txt http://127.0.0.1:8080/echo
expect_status 413 -X DELETE --data 'unexpected' http://127.0.0.1:8080/users/123

tmp_missing="$(mktemp -d /tmp/meteorite-missing-handler.XXXXXX)"
cp -R fixtures/apps/basic-service/. "$tmp_missing/"
python3 - <<'PY' "$tmp_missing/src/app.lua"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('"handlers.health"', '"handlers.missing"')
p.write_text(s)
PY
python3 - <<'PY' "$tmp_missing/build.zig" "$ROOT"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
root = sys.argv[2]
s = p.read_text()
s = s.replace('"../../../src/cli/main.lua"', f'"{root}/src/cli/main.lua"')
s = s.replace('b.path("../../../zig/pattern.zig")', f'.{{ .cwd_relative = "{root}/zig/pattern.zig" }}')
s = s.replace('b.path("../../../zig/meteorite.zig")', f'.{{ .cwd_relative = "{root}/zig/meteorite.zig" }}')
s = s.replace('b.path("../../../zig/bridge.zig")', f'.{{ .cwd_relative = "{root}/zig/bridge.zig" }}')
s = s.replace('b.path("../../../zig/backends/protocol.zig")', f'.{{ .cwd_relative = "{root}/zig/backends/protocol.zig" }}')
s = s.replace('b.path("../../../zig/server/http_date.zig")', f'.{{ .cwd_relative = "{root}/zig/server/http_date.zig" }}')
s = s.replace('b.path("../../../zig/server/signals.zig")', f'.{{ .cwd_relative = "{root}/zig/server/signals.zig" }}')
s = s.replace('b.path("../../../zig/server/cached_time.zig")', f'.{{ .cwd_relative = "{root}/zig/server/cached_time.zig" }}')
s = s.replace('b.path("../../../zig/bridge/lua_bench_stats.zig")', f'.{{ .cwd_relative = "{root}/zig/bridge/lua_bench_stats.zig" }}')
s = s.replace('b.path("../../../zig/server/validators.zig")', f'.{{ .cwd_relative = "{root}/zig/server/validators.zig" }}')
s = s.replace('b.path("../../../zig/server/static_files.zig")', f'.{{ .cwd_relative = "{root}/zig/server/static_files.zig" }}')
s = s.replace('b.path("../../../zig/server/request_limits.zig")', f'.{{ .cwd_relative = "{root}/zig/server/request_limits.zig" }}')
p.write_text(s)
PY
(cd "$tmp_missing" && ! zig build install-server >/tmp/meteorite-missing-build.log 2>&1)
grep -q 'route GET /health references missing handler `handlers.missing`' /tmp/meteorite-missing-build.log
grep -q 'declared at:' /tmp/meteorite-missing-build.log
grep -q 'define `pub fn missing(ctx: anytype) !void`' /tmp/meteorite-missing-build.log

tmp_budget="$(mktemp -d /tmp/meteorite-pattern-budget.XXXXXX)"
cp -R fixtures/apps/basic-service/. "$tmp_budget/"
python3 - <<'PY' "$tmp_budget/src/app.lua"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('max_dfa_bytes = "8kb"', 'max_dfa_bytes = "128"')
p.write_text(s)
PY
(cd "$tmp_budget" && ! luajit "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current release-static >/tmp/meteorite-budget.log 2>&1)
grep -q 'pattern exceeded DFA byte budget' /tmp/meteorite-budget.log
grep -q 'dfa_states' /tmp/meteorite-budget.log
grep -q 'estimated_size' /tmp/meteorite-budget.log

tmp_profile="$(mktemp -d /tmp/meteorite-profile.XXXXXX)"
mkdir -p "$tmp_profile/src"
cat > "$tmp_profile/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({
  name = "profile-demo",
  profile = m.profile({
    name = "tiny",
    request = {
      max_uri_bytes = "512b",
      max_path_bytes = "256b",
      max_query_bytes = "128b",
      max_query_pairs = 4,
      max_response_bytes = "4kb",
      request_arena = "16kb",
    },
    static = {
      max_dfa_bytes_total = "8kb",
      max_graph_bytes = "32kb",
    },
  }),
})
app:get("/health", "handlers.health")
return app
LUA
luajit src/cli/main.lua graph "$tmp_profile/src/main.lua" "$tmp_profile/.meteorite/graph/current" release-static >/tmp/meteorite-profile.log
grep -q 'memory profile: tiny' /tmp/meteorite-profile.log
grep -q 'uri limit: 512 bytes' /tmp/meteorite-profile.log
grep -q 'max URI: 512b' "$tmp_profile/.meteorite/graph/current/build-report.txt"

demo_root="fixtures/apps/hybrid-demo"
luajit src/cli/main.lua graph "$demo_root/src/main.lua" "$demo_root/.meteorite/graph/current" dev >/tmp/meteorite-demo-graph.log
grep -q 'capabilities: auth, http, zig' /tmp/meteorite-demo-graph.log
grep -q 'inline_lua' "$demo_root/.meteorite/graph/current/routes.zon"
grep -q 'data_cruncher' "$demo_root/.meteorite/graph/current/capabilities.zon"
grep -q 'inline Lua handlers: 5' "$demo_root/.meteorite/graph/current/build-report.txt"
grep -q 'Lua state: single_locked' "$demo_root/.meteorite/graph/current/build-report.txt"
grep -q 'MeteoriteContext_route_3' "$demo_root/.meteorite/aids/lua/meteorite.meta.lua"
test -f "$demo_root/.meteorite/aids/lua/meteorite.lua"
test -f "$demo_root/.meteorite/lua/inline/route_1.lua"

demo_invoke() {
  luajit src/cli/main.lua invoke "$demo_root/src/main.lua" "$@"
}
[[ "$(demo_invoke GET /)" == $'200\ttext/plain; charset=utf-8\thello from meteorite' ]]
[[ "$(demo_invoke GET /health)" == $'200\tapplication/json\t{"ok":true,"runtime":"lua"}' ]]
[[ "$(demo_invoke GET /users/456)" == $'200\tapplication/json\t{"id":"456","message":"typed params from zig graph","user":{"capability":"db","echo":{"id":"456"},"headers":{"authorization":"Bearer demo-token-for-db"},"ok":true,"path":"/get-user-from-db"}}' ]]
[[ "$(demo_invoke POST /echo 'hello body')" == $'200\ttext/plain; charset=utf-8\thello body' ]]
[[ "$(demo_invoke GET /devices/router_01)" == $'200\tapplication/json\t{"device":"device:router_01"}' ]]
[[ "$(demo_invoke GET /devices/INVALID)" == $'404\ttext/plain\tnot found' ]]

luajit <<'LUA'
package.path = "fixtures/apps/hybrid-demo/src/?.lua;fixtures/apps/hybrid-demo/src/?/init.lua;src/?.lua;src/?/init.lua;" .. package.path
local hybrid = require("cli.hybrid")
local app = assert(loadfile("fixtures/apps/hybrid-demo/src/main.lua"))()
local store = { capabilities = {} }
hybrid.invoke(app, { method = "GET", path = "/users/1" }, { store = store })
hybrid.invoke(app, { method = "GET", path = "/users/2" }, { store = store })
assert(store.capabilities["auth.db"].refresh_count == 1, "auth token refresh should be capability-owned and cached")
LUA

! luajit src/cli/main.lua graph "$demo_root/src/main.lua" "$demo_root/.meteorite/static-fail" release-static >/tmp/meteorite-static-inline.log 2>&1
grep -q 'static build cannot include inline Lua handler' /tmp/meteorite-static-inline.log
grep -q 'build hybrid' /tmp/meteorite-static-inline.log

tmp_cap="$(mktemp -d /tmp/meteorite-capability.XXXXXX)"
cp -R fixtures/apps/hybrid-demo/. "$tmp_cap/"
python3 - <<'PY' "$tmp_cap/src/app.lua"
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = re.sub(r'app:capability\("auth", \{\n  db = \{\n    token_url = "http://localhost:8888/token",\n    audience = "db",\n    refresh_before_seconds = 30,\n  \},\n\}\)\n\n', '', s)
p.write_text(s)
PY
! luajit src/cli/main.lua graph "$tmp_cap/src/main.lua" "$tmp_cap/.meteorite/graph/current" dev >/tmp/meteorite-capability.log 2>&1
grep -q 'route uses undeclared AUTH capability `db`' /tmp/meteorite-capability.log

tmp_upvalue="$(mktemp -d /tmp/meteorite-upvalue.XXXXXX)"
mkdir -p "$tmp_upvalue/src"
cat > "$tmp_upvalue/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "bad-upvalue" })
local message = "nope"
app:get("/", function(c)
  return c:text(message)
end)
return app
LUA
! luajit src/cli/main.lua graph "$tmp_upvalue/src/main.lua" "$tmp_upvalue/.meteorite/graph/current" dev >/tmp/meteorite-upvalue.log 2>&1
grep -q 'captures outer local `message`' /tmp/meteorite-upvalue.log

tmp_stubs="$(mktemp -d /tmp/meteorite-stubs.XXXXXX)"
mkdir -p "$tmp_stubs/src" "$tmp_stubs/zig"
cat > "$tmp_stubs/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "stub-demo" })
app:get("/users/:id", { params = { id = m.u64() } }, "handlers.get_user")
return app
LUA
luajit src/cli/main.lua graph "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" dev >/tmp/meteorite-stubs.log
test ! -e "$tmp_stubs/zig/handlers.zig"
test ! -e "$tmp_stubs/.luarc.json"
grep -q 'pub fn get_user(c: mt.ctx.get_user)' "$tmp_stubs/.meteorite/aids/handlers.stub.zig"
luajit src/cli/main.lua sync "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" dev >/tmp/meteorite-sync.log
test -f "$tmp_stubs/zig/handlers.zig"
test -f "$tmp_stubs/.luarc.json"
grep -q '<meteorite:generated-stub>' "$tmp_stubs/zig/handlers.zig"
grep -q 'created .*zig/handlers.zig' "$tmp_stubs/.meteorite/aids/handler-sync.warnings.txt"
grep -q 'pub fn get_user(c: mt.ctx.get_user)' "$tmp_stubs/zig/handlers.zig"
! luajit src/cli/main.lua graph "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" release-static >/tmp/meteorite-stubs-release.log 2>&1
grep -q 'release build contains generated handler stub `get_user`' /tmp/meteorite-stubs-release.log

tmp_typed="$(mktemp -d /tmp/meteorite-typed.XXXXXX)"
cp -R fixtures/apps/basic-service/. "$tmp_typed/"
cat > "$tmp_typed/zig/handlers.zig" <<'ZIG'
const mt = @import("meteorite_graph");

pub fn health(c: mt.ctx.health) !void {
    try c.text(200, "ok");
}

pub fn get_user(c: mt.ctx.get_user) !void {
    const id: u64 = c.params.id;
    _ = id;
    try c.bytes(200, "application/json", c.param("id") orelse "missing");
}

pub fn put_user(c: mt.ctx.put_user) !void {
    const id: u64 = c.params.id;
    const body = try c.body();
    _ = body;
    try c.text(200, c.param("id") orelse "missing");
    _ = id;
}

pub fn patch_user(c: mt.ctx.patch_user) !void {
    const id: u64 = c.params.id;
    const body = try c.body();
    _ = body;
    try c.text(200, c.param("id") orelse "missing");
    _ = id;
}

pub fn delete_user(c: mt.ctx.delete_user) !void {
    const id: u64 = c.params.id;
    _ = id;
    try c.text(200, c.param("id") orelse "missing");
}

pub fn echo(c: mt.ctx.echo) !void {
    const value = try c.body();
    try c.text(200, value);
}

pub fn get_device(c: mt.ctx.get_device) !void {
    const id: []const u8 = c.params.device_id;
    try c.bytes(200, "application/json", id);
}

pub fn file(c: mt.ctx.file) !void { try c.text(200, c.params.name); }
pub fn slug(c: mt.ctx.slug) !void { try c.text(200, c.params.slug); }
pub fn uuid(c: mt.ctx.uuid) !void { try c.text(200, c.params.id); }
pub fn hex(c: mt.ctx.hex) !void { try c.text(200, c.params.digest); }
pub fn search(c: mt.ctx.search) !void {
    const q: []const u8 = c.query.q;
    const page: ?u64 = c.query.page;
    const exact: ?bool = c.query.exact;
    _ = page;
    _ = exact;
    try c.text(200, q);
}
ZIG
python3 - <<'PY' "$tmp_typed/build.zig" "$ROOT"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
root = sys.argv[2]
s = p.read_text()
s = s.replace('"../../../src/cli/main.lua"', f'"{root}/src/cli/main.lua"')
s = s.replace('b.path("../../../zig/pattern.zig")', f'.{{ .cwd_relative = "{root}/zig/pattern.zig" }}')
s = s.replace('b.path("../../../zig/meteorite.zig")', f'.{{ .cwd_relative = "{root}/zig/meteorite.zig" }}')
s = s.replace('b.path("../../../zig/bridge.zig")', f'.{{ .cwd_relative = "{root}/zig/bridge.zig" }}')
s = s.replace('b.path("../../../zig/backends/protocol.zig")', f'.{{ .cwd_relative = "{root}/zig/backends/protocol.zig" }}')
s = s.replace('b.path("../../../zig/server/http_date.zig")', f'.{{ .cwd_relative = "{root}/zig/server/http_date.zig" }}')
s = s.replace('b.path("../../../zig/server/signals.zig")', f'.{{ .cwd_relative = "{root}/zig/server/signals.zig" }}')
s = s.replace('b.path("../../../zig/server/cached_time.zig")', f'.{{ .cwd_relative = "{root}/zig/server/cached_time.zig" }}')
s = s.replace('b.path("../../../zig/bridge/lua_bench_stats.zig")', f'.{{ .cwd_relative = "{root}/zig/bridge/lua_bench_stats.zig" }}')
s = s.replace('b.path("../../../zig/server/validators.zig")', f'.{{ .cwd_relative = "{root}/zig/server/validators.zig" }}')
s = s.replace('b.path("../../../zig/server/static_files.zig")', f'.{{ .cwd_relative = "{root}/zig/server/static_files.zig" }}')
s = s.replace('b.path("../../../zig/server/request_limits.zig")', f'.{{ .cwd_relative = "{root}/zig/server/request_limits.zig" }}')
p.write_text(s)
PY
(cd "$tmp_typed" && zig build install-server >/tmp/meteorite-typed-build.log 2>&1)

echo "PASS: Meteorite basic-service fixture acceptance"
