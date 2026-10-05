package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"
local prepare = require("codegen.graph_prepare")
local helpers = require("codegen.helpers")
local test = require("test")

local function fixture(mode)
  local root = os.tmpname()
  os.remove(root)
  helpers.mkdir_p(root .. "/.meteorite/graph/current")
  local external = root .. "/installed-handler.lua"
  helpers.write_file(external, 'return function(c) return c:text("portable") end\n')
  local route = { id = "package_handler", handler = { kind = "lua", path = external }, scope = {}, runtime = {}, execution = {} }
  prepare.prepare_graph({ routes = { route } }, root .. "/.meteorite/graph/current", mode)
  return root, external, route
end

test "release copies external Lua handlers to a relative deployment path" (function()
  local root, external, route = fixture("release-hybrid")
  test.assert_eq(route.handler.path, ".meteorite/lua/handlers/package_handler.lua", "runtime path")
  test.assert_eq(route.handler.source_path, external, "source provenance")
  test.assert_eq(helpers.read_file(root .. "/" .. route.handler.path), helpers.read_file(external), "packaged source")
  assert(os.execute("rm -rf " .. string.format("%q", root)))
end)

test "development retains the live installed handler path" (function()
  local root, external, route = fixture("hybrid_dev")
  test.assert_eq(route.handler.path, external, "live path")
  assert(os.execute("rm -rf " .. string.format("%q", root)))
end)

test "external handler edits change the release Lua partition hash" (function()
  local root = os.tmpname()
  os.remove(root)
  helpers.mkdir_p(root .. "/.meteorite/graph/current")
  local external = root .. "/installed-handler.lua"
  local m, emitter = require("meteorite"), require("codegen.emitter")
  local function emit(text)
    helpers.write_file(external, 'return function(c) return c:text("' .. text .. '") end')
    local app = m.app({ name = "handler-hash" })
    app:get("/", { summary = "External handler" }, m.lua("installed_handler", { path = external }))
    return emitter.emit(app, { output = root .. "/.meteorite/graph/current", mode = "release-hybrid", backend = "fast_http" })
  end
  local before, after = emit("before"), emit("after")
  test.assert_true(before.partitions.lua_chunk_hash ~= after.partitions.lua_chunk_hash, "content invalidates partition")
  assert(os.execute("rm -rf " .. string.format("%q", root)))
end)

test.run()
