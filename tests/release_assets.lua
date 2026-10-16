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

test "release closure includes rebased installed handlers" (function()
  local root = os.tmpname()
  os.remove(root)
  mkdir_p(root .. "/.meteorite/graph/current")
  local external = root .. "/installed-handler.lua"
  write_file(external, "return function(c) return c:text('portable') end\n")
  local app_graph = { routes = {
    { id = "installed", handler = { kind = "lua", path = external }, scope = {}, runtime = {}, execution = {} },
  } }
  require("codegen.graph_prepare").prepare_graph(app_graph, root .. "/.meteorite/graph/current", "release-hybrid")
  local assets = release_assets.new_set()
  release_assets.add_hybrid_lua_assets({ graph = graph.Graph.new() }, assets, root, app_graph)
  test.assert_eq(#assets.assets, 1, "handler is in deployment closure")
  test.assert_eq(assets.assets[1].virtual_path, ".meteorite/lua/handlers/installed.lua", "portable path")
  assert(os.execute("rm -rf " .. string.format("%q", root)))
end)

local function failing_ctx()
  local ctx = { graph = graph.Graph.new() }
  ctx.fail = function(message) error({ release_failure = message }, 0) end
  return ctx
end

local function expect_failure(fn, pattern, label)
  local ok, err = pcall(fn)
  test.assert_true(not ok, label .. ": expected failure")
  local message = type(err) == "table" and err.release_failure or tostring(err)
  test.assert_true(message:find(pattern) ~= nil, label .. ": message was: " .. tostring(message))
end

local function payload(assets)
  local set = release_assets.new_set()
  local g = graph.Graph.new()
  for _, a in ipairs(assets) do set:add(g:add_asset(a)) end
  return set
end

test "a Lua payload ships module files under lua/ and ignores other assets" (function()
  local ctx = failing_ctx()
  local assets = release_assets.new_set()
  local provided, count = release_assets.add_payload_lua_assets(ctx, assets, { payload({
    { kind = "generated", virtual_path = "hydronium_dom/server/renderer.lua", content = "return {}\n" },
    { kind = "generated", virtual_path = "lua/app/page.lua", content = "return 1\n" },
    { kind = "generated", virtual_path = "pkg/init.lua", content = "return 2\n" },
    { kind = "generated", virtual_path = "quaver-contract.lua", content = "return {}\n" },
    { kind = "generated", virtual_path = "quaver-report.txt", content = "report\n" },
  }) })
  test.assert_eq(count, 3, "module count")
  test.assert_true(provided["hydronium_dom.server.renderer"] and provided["app.page"] and provided["pkg"], "provided modules")
  local paths = {}
  for _, a in ipairs(assets.assets) do paths[#paths + 1] = a.virtual_path end
  table.sort(paths)
  test.assert_eq(table.concat(paths, " "), "lua/app/page.lua lua/hydronium_dom/server/renderer.lua lua/pkg/init.lua", "shipped paths")
  test.assert_eq(assets.assets[1].kind, "lua_module", "asset kind")
  test.assert_true(assets.assets[1].content ~= nil, "generated content carried over")
end)

test "a Lua payload rejects flavor variants, duplicates and emptiness" (function()
  expect_failure(function()
    release_assets.add_payload_lua_assets(failing_ctx(), release_assets.new_set(), { payload({
      { kind = "generated", virtual_path = "x@lua54.lua", content = "" } }) })
  end, "flavor variant", "variant")
  expect_failure(function()
    release_assets.add_payload_lua_assets(failing_ctx(), release_assets.new_set(), { payload({
      { kind = "generated", virtual_path = "a.lua", content = "" },
      { kind = "generated", virtual_path = "lua/a.lua", content = "" } }) })
  end, "twice", "duplicate")
  expect_failure(function()
    release_assets.add_payload_lua_assets(failing_ctx(), release_assets.new_set(), { payload({
      { kind = "generated", virtual_path = "report.txt", content = "" } }) })
  end, "produced no Lua modules", "empty")
end)

test "a payload module replaces the project copy a handler requires" (function()
  local root = os.tmpname()
  os.remove(root)
  mkdir_p(root .. "/src/app")
  write_file(root .. "/src/app/handler.lua", 'local page = require("app.page")\nlocal util = require("app.util")\nreturn function(c) return c:html(page.render()) end\n')
  write_file(root .. "/src/app/page.lua", 'return { render = function() return "x" end }\n')
  write_file(root .. "/src/app/util.lua", 'return {}\n')
  local assets = release_assets.new_set()
  local ctx = failing_ctx()
  local provided = release_assets.add_payload_lua_assets(ctx, assets, { payload({
    { kind = "generated", virtual_path = "app/page.lua", content = "return { render = function() return 'y' end }\n" } }) })
  release_assets.add_hybrid_lua_assets(ctx, assets, root, { routes = {
    { id = "home", handler = { kind = "lua", path = "src/app/handler.lua" } },
  } }, nil, provided)
  local paths = {}
  for _, a in ipairs(assets.assets) do paths[#paths + 1] = a.virtual_path end
  table.sort(paths)
  test.assert_eq(table.concat(paths, " "), "lua/app/page.lua src/app/handler.lua src/app/util.lua", "payload wins for app.page only")
  test.assert_eq(release_assets.check_lua_closure(ctx, assets, {}), 3, "closure holds")
  assert(os.execute("rm -rf " .. string.format("%q", root)))
end)

test "the closure check names missing modules and honors externals" (function()
  local assets = release_assets.new_set()
  local ctx = failing_ctx()
  release_assets.add_payload_lua_assets(ctx, assets, { payload({
    { kind = "generated", virtual_path = "app/page.lua", content = 'local json = require("cjson")\nlocal h = require("hydronium_dom.server")\nlocal s = string.format\nlocal m = require("string")\nreturn {}\n' } }) })
  expect_failure(function() release_assets.check_lua_closure(ctx, assets, {}) end,
    "cjson %(required by lua/app/page.lua%).*hydronium_dom%.server %(required by lua/app/page.lua%)", "missing")
  assets:add(ctx.graph:add_asset({ kind = "lua_cmodule", virtual_path = "lib/5.4/cjson.so", source_path = "/dev/null" }))
  expect_failure(function() release_assets.check_lua_closure(ctx, assets, {}) end, "hydronium_dom%.server", "C module resolves cjson")
  test.assert_eq(release_assets.check_lua_closure(ctx, assets, { "hydronium_dom.server" }), 1, "external accepted")
end)

test.run()
