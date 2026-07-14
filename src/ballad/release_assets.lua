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

local function normalize_relative(value)
  local out = {}
  for part in tostring(value or ""):gmatch("[^/]+") do
    if part == ".." then
      if #out > 0 then out[#out] = nil end
    elseif part ~= "." and part ~= "" then
      out[#out + 1] = part
    end
  end
  return table.concat(out, "/")
end

local function resolve_project_file(root, rel_path)
  if not rel_path or rel_path == "" then return nil, nil end
  local root_prefix = tostring(root or "."):gsub("/+$", "") .. "/"
  local candidates = rel_path:sub(1, 1) == "/" and { rel_path } or { join(root or ".", rel_path), rel_path }
  for _, full in ipairs(candidates) do
    if file_exists(full) then
      local virtual_path = full:sub(1, #root_prefix) == root_prefix and full:sub(#root_prefix + 1) or rel_path
      if virtual_path:sub(1, 1) == "/" then return nil, nil end
      return full, normalize_relative(virtual_path)
    end
  end
  return nil, nil
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

local function read_file(file_path)
  local file = io.open(file_path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function project_lua_candidates(module)
  if not module or module == "" then return {} end
  local rel = tostring(module):gsub("%.", "/")
  return {
    "src/" .. rel .. ".lua",
    "src/" .. rel .. "/init.lua",
  }
end

local function scan_requires(source)
  local modules = {}
  source = tostring(source or "")
  for quote, module in source:gmatch("require%s*%(%s*(['\"])([%w_%.%-]+)%1%s*%)") do
    if quote and module then modules[#modules + 1] = module end
  end
  for quote, module in source:gmatch("require%s+(['\"])([%w_%.%-]+)%1") do
    if quote and module then modules[#modules + 1] = module end
  end
  return modules
end

local function add_project_lua_file(ctx, assets, root, rel_path, kind, metadata, seen)
  if not rel_path or rel_path == "" then return end
  if not rel_path:match("%.lua$") then return end
  local full, virtual_path = resolve_project_file(root, rel_path)
  if not full then return end
  if seen[virtual_path] then return end
  seen[virtual_path] = true
  assets:add(ctx.graph:add_asset({
    kind = kind or "file",
    source_path = full,
    virtual_path = virtual_path,
    metadata = metadata or {},
  }))
  local source = read_file(full)
  for _, module in ipairs(scan_requires(source)) do
    for _, candidate in ipairs(project_lua_candidates(module)) do
      add_project_lua_file(ctx, assets, root, candidate, "meteorite_lua_module", { required_by = virtual_path, module = module }, seen)
    end
  end
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
  local seen = {}
  local nodes = {}
  for _, route in ipairs(graph.routes or {}) do nodes[#nodes + 1] = route end
  for _, message in ipairs(graph.messages or {}) do nodes[#nodes + 1] = message end
  for _, route in ipairs(nodes) do
    if route.handler and route.handler.kind == "inline_lua" then
      local chunk_path = route.handler.lifted and route.handler.lifted.chunk_path
      add_project_lua_file(ctx, assets, root, chunk_path, "meteorite_lua_chunk", { route = route.id }, seen)
    elseif route.handler and route.handler.kind == "lua" then
      local route_path = lua_file_path(route.handler)
      add_project_lua_file(ctx, assets, root, route_path, "meteorite_lua_handler", { route = route.id }, seen)
    end
  end
  for _, plugin in ipairs(graph.plugins or {}) do
    if plugin.handler and plugin.handler.kind == "inline_lua" then
      local chunk_path = plugin.handler.lifted and plugin.handler.lifted.chunk_path
      add_project_lua_file(ctx, assets, root, chunk_path, "meteorite_lua_chunk", { plugin = plugin.id }, seen)
    elseif plugin.handler and plugin.handler.kind == "lua" then
      local plugin_path = lua_file_path(plugin.handler)
      add_project_lua_file(ctx, assets, root, plugin_path, "meteorite_lua_plugin", { plugin = plugin.id }, seen)
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
  local output_root = output_dir
  if not fs.is_dir(output_root) then output_root = join(root or ".", output_dir) end
  copy_tree_assets(ctx, assets, output_root, "lib/lua", "lib", "lua_cmodule")
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

function assets_mod.assert_static_release_assets(ctx, assets)
  local forbidden_kinds = {
    lua_runtime = true,
    lua_runtime_source = true,
    lua_module = true,
    lua_cmodule = true,
    meteorite_lua_chunk = true,
    meteorite_lua_handler = true,
    meteorite_lua_module = true,
    meteorite_lua_plugin = true,
    meteorite_lua_source = true,
  }
  local found = {}
  for _, asset in ipairs((assets and assets.assets) or {}) do
    local kind = asset.kind or ""
    local virtual_path = asset.virtual_path or asset.dest or ""
    if forbidden_kinds[kind]
      or tostring(virtual_path):match("^runtime/lua/")
      or tostring(virtual_path):match("^runtime/source/")
      or tostring(virtual_path):match("^%.meteorite/lua/")
      or tostring(virtual_path):match("^lua/")
      or tostring(virtual_path):match("^lib/%d") then
      found[#found + 1] = tostring(kind) .. " " .. tostring(virtual_path)
    end
  end
  if #found == 0 then return end
  table.sort(found)
  local lines = {
    "meteorite.release({ mode = 'static' }) attempted to package Lua runtime artifacts.",
    "",
    "Forbidden assets:",
  }
  for _, item in ipairs(found) do lines[#lines + 1] = "  - " .. item end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Remediation: only package these assets for hybrid releases, or remove retained Lua runtime nodes from the static graph."
  ctx.fail(table.concat(lines, "\n"))
end

function assets_mod.new_set()
  return graph_mod.AssetSet.new()
end

return assets_mod
