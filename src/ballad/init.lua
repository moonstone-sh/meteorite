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
  return path.dirname(path.dirname(path.dirname(source)))
end

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

local function with_package_path(root, fn)
  local previous_path = package.path
  package.path = table.concat({
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
    zig = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
    release = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
  },

  graph = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local output = join(root, opts.output or ".meteorite/graph/current")
    local mode = opts.mode or "dev"
    local app = load_app(root, input, mode)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end
    local result = emitter.emit(app, { output = output, mode = mode })
    local assets = graph_mod.AssetSet.new()
    assets:add(ctx.graph:add_asset({ kind = "meteorite_graph", output_path = result.output, virtual_path = result.output, metadata = { graph_hash = result.graph_hash, routes = #result.graph.routes } }))
    return assets
  end,

  zig = function(ctx, inputs, opts)
    opts = opts or {}
    local root = opts.root or "."
    local tool = opts.tool or "zig"
    local output = opts.output or "dist/server"
    local output_path = join(root, output)
    return ctx:native_task({
      tool = tool,
      args = { "build", "install-server", "--", output },
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite server",
    })
  end,

  release = function(ctx, inputs, opts)
    opts = release_contract.normalize_opts(opts)
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local graph_output = join(root, opts.graph_output or ".meteorite/graph/current")
    local output = opts.output or opts.out or "dist/server"
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

    local result = emitter.emit(app, { output = graph_output, mode = mode })
    local task_assets = ctx:native_task({
      tool = opts.tool or "zig",
      args = release_tasks.build_args_for(mode, { output = output, graph_input = opts.input or "src/main.lua", graph_output = opts.graph_output or ".meteorite/graph/current", backend = opts.backend, hybrid_profile = opts.hybrid_profile, ["hybrid-profile"] = opts["hybrid-profile"], router_dispatch = opts.router_dispatch, ["router-dispatch"] = opts["router-dispatch"], optimize = opts.optimize, target = opts.target, lua_root = lua_root }),
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite " .. release_mode .. " release",
    })

    local assets = release_assets.new_set()
    if lua_task_assets then
      for _, asset in ipairs(lua_task_assets.assets or {}) do
        asset.virtual_path = "runtime/lua"
        asset.kind = "lua_runtime"
        asset.metadata = asset.metadata or {}
        asset.metadata.target = target_lua.target
        assets:add(asset)
      end
    end
    for _, task_set in ipairs(cmodule_task_sets) do
      for _, asset in ipairs(task_set.assets or {}) do
        asset.virtual_path = path.join("runtime/lua-cmodules", path.basename and path.basename(asset.output_path or asset.virtual_path or "module") or "module")
        asset.kind = "lua_cmodule"
        assets:add(asset)
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
      content = release_manifest.build(result, release_mode, opts.bin or "bin/server", contract, target_lua),
      generated = true,
      metadata = { mode = release_mode, graph_hash = result.graph_hash, contract = contract.format },
    }))
    release_assets.add_static_assets(ctx, assets, path.join(graph_output, "static"))
    if release_mode == "hybrid" then
      release_assets.add_hybrid_lua_assets(ctx, assets, root, result.graph)
      release_assets.add_package_assets(ctx, assets, opts.packages)
      release_assets.add_runtime_source_asset(ctx, assets, root, target_lua)
    end
    return assets
  end,
}
