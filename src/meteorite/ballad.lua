local graph_mod = require("ballad.graph")
local path = require("ballad.path")
local fs = require("ballad.fs")
local emitter = require("meteorite.emitter")

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

local function normalize_mode(mode)
  mode = mode or "hybrid"
  if mode == "hybrid" or mode == "release-hybrid" then return "release-hybrid", "hybrid" end
  if mode == "static" or mode == "release-static" then return "release-static", "static" end
  error("meteorite.release: unsupported mode `" .. tostring(mode) .. "`; expected hybrid or static")
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

local function source_at(item)
  local source = item and item.source or {}
  local file = source.file or source.short_src or "<unknown>"
  local line = source.line or source.linedefined or 0
  local column = source.column or 1
  return tostring(file) .. ":" .. tostring(line) .. ":" .. tostring(column)
end

local function add_lua_reference(refs, kind, label, item, hint)
  refs[#refs + 1] = {
    kind = kind,
    label = label,
    source = source_at(item),
    hint = hint,
  }
end

local function lua_references(graph)
  local refs = {}
  for _, route in ipairs(graph.routes or {}) do
    local handler = route.handler or {}
    if handler.kind == "inline_lua" then
      add_lua_reference(refs, "inline route handler", route.method .. " " .. route.raw_path, route, "move this handler to a Zig symbol/file or build with mode='hybrid'")
    elseif handler.kind == "lua" then
      add_lua_reference(refs, "Lua file/module route handler", route.method .. " " .. route.raw_path .. " -> " .. tostring(handler.path or handler.module), route, "replace with a Zig handler or build with mode='hybrid'")
    end
  end
  for _, plugin in ipairs(graph.plugins or {}) do
    if type(plugin.execute) == "function" then
      add_lua_reference(refs, "Lua scoped plugin", plugin.id or plugin.kind or "plugin", plugin, "expand this plugin to graph/Zig at construction time or build with mode='hybrid'")
    elseif plugin.handler and (plugin.handler.kind == "inline_lua" or plugin.handler.kind == "lua") then
      add_lua_reference(refs, "Lua scoped plugin", plugin.id or plugin.kind or "plugin", plugin, "replace with a graph/Zig plugin or build with mode='hybrid'")
    end
  end
  return refs
end

