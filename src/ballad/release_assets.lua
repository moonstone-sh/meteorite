local graph_mod = require("ballad.graph")
local path = require("ballad.path")
local fs = require("ballad.fs")

local assets_mod = {}

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

local function file_exists(file_path)
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

function assets_mod.package_is_lua_cmodule(package)
  local kind = package.kind or ""
  if kind == "lua_cmodule" or kind == "cmodule" or kind == "native" then return true end
  if package.lua_api or package.lua_abi then
    local artifact_path = package.artifact_path or ""
    if artifact_path ~= "" and fs.is_dir(path.join(artifact_path, "files/lib/lua")) then return true end
  end
  return false
end

function assets_mod.package_is_lua_module(package)
  local kind = package.kind or ""
  return kind == "lua_module" or kind == "lib" or fs.is_dir(path.join(package.artifact_path or "", "files/share/lua"))
end

local function is_cross_target(target)
  return target and target ~= "" and target ~= "native"
end

function assets_mod.add_hybrid_lua_assets(ctx, assets, root, graph)
  copy_tree_assets(ctx, assets, root, ".meteorite/lua/inline", ".meteorite/lua/inline", "meteorite_lua_chunk")
  copy_tree_assets(ctx, assets, root, "src", "src", "meteorite_lua_source")
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

function assets_mod.add_runtime_tree_assets(ctx, assets, root, runtime_dir, target)
  -- The built Lua runtime is a directory (bin/, lib/, include/); add individual
  -- files so the Ballad sink can copy them (fs.copy_file handles files, not dirs).
  copy_tree_assets(ctx, assets, root, runtime_dir, "runtime/lua", "lua_runtime")
  for _, asset in ipairs(assets.assets or {}) do
    if asset.kind == "lua_runtime" then
      asset.metadata = asset.metadata or {}
      asset.metadata.target = target
    end
  end
end

function assets_mod.add_runtime_source_asset(ctx, assets, root, target_lua)
  if not target_lua or not target_lua.source_payload_path then return end
  local source_path = target_lua.source_payload_path
  local name = source_path:match("([^/]+)$") or "lua-source.tar.gz"
  add_file_asset(ctx, assets, root, source_path, path.join("runtime/source", name), "lua_runtime_source", { target = target_lua.target or "host" })
end

function assets_mod.add_package_assets(ctx, assets, packages, opts)
  opts = opts or {}
  for _, package in ipairs(packages or {}) do
    local artifact_path = package.artifact_path
    if artifact_path and artifact_path ~= "" then
      if assets_mod.package_is_lua_module(package) then
        copy_tree_assets(ctx, assets, artifact_path, "files/share/lua", "lua", "lua_module")
      end
      if not is_cross_target(opts.target) and assets_mod.package_is_lua_cmodule(package) then
        copy_tree_assets(ctx, assets, artifact_path, "files/lib/lua", "lib", "lua_cmodule")
      end
    end
  end
end

function assets_mod.add_target_cmodule_assets(ctx, assets, root, output_dir, target)
  if not output_dir or output_dir == "" then return end
  copy_tree_assets(ctx, assets, root or ".", path.join(output_dir, "lib/lua"), "lib", "lua_cmodule")
  for _, asset in ipairs(assets.assets or {}) do
    if asset.kind == "lua_cmodule" then
      asset.metadata = asset.metadata or {}
      asset.metadata.target = target
    end
  end
end

function assets_mod.add_static_assets(ctx, assets, static_root)
  if not fs.is_dir(static_root) then return 0 end
  local count = 0
  for _, file_path in ipairs(fs.list_files(static_root)) do
    local rel = path.relative(file_path, static_root)
    assets:add(ctx.graph:add_asset({
      kind = "meteorite_static_asset",
      source_path = file_path,
      virtual_path = path.join("static", rel),
      metadata = { release_static = true },
    }))
    count = count + 1
  end
  return count
end

function assets_mod.add_graph_assets(ctx, assets, root, source_dir, dest_dir)
  copy_tree_assets(ctx, assets, root or ".", source_dir, dest_dir or source_dir, "meteorite_graph")
end

function assets_mod.new_set()
  return graph_mod.AssetSet.new()
end

return assets_mod
