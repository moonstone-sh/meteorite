local graph_mod = require("ballad.graph")
local path = require("ballad.path")
local emitter = require("codegen.emitter")
local release_manifest = require("ballad.release_manifest")
local release_assets = require("ballad.release_assets")
local release_contract = require("ballad.release_contract")
local release_tasks = require("ballad.release_tasks")

local function plugin_root()
  local source = debug.getinfo(1, "S").source or ""
  source = source:gsub("^@", "")
  local root2 = path.dirname(path.dirname(source))
  local root = root2
  local pipe_check = io.open(path.join(root2, "build.zig"), "r")
  if pipe_check then
    pipe_check:close()
  else
    root = path.dirname(root2)
  end
  -- Ensure absolute path so native tasks with different cwd can locate scripts
  if root == "" or root == "." then
    local pipe = io.popen("pwd", "r")
    root = (pipe:read("*l") or ""):gsub("/+$", "")
    pipe:close()
  elseif root:sub(1, 1) ~= "/" then
    local pipe = io.popen("pwd", "r")
    local cwd = (pipe:read("*l") or ""):gsub("/+$", "")
    pipe:close()
    root = cwd .. "/" .. root
  end
  return root
end

local function plugin_build_file()
  return path.join(plugin_root(), "build.zig")
end

local function plugin_cli_file()
  local p1 = path.join(plugin_root(), "cli/main.lua")
  local f = io.open(p1, "r")
  if f then
    f:close()
    return p1
  end
  return path.join(plugin_root(), "src/cli/main.lua")
end

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

local function with_package_path(root, fn)
  local previous_path = package.path
  package.path = table.concat({
    path.join(plugin_root(), "src/?.lua"),
    path.join(plugin_root(), "src/?/init.lua"),
    path.join(root, "src/?.lua"),
    path.join(root, "src/?/init.lua"),
    "src/?.lua",
    "src/?/init.lua",
    previous_path,
  }, ";")
  local ok, a, b, c = pcall(fn)
  package.path = previous_path
  if not ok then error(a) end
  return a, b, c
end


local function load_app(root, input, mode)
  local previous_mode = _G.METEORITE_BUILD_MODE
  _G.METEORITE_BUILD_MODE = mode
  local ok, app_or_err = pcall(function()
    local chunk, err = with_package_path(root, function()
      return loadfile(input)
    end)
    if not chunk then error(err) end
    return with_package_path(root, chunk)
  end)
  _G.METEORITE_BUILD_MODE = previous_mode
  if not ok then error(app_or_err) end
  return app_or_err
end




