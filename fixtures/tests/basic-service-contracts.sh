#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
meteorite_test_setup
meteorite_test_trap "basic-service-contracts"

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
(cd "$tmp_budget" && ! luajit "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current release-static std_http >/tmp/meteorite-budget.log 2>&1)
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
app:get("/health", {
  summary = "Report profile health",
}, "handlers.health")
return app
LUA
luajit src/cli/main.lua graph "$tmp_profile/src/main.lua" "$tmp_profile/.meteorite/graph/current" release-static std_http >/tmp/meteorite-profile.log
grep -q 'memory profile: tiny' /tmp/meteorite-profile.log
grep -q 'uri limit: 512 bytes' /tmp/meteorite-profile.log
grep -q 'max URI: 512b' "$tmp_profile/.meteorite/graph/current/build-report.txt"

demo_root="fixtures/apps/hybrid-demo"
luajit src/cli/main.lua graph "$demo_root/src/main.lua" "$demo_root/.meteorite/graph/current" dev fast_http >/tmp/meteorite-demo-graph.log
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
[[ "$(demo_invoke POST /echo 'hello body')" == $'200\ttext/plain; charset=utf-8\thello body' ]]
[[ "$(demo_invoke GET /devices/router_01)" == $'200\tapplication/json\t{"device":"device:router_01"}' ]]
[[ "$(demo_invoke GET /devices/INVALID)" == $'200\tapplication/json\t{"device":"device:INVALID"}' ]]

luajit <<'LUA'
package.path = "fixtures/apps/hybrid-demo/src/?.lua;fixtures/apps/hybrid-demo/src/?/init.lua;src/?.lua;src/?/init.lua;" .. package.path
local hybrid = require("cli.hybrid")
local app = assert(loadfile("fixtures/apps/hybrid-demo/src/main.lua"))()
local store = { capabilities = {} }
local requests = 0
local function fake_http(method, base_url, path, opts)
  requests = requests + 1
  assert(method == "POST")
  assert(base_url == "http://localhost:8888")
  assert(path == "/get-user-from-db")
  assert(opts.headers.authorization == "Bearer demo-token-for-db")
  assert(opts.body.id == "1" or opts.body.id == "2")
  return {
    status = 200,
    headers = { ["content-type"] = "application/json" },
    body = { ok = true, path = path, capability = "db", echo = opts.body },
  }
end
local first = hybrid.invoke(app, { method = "GET", path = "/users/1" }, { store = store, http_request = fake_http })
local second = hybrid.invoke(app, { method = "GET", path = "/users/2" }, { store = store, http_request = fake_http })
assert(first.body:find('"id":"1"', 1, true))
assert(first.body:find('"echo":{"id":"1"}', 1, true))
assert(second.body:find('"id":"2"', 1, true))
assert(second.body:find('"echo":{"id":"2"}', 1, true))
assert(requests == 2)
assert(store.capabilities["auth.db"].refresh_count == 1, "auth token refresh should be capability-owned and cached")
LUA

! luajit src/cli/main.lua graph "$demo_root/src/main.lua" "$demo_root/.meteorite/static-fail" release-static std_http >/tmp/meteorite-static-inline.log 2>&1
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
! luajit src/cli/main.lua graph "$tmp_cap/src/main.lua" "$tmp_cap/.meteorite/graph/current" dev fast_http >/tmp/meteorite-capability.log 2>&1
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
! luajit src/cli/main.lua graph "$tmp_upvalue/src/main.lua" "$tmp_upvalue/.meteorite/graph/current" dev fast_http >/tmp/meteorite-upvalue.log 2>&1
grep -q 'captures outer local `message`' /tmp/meteorite-upvalue.log

tmp_stubs="$(mktemp -d /tmp/meteorite-stubs.XXXXXX)"
mkdir -p "$tmp_stubs/src" "$tmp_stubs/zig"
cat > "$tmp_stubs/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "stub-demo" })
app:get("/users/:id", {
  summary = "Fetch one stub user",
  params = { id = m.u64() },
}, "handlers.get_user")
return app
LUA
luajit src/cli/main.lua graph "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" dev fast_http >/tmp/meteorite-stubs.log
test ! -e "$tmp_stubs/zig/handlers.zig"
test ! -e "$tmp_stubs/.luarc.json"
grep -q 'pub fn get_user(c: mt.ctx.get_user)' "$tmp_stubs/.meteorite/aids/handlers.stub.zig"
luajit src/cli/main.lua sync "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" dev >/tmp/meteorite-sync.log
test -f "$tmp_stubs/zig/handlers.zig"
test -f "$tmp_stubs/.luarc.json"
grep -q '<meteorite:generated-stub>' "$tmp_stubs/zig/handlers.zig"
grep -q 'created .*zig/handlers.zig' "$tmp_stubs/.meteorite/aids/handler-sync.warnings.txt"
grep -q 'pub fn get_user(c: mt.ctx.get_user)' "$tmp_stubs/zig/handlers.zig"
! luajit src/cli/main.lua graph "$tmp_stubs/src/main.lua" "$tmp_stubs/.meteorite/graph/current" release-static std_http >/tmp/meteorite-stubs-release.log 2>&1
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

echo "PASS: basic-service deterministic contracts"
