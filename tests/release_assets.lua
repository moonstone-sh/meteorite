package.path = "src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;tests/?.lua;;"

local graph = require("ballad.graph")
local release_assets = require("ballad.release_assets")
local test = require("test")

local function write_file(path, content)
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
end

local function mkdir_p(path)
  assert(os.execute("mkdir -p " .. string.format("%q", path)))
end

local function fixture_tree()
  local root = os.tmpname()
  os.remove(root)
  local output = root .. "/.meteorite/release/aarch64-linux-gnu/lua-cmodules/mockcmodule"
  mkdir_p(output .. "/lib/lua/5.4")
  write_file(output .. "/lib/lua/5.4/mockcmodule.so", "synthetic target cmodule\n")
  return root, output
end

local function collect(root, output_dir)
  local assets = release_assets.new_set()
  local ctx = { graph = graph.Graph.new() }
  release_assets.add_target_cmodule_assets(ctx, assets, root, output_dir, "aarch64-linux-gnu")
  return assets
end

test "target cmodule assets collect root-relative task output" (function()
  local root, output = fixture_tree()
  local relative = output:sub(#root + 2)
  local assets = collect(root, relative)
  test.assert_eq(#assets.assets, 1, "asset count")
  test.assert_eq(assets.assets[1].kind, "lua_cmodule", "asset kind")
  test.assert_eq(assets.assets[1].virtual_path, "lib/5.4/mockcmodule.so", "virtual path")
  test.assert_eq(assets.assets[1].metadata.target, "aarch64-linux-gnu", "target metadata")
end)

test "target cmodule assets collect already-rooted task output" (function()
  local root, output = fixture_tree()
  local assets = collect(root, output)
  test.assert_eq(#assets.assets, 1, "asset count")
  test.assert_eq(assets.assets[1].virtual_path, "lib/5.4/mockcmodule.so", "virtual path")
end)

test "hybrid inline chunks collect project-rooted generated paths" (function()
  local root = os.tmpname()
  os.remove(root)
  local chunk_path = root .. "/.meteorite/graph/release/../../lua/inline/route_1.lua"
  mkdir_p(root .. "/.meteorite/graph/release")
  mkdir_p(root .. "/.meteorite/lua/inline")
  write_file(root .. "/.meteorite/lua/inline/route_1.lua", "return function() return 'ok' end\n")

  local assets = release_assets.new_set()
  local ctx = { graph = graph.Graph.new() }
  release_assets.add_hybrid_lua_assets(ctx, assets, root, {
    routes = {
      { id = "route_1", handler = { kind = "inline_lua", lifted = { chunk_path = chunk_path } } },
    },
  })

  test.assert_eq(#assets.assets, 1, "asset count")
  test.assert_eq(assets.assets[1].kind, "meteorite_lua_chunk", "asset kind")
  test.assert_eq(assets.assets[1].virtual_path, ".meteorite/lua/inline/route_1.lua", "virtual path")
end)

test "lifted chunks keep a separate release runtime path" (function()
  local lifter = require("codegen.lifter")
  local root = os.tmpname()
  os.remove(root)
  mkdir_p(root .. "/.meteorite/graph/release")
  local source = root .. "/handler.lua"
  write_file(source, "return function(ctx) return ctx end\n")
  local handler = assert(loadfile(source))()
  local lifted = lifter.lift({
    id = "route_1",
    method = "GET",
    raw_path = "/",
    source = { file = source, line = 1, column = 1 },
    handler = { value = handler },
  }, { output = root .. "/.meteorite/graph/release" })

  test.assert_eq(lifted.runtime_path, ".meteorite/lua/inline/route_1.lua", "runtime path")
  test.assert_eq(lifted.chunk_path, root .. "/.meteorite/graph/release/../../lua/inline/route_1.lua", "source path")
end)

test "generated route descriptors use the runtime path" (function()
  local graph_routes = require("codegen.graph_routes")
  local route = {
    id = "route_1",
    source = { file = "src/main.lua", line = 1, column = 1 },
    handler = {
      kind = "inline_lua",
      lifted = {
        chunk_path = ".meteorite/graph/current/../../lua/inline/route_1.lua",
        runtime_path = ".meteorite/lua/inline/route_1.lua",
      },
    },
  }
  local plugin = {
    id = "plugin_1",
    handler = { kind = "inline_lua", lifted = route.handler.lifted },
  }

  test.assert_true(graph_routes.route_handler_zig(route):find('chunk_path = ".meteorite/lua/inline/route_1.lua"', 1, true) ~= nil, "route runtime path")
  test.assert_true(graph_routes.plugin_handler_zig(plugin):find('chunk_path = ".meteorite/lua/inline/route_1.lua"', 1, true) ~= nil, "plugin runtime path")
end)

test.run()
