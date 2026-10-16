#!/usr/bin/env bash
# A hybrid release whose Lua modules come from an upstream node
# (lua_modules = "inputs") instead of whole package trees: the payload ships
# under lua/, the server serves a handler that requires it, and a payload
# missing a required module fails the release with the module's name.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${METEORITE_PAYLOAD_PORT:-18431}"
APP="$(mktemp -d /tmp/meteorite-lua-payload.XXXXXX)"
# cleanup.sh owns the EXIT trap (it stops the server). The app directory is
# removed on success and kept on failure for inspection.
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"

mkdir -p "$APP/src/handlers" "$APP/vendor"
# The server build runs the app's environment Lua; borrow this checkout's.
ln -s "$ROOT/.moonstone" "$APP/.moonstone"
cat > "$APP/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "lua-payload", port_env = "PORT" })
app:get("/greet", m.lua("handlers.greet", { path = "src/handlers/greet.lua" }))
return app
LUA
cat > "$APP/src/handlers/greet.lua" <<'LUA'
local greeting = require("greeting")
return function(c) return c:text(greeting.say("the payload")) end
LUA
cat > "$APP/vendor/greeting.lua" <<'LUA'
return { say = function(name) return "hello from " .. name end }
LUA
echo "not a module" > "$APP/vendor/report.txt"

write_partiture() {
  local files="$1"
  cat > "$APP/partiture.lua" <<LUA
local ballad = require("ballad")
local graph = require("ballad.graph")

-- Stands in for any node that produces Lua modules (for example Quaver).
local payload_plugin = {
  name = "fixture.payload",
  methods = { files = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false } },
}
function payload_plugin.files(ctx, inputs, opts)
  local set = graph.AssetSet.new()
  for _, rel in ipairs(opts.files) do
    set:add(ctx.graph:add_asset({ kind = "file", source_path = "vendor/" .. rel, virtual_path = rel }))
  end
  return set
end

return ballad.partiture(function(p)
  local payload = p:use(payload_plugin).files({ files = { $files } })
  local m = p:use("meteorite.ballad")
  local release = m.release(payload, {
    root = ".",
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    output = ".meteorite/release/server",
    mode = "hybrid",
    backend = "std_http",
    bin = "bin/server",
    lua_modules = "inputs",
  })
  p.sink.directory(release, { out = "dist/release", file_graph = true })
end)
LUA
}

play() {
  (
    cd "$APP"
    # The env's ballad launcher keeps the caller's LUA_PATH (moon exec would
    # replace it), so this checkout's meteorite.ballad plugin is found.
    LUA_PATH="$ROOT/src/ballad_plugin/?.lua;$ROOT/src/ballad_plugin/?/init.lua;$ROOT/src/?.lua;$ROOT/src/?/init.lua;$ROOT/.moonstone/env/share/lua/5.4/?.lua;$ROOT/.moonstone/env/share/lua/5.4/?/init.lua" \
      "$ROOT/.moonstone/env/bin/ballad" play "$APP/partiture.lua"
  )
}

# 1. A payload without the module the handler requires fails, naming it.
write_partiture '"report.txt"'
if play >"$APP/missing.log" 2>&1; then
  echo "lua payload: a payload without any module should fail ($APP)" >&2; exit 1
fi
grep -q 'produced no Lua modules' "$APP/missing.log" || { cat "$APP/missing.log" >&2; exit 1; }

mv "$APP/vendor/greeting.lua" "$APP/vendor/greeting.keep"
cat > "$APP/vendor/other.lua" <<'LUA'
return {}
LUA
write_partiture '"other.lua"'
if play >"$APP/closure.log" 2>&1; then
  echo "lua payload: a payload missing 'greeting' should fail the closure check" >&2; exit 1
fi
grep -q 'greeting (required by src/handlers/greet.lua)' "$APP/closure.log" || { cat "$APP/closure.log" >&2; exit 1; }
mv "$APP/vendor/greeting.keep" "$APP/vendor/greeting.lua"

# 2. The full payload builds a release that ships it and nothing else.
write_partiture '"report.txt", "greeting.lua"'
play >"$APP/release.log" 2>&1 || { cat "$APP/release.log" >&2; exit 1; }
REL="$APP/dist/release"
test -x "$REL/bin/server"
test -f "$REL/lua/greeting.lua"
test -f "$REL/src/handlers/greet.lua"
test ! -e "$REL/lua/report.txt"
if find "$REL/lua" -name '*.lua' | grep -v '/lua/greeting.lua$' | grep -q .; then
  echo "lua payload: release ships Lua beyond the payload:" >&2
  find "$REL/lua" -name '*.lua' >&2; exit 1
fi
python3 - "$REL/meteorite-release.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["lua_modules"]["source"] == "inputs", m.get("lua_modules")
assert m["lua_modules"]["modules"] == 1, m["lua_modules"]
PY

# 3. The server answers from the payload module.
(cd "$REL" && PORT="$PORT" exec ./bin/server >"$APP/server.log" 2>&1) &
server_pid=$!
register_pid "$server_pid"
for _ in $(seq 1 100); do
  curl -fsS "http://127.0.0.1:$PORT/greet" >/dev/null 2>&1 && break
  sleep 0.1
done
body="$(curl -fsS "http://127.0.0.1:$PORT/greet")"
if [ "$body" != "hello from the payload" ]; then
  echo "lua payload: expected 'hello from the payload', got '$body'" >&2
  cat "$APP/server.log" >&2; exit 1
fi
kill "$server_pid" 2>/dev/null || true
unregister_pid "$server_pid"
rm -rf "$APP"
echo "lua payload release: ok"