local function fail_static_lua(ctx, refs)
  if #refs == 0 then return end
  local lines = {
    "meteorite.release({ mode = 'static' }) failed the release compiler contract.",
    "",
    "The graph may be produced by Lua, but static mode cannot retain Lua runtime execution nodes.",
    "",
    "Lua runtime nodes found:",
  }
  for _, ref in ipairs(refs) do
    lines[#lines + 1] = "  - " .. ref.kind .. ": " .. ref.label
    lines[#lines + 1] = "    at: " .. ref.source
    lines[#lines + 1] = "    hint: " .. ref.hint
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Use meteorite.release({ mode = 'hybrid' }) to ship Lua, or remove/replace non-graphable Lua with Zig/graph-expanded handlers/plugins."
  ctx.fail(table.concat(lines, "\n"))
end

local file_exists

local function release_contract(graph, release_mode)
  local refs = lua_references(graph)
  return {
    format = "meteorite.release_contract.v0",
    validation_mode = release_mode,
    graph_may_be_produced_by_lua = true,
    retained_lua_nodes = refs,
    requires_target_lua = release_mode == "hybrid" and #refs > 0,
  }
end

local function runtime_source_from_opts(opts)
  local runtime = opts.runtime or {}
  return opts.lua_source
    or opts.runtime_source
    or runtime.source_payload_path
    or runtime.source_payload
    or runtime.source
    or os.getenv("METEORITE_LUA_SOURCE")
end

local function target_from_opts(opts)
  local runtime = opts.runtime or {}
  return opts.target or runtime.target or runtime.abi_target
end

local function validate_hybrid_target_lua(ctx, root, contract, opts)
  if contract.validation_mode ~= "hybrid" then
    return { status = "not_required" }
  end
  local target = target_from_opts(opts)
  if not contract.requires_target_lua then
    return { status = "not_required", target = target }
  end

  local source = runtime_source_from_opts(opts)
  if target and target ~= "" and (not source or source == "") then
    local lines = {
      "meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) failed the release compiler contract.",
      "",
      "Hybrid mode may retain Lua runtime execution nodes, but cross-target release must materialize target Lua and target Lua modules.",
      "",
      "Missing:",
      "  source_payload_path",
      "",
      "Lua runtime nodes found:",
    }
    for _, ref in ipairs(contract.retained_lua_nodes) do
      lines[#lines + 1] = "  - " .. ref.kind .. ": " .. ref.label
      lines[#lines + 1] = "    at: " .. ref.source
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Hint: pass runtime = { source_payload_path = ... } from the Moonstone/Ballad plugin, set lua_source/runtime_source, or build static after replacing Lua runtime handlers/plugins."
    ctx.fail(table.concat(lines, "\n"))
  end

  if source and source ~= "" then
    local full = join(root, source)
    if not file_exists(full) then
      ctx.fail("meteorite.release({ mode = 'hybrid' }) runtime source_payload_path does not exist: " .. tostring(source))
    end
    return { status = "source_payload_available", target = target, source_payload_path = source }
  end

  return { status = "host_env", target = target }
end

function file_exists(file_path)
  local f = io.open(file_path, "rb")
  if f then f:close(); return true end
  return false
end

local function add_file_asset(ctx, assets, root, source_path, virtual_path, kind, metadata)
  if not source_path or source_path == "" then return end
  local full = join(root, source_path)
  if not file_exists(full) then return end
  assets:add(ctx.graph:add_asset({
    kind = kind or "file",
    source_path = full,
    virtual_path = virtual_path or source_path,
    metadata = metadata or {},
  }))
end

local function copy_tree_assets(ctx, assets, root, source_dir, dest_dir, kind)
  local full_dir = join(root, source_dir)
  if not fs.is_dir(full_dir) then return end
  for _, file_path in ipairs(fs.list_files(full_dir)) do
    local rel = path.relative(file_path, full_dir)
    local source = fs.readlink(file_path)
    assets:add(ctx.graph:add_asset({
      kind = kind or "file",
      source_path = source,
      virtual_path = path.join(dest_dir or source_dir, rel),
    }))
  end
end

local function lua_file_path(handler)
  if handler.path and handler.path ~= "" then return handler.path end
  local module = handler.module or ""
  if module:match("%.lua$") or module:find("/") then return module end
  return "src/" .. module:gsub("%.", "/") .. ".lua"
end

local function add_hybrid_lua_assets(ctx, assets, root, graph)
  copy_tree_assets(ctx, assets, root, ".meteorite/lua/inline", ".meteorite/lua/inline", "meteorite_lua_chunk")
  copy_tree_assets(ctx, assets, root, "src", "src", "meteorite_lua_source")
  copy_tree_assets(ctx, assets, root, ".moonstone/env/share/lua", ".moonstone/env/share/lua", "lua_module")
  copy_tree_assets(ctx, assets, root, ".moonstone/env/lib/lua", ".moonstone/env/lib/lua", "lua_cmodule")
  for _, route in ipairs(graph.routes or {}) do
    if route.handler and route.handler.kind == "lua" then
      local route_path = lua_file_path(route.handler)
      add_file_asset(ctx, assets, root, route_path, route_path, "meteorite_lua_handler", { route = route.id })
    end
  end
  for _, plugin in ipairs(graph.plugins or {}) do
    if plugin.handler and plugin.handler.kind == "lua" then
      local plugin_path = lua_file_path(plugin.handler)
      add_file_asset(ctx, assets, root, plugin_path, plugin_path, "meteorite_lua_plugin", { plugin = plugin.id })
    end
  end
end

local function add_runtime_source_asset(ctx, assets, root, target_lua)
  if not target_lua or not target_lua.source_payload_path then return end
  local source_path = target_lua.source_payload_path
  local name = source_path:match("([^/]+)$") or "lua-source.tar.gz"
  add_file_asset(ctx, assets, root, source_path, path.join("runtime/source", name), "lua_runtime_source", { target = target_lua.target or "host" })
end

local function build_args_for(mode, opts)
  local args = {
    "build",
    "install-server",
    "-Dmode=" .. mode,
    "-Dgraph-input=" .. (opts.graph_input or "src/main.lua"),
    "-Dgraph-output=" .. (opts.graph_output or ".meteorite/graph/current"),
    "-Dbackend=" .. (opts.backend or "std_http"),
    "-Dhybrid-profile=" .. (opts.hybrid_profile or opts["hybrid-profile"] or (mode == "release-hybrid" and "optimized" or "default")),
    "-Drouter-dispatch=" .. (opts.router_dispatch or opts["router-dispatch"] or "param_matchers"),
  }
  if opts.optimize then args[#args + 1] = "-Doptimize=" .. opts.optimize end
  if opts.target then args[#args + 1] = "-Dtarget=" .. opts.target end
  args[#args + 1] = "--"
  args[#args + 1] = opts.output or opts.out or "dist/server"
  return args
end

local function json_string(value)
  return "\"" .. tostring(value or ""):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. "\""
end

local function build_manifest(result, release_mode, output_path, contract, target_lua)
  local retained = contract and contract.retained_lua_nodes or {}
  local lines = {
    "{",
    "  \"format\": \"meteorite.release.v0\",",
    "  \"mode\": \"" .. release_mode .. "\",",
    "  \"graph_hash\": \"" .. tostring(result.graph_hash) .. "\",",
    "  \"routes\": " .. tostring(#(result.graph.routes or {})) .. ",",
    "  \"output\": " .. json_string(output_path) .. ",",
    "  \"contract\": {",
    "    \"format\": \"meteorite.release_contract.v0\",",
    "    \"validation_mode\": " .. json_string(contract and contract.validation_mode or release_mode) .. ",",
    "    \"graph_may_be_produced_by_lua\": true,",
    "    \"retained_lua_nodes\": " .. tostring(#retained) .. ",",
    "    \"requires_target_lua\": " .. tostring(contract and contract.requires_target_lua or false),
    "  },",
    "  \"target_lua\": {",
    "    \"status\": " .. json_string(target_lua and target_lua.status or "not_required") .. ",",
    "    \"target\": " .. json_string(target_lua and target_lua.target or "") .. ",",
    "    \"source_payload_path\": " .. json_string(target_lua and target_lua.source_payload_path or ""),
    "  }",
    "}",
    "",
  }
  return table.concat(lines, "\n")
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
    opts = opts or {}
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
    opts = opts or {}
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local graph_output = join(root, opts.graph_output or ".meteorite/graph/current")
    local output = opts.output or opts.out or "dist/server"
    local output_path = join(root, output)
    local mode, release_mode = normalize_mode(opts.mode)
    local app = load_app(root, input, mode)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end

    local normalized = app:normalize({ mode = "dev" })
    local contract = release_contract(normalized, release_mode)
    if release_mode == "static" then fail_static_lua(ctx, contract.retained_lua_nodes) end
    local target_lua = validate_hybrid_target_lua(ctx, root, contract, opts)

    local result = emitter.emit(app, { output = graph_output, mode = mode })
    local task_assets = ctx:native_task({
      tool = opts.tool or "zig",
      args = build_args_for(mode, { output = output, graph_input = opts.input or "src/main.lua", graph_output = opts.graph_output or ".meteorite/graph/current", backend = opts.backend, hybrid_profile = opts.hybrid_profile, ["hybrid-profile"] = opts["hybrid-profile"], router_dispatch = opts.router_dispatch, ["router-dispatch"] = opts["router-dispatch"], optimize = opts.optimize, target = opts.target }),
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite " .. release_mode .. " release",
    })

    local assets = graph_mod.AssetSet.new()
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
      content = build_manifest(result, release_mode, output, contract, target_lua),
      generated = true,
      metadata = { mode = release_mode, graph_hash = result.graph_hash, contract = contract.format },
    }))
    if release_mode == "hybrid" then
      add_hybrid_lua_assets(ctx, assets, root, result.graph)
      add_runtime_source_asset(ctx, assets, root, target_lua)
    end
    return assets
  end,
}