return {
  name = "meteorite.ballad",
  version = "0.1.0",
  methods = {
    graph = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
    check = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
    zig = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
    release = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
  },

  graph = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local output = join(root, opts.output or ".meteorite/graph/current")
    local mode = opts.mode
    if not mode or not opts.backend then ctx.fail("meteorite.graph requires explicit mode and backend") end
    local app = load_app(root, input, mode)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end
    local result = emitter.emit(app, { output = output, mode = mode, backend = opts.backend })
    local assets = graph_mod.AssetSet.new()
    assets:add(ctx.graph:add_asset({ kind = "meteorite_graph", output_path = result.output, virtual_path = result.output, metadata = { graph_hash = result.graph_hash, routes = #result.graph.routes } }))
    return assets
  end,

  check = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    if not opts.mode or not opts.backend then ctx.fail("meteorite.check requires explicit mode and backend") end
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local mode, release_mode = release_contract.normalize_mode(opts.mode)
    local app = load_app(root, input, mode)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end
    local contract = release_contract.for_graph(app:normalize({ mode = "dev" }), release_mode)
    if release_mode == "static" then release_contract.fail_static_lua(ctx, contract.retained_lua_nodes) end
    release_contract.validate_target_lua(ctx, root, contract, opts)
    release_contract.validate_packages(ctx, contract, opts)
    local output = join(root, opts.output or ".meteorite/check/report")
    local result = emitter.emit(app, { output = output, mode = mode, backend = opts.backend })
    if release_mode == "static" then release_contract.assert_static_graph(ctx, result.graph) end
    local assets = graph_mod.AssetSet.new()
    assets:add(ctx.graph:add_asset({ kind = "meteorite_check", output_path = result.output, virtual_path = result.output, metadata = { mode = mode, backend = opts.backend, graph_hash = result.graph_hash } }))
    return assets
  end,

  zig = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    if not opts.mode or not opts.backend then ctx.fail("meteorite.zig requires explicit mode and backend") end
    local root = opts.root or "."
    local tool = opts.tool or "zig"
    local output = opts.output or "dist/server"
    local output_path = join(root, output)
    return ctx:native_task({
      tool = tool,
      args = release_tasks.build_args_for(opts.mode, {
        output = output,
        graph_input = opts.input or "src/main.lua",
        graph_output = opts.graph or opts.graph_output or ".meteorite/graph/current",
        backend = opts.backend,
        hybrid_profile = opts.hybrid_profile,
        router_dispatch = opts.router_dispatch,
        optimize = opts.optimize,
      }),
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite server",
    })
  end,

  release = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    if not opts.mode or not opts.backend then ctx.fail("meteorite.release requires explicit mode and backend") end
    release_contract.validate_deployment_adapter(ctx, opts)
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local graph_output = join(root, opts.graph_output or ".meteorite/graph/current")
    local output = opts.output or opts.out or ".meteorite/release/server"
    local output_path = join(root, output)
    local mode, release_mode = release_contract.normalize_mode(opts.mode)
    local app = load_app(root, input, mode)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end

    local normalized = app:normalize({ mode = "dev" })
    local contract = release_contract.for_graph(normalized, release_mode)
    if release_mode == "static" then release_contract.fail_static_lua(ctx, contract.retained_lua_nodes) end
    local target_lua = release_contract.validate_target_lua(ctx, root, contract, opts)
    release_contract.validate_packages(ctx, contract, opts)
    local lua_task_assets, lua_root = release_tasks.compile_target_lua(ctx, root, opts, target_lua, plugin_root())
    lua_root = lua_root or opts.lua_root
    local cmodule_task_sets = release_tasks.rebuild_lua_cmodules(ctx, root, opts, target_lua, lua_root, plugin_root())

    local result = emitter.emit(app, { output = graph_output, mode = mode, backend = opts.backend })
    if release_mode == "static" then release_contract.assert_static_graph(ctx, result.graph) end
    local task_assets = ctx:native_task({
      tool = opts.tool or "zig",
      args = release_tasks.build_args_for(mode, { output = output, build_file = plugin_build_file(), project_root = ".", meteorite_cli = plugin_cli_file(), graph_input = opts.input or "src/main.lua", graph_output = opts.graph_output or ".meteorite/graph/current", backend = opts.backend, unix_socket_path = opts.unix_socket_path, ["unix-socket-path"] = opts["unix-socket-path"], unix_socket_mode = opts.unix_socket_mode, ["unix-socket-mode"] = opts["unix-socket-mode"], unix_socket_unlink_stale = opts.unix_socket_unlink_stale, ["unix-socket-unlink-stale"] = opts["unix-socket-unlink-stale"], hybrid_profile = opts.hybrid_profile, ["hybrid-profile"] = opts["hybrid-profile"], router_dispatch = opts.router_dispatch, ["router-dispatch"] = opts["router-dispatch"], optimize = opts.optimize, target = opts.target, lua_root = lua_root }),
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite " .. release_mode .. " release",
    })

    local assets = release_assets.new_set()
    if lua_task_assets then
      -- The built Lua runtime is a directory (bin/, lib/, include/).
      -- Add individual files so the Ballad sink can copy them.
      release_assets.add_runtime_tree_assets(ctx, assets, root, lua_root or path.join(".meteorite/release", target_lua and target_lua.target or "unknown", "lua"), target_lua and target_lua.target or "host")
    end
    for _, task_set in ipairs(cmodule_task_sets) do
      for _, asset in ipairs(task_set.assets or {}) do
        release_assets.add_target_cmodule_assets(ctx, assets, root, asset.output_path, target_lua and target_lua.target or release_contract.target_from_opts(opts))
      end
    end
    for _, asset in ipairs(task_assets.assets or {}) do
      asset.virtual_path = opts.bin or "bin/server"
      asset.kind = "meteorite_server"
      asset.metadata = asset.metadata or {}
      asset.metadata.mode = release_mode
      assets:add(asset)
    end
    assets:add(ctx.graph:add_asset({
      kind = "meteorite_release_manifest",
      virtual_path = "meteorite-release.json",
      content = release_manifest.build(result, release_mode, opts.bin or "bin/server", contract, target_lua, opts),
      generated = true,
      metadata = { mode = release_mode, graph_hash = result.graph_hash, contract = contract.format },
    }))
    release_assets.add_static_assets(ctx, assets, path.join(graph_output, "static"))
    if release_mode == "hybrid" then
      release_assets.add_hybrid_lua_assets(ctx, assets, root, result.graph)
      release_assets.add_package_assets(ctx, assets, opts.packages, { target = target_lua and target_lua.target or release_contract.target_from_opts(opts) })
      release_assets.add_runtime_source_asset(ctx, assets, root, target_lua)
    end
    if release_mode == "static" then release_assets.assert_static_release_assets(ctx, assets) end
    return assets
  end,
}
