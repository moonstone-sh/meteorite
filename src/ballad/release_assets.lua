local graph_mod = require("ballad.graph")
local path = require("ballad.path")
local fs = require("ballad.fs")
-- Required eagerly: the Ballad plugin loader restores package.path after
-- loading this module, so a lazy require would not find it.
local flavor = require("meteorite.flavor")

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

-- `target` (a flavor) projects flavor-tagged files the way `moon sync`
-- does: `lexer@lua54.lua` ships as `lexer.lua` and losing variants are left
-- out, so the release's plain `require` needs no variant searcher.
local function copy_tree_assets(ctx, assets, root, source_dir, dest_dir, kind, target)
  local full_dir = join(root, source_dir)
  if not fs.is_dir(full_dir) then return end
  local rels, by_rel = {}, {}
  for _, file_path in ipairs(fs.list_files(full_dir)) do
    local rel = path.relative(file_path, full_dir)
    rels[#rels + 1] = rel
    by_rel[rel] = file_path
  end
  local entries
  if target then
    entries = flavor.project_files(rels, target)
  else
    entries = {}
    for _, rel in ipairs(rels) do entries[#entries + 1] = { source = rel, path = rel } end
  end
  for _, entry in ipairs(entries) do
    local metadata = nil
    if entry.source ~= entry.path then metadata = { flavor_variant = entry.source, flavor = target.id } end
    assets:add(ctx.graph:add_asset({
      kind = kind or "file",
      source_path = fs.readlink(by_rel[entry.source]),
      virtual_path = path.join(dest_dir or source_dir, entry.path),
      metadata = metadata,
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

local function add_project_lua_file(ctx, assets, root, rel_path, kind, metadata, seen, target, provided)
  if not rel_path or rel_path == "" then return end
  if not rel_path:match("%.lua$") then return end
  -- A Lua payload (lua_modules = "inputs") that provides this module wins:
  -- `src/?.lua` precedes `lua/?.lua` on the server's path, so shipping the
  -- project copy too would shadow the payload's.
  if provided and kind == "meteorite_lua_module" and metadata and provided[metadata.module] then return end
  -- A required project module ships under its plain name with the content of
  -- the variant the target flavor selects (handler paths were already
  -- resolved by graph_prepare and are shipped as-is).
  local source_rel = rel_path
  if target and kind == "meteorite_lua_module" then
    local chosen, tags = flavor.resolve_file(rel_path, target, root)
    if tags then
      source_rel = chosen
      metadata = metadata or {}
      metadata.flavor_variant = chosen
      metadata.flavor = target.id
    end
  end
  local full, virtual_path = resolve_project_file(root, source_rel)
  if not full then return end
  -- Module candidates are always project-relative (`src/x.lua`).
  if source_rel ~= rel_path then virtual_path = normalize_relative(rel_path) end
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
      add_project_lua_file(ctx, assets, root, candidate, "meteorite_lua_module", { required_by = virtual_path, module = module }, seen, target, provided)
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

function assets_mod.add_hybrid_lua_assets(ctx, assets, root, graph, target, provided)
  local seen = {}
  local nodes = {}
  for _, route in ipairs(graph.routes or {}) do nodes[#nodes + 1] = route end
  for _, message in ipairs(graph.messages or {}) do nodes[#nodes + 1] = message end
  for _, route in ipairs(nodes) do
    if route.handler and route.handler.kind == "inline_lua" then
      local chunk_path = route.handler.lifted and route.handler.lifted.chunk_path
      add_project_lua_file(ctx, assets, root, chunk_path, "meteorite_lua_chunk", { route = route.id }, seen, target, provided)
    elseif route.handler and route.handler.kind == "lua" then
      local route_path = lua_file_path(route.handler)
      add_project_lua_file(ctx, assets, root, route_path, "meteorite_lua_handler", { route = route.id }, seen, target, provided)
    end
  end
  for _, plugin in ipairs(graph.plugins or {}) do
    if plugin.handler and plugin.handler.kind == "inline_lua" then
      local chunk_path = plugin.handler.lifted and plugin.handler.lifted.chunk_path
      add_project_lua_file(ctx, assets, root, chunk_path, "meteorite_lua_chunk", { plugin = plugin.id }, seen, target, provided)
    elseif plugin.handler and plugin.handler.kind == "lua" then
      local plugin_path = lua_file_path(plugin.handler)
      add_project_lua_file(ctx, assets, root, plugin_path, "meteorite_lua_plugin", { plugin = plugin.id }, seen, target, provided)
    end
  end
end

local function valid_module_path(rel)
  if not rel:match("%.lua$") then return false end
  for segment in rel:sub(1, -5):gmatch("[^/]+") do
    if not segment:match("^[%a_][%w_]*$") then return false end
  end
  return true
end

local function module_of(rel)
  local name = rel:gsub("%.lua$", ""):gsub("/init$", "")
  return (name:gsub("/", "."))
end

-- Ships the Lua modules an upstream node produced (for example a Quaver
-- build) under `lua/`, in place of whole package trees. Each `.lua` asset
-- whose path is a module path (`a/b.lua`, optionally under `lua/`) ships as
-- `lua/a/b.lua`; other assets (reports, manifests) are ignored. Returns the
-- set of provided module names.
function assets_mod.add_payload_lua_assets(ctx, assets, inputs)
  local provided, count = {}, 0
  local by_path = {}
  for _, input in ipairs(inputs or {}) do
    for _, asset in ipairs((input and input.assets) or {}) do
      local rel = normalize_relative((asset.virtual_path or ""):gsub("^lua/", ""))
      if rel:find("@", 1, true) and rel:match("%.lua$") then
        ctx.fail("meteorite.release: Lua payload asset `" .. rel .. "` is a flavor variant; select variants before the release (Quaver does this for its target flavor)")
      end
      if valid_module_path(rel) then
        if by_path[rel] then ctx.fail("meteorite.release: Lua payload ships `lua/" .. rel .. "` twice") end
        by_path[rel] = true
        assets:add(ctx.graph:add_asset({
          kind = "lua_module",
          source_path = asset.source_path,
          content = asset.content,
          generated = asset.content ~= nil or nil,
          virtual_path = "lua/" .. rel,
          metadata = { lua_payload = true, payload_path = asset.virtual_path },
        }))
        provided[module_of(rel)] = true
        count = count + 1
      end
    end
  end
  if count == 0 then
    ctx.fail("meteorite.release: lua_modules = \"inputs\" but the input node produced no Lua modules")
  end
  return provided, count
end

local STANDARD_MODULES = {
  _G = true, coroutine = true, debug = true, io = true, math = true, os = true, package = true,
  string = true, table = true, utf8 = true, bit = true, bit32 = true, jit = true, ffi = true,
  ["string.buffer"] = true, ["table.new"] = true, ["table.clear"] = true,
}

local function asset_source(asset)
  if asset.content then return asset.content end
  return read_file(asset.source_path or "") or ""
end

-- Every literal `require` in the Lua the release ships must resolve to a
-- shipped Lua module (project `src/` or `lua/`), a shipped C module, a
-- standard library, or an entry of `externals`. Dynamic requires are not
-- checked. Returns the number of modules checked.
function assets_mod.check_lua_closure(ctx, assets, externals)
  local available, sources = {}, {}
  for name in pairs(STANDARD_MODULES) do available[name] = true end
  for _, name in ipairs(externals or {}) do available[name] = true end
  for _, asset in ipairs((assets and assets.assets) or {}) do
    local vp, kind = asset.virtual_path or "", asset.kind or ""
    if kind == "lua_module" and vp:match("^lua/") then
      available[module_of(vp:sub(5))] = true
      sources[#sources + 1] = asset
    elseif kind == "lua_cmodule" then
      local rel = vp:gsub("^lib/", ""):gsub("^%d+%.%d+/", ""):gsub("%.[%a]+$", "")
      available[(rel:gsub("/", "."))] = true
    elseif kind:match("^meteorite_lua_") then
      if vp:match("^src/") then available[module_of(vp:sub(5))] = true end
      sources[#sources + 1] = asset
    end
  end
  local missing, seen = {}, {}
  for _, asset in ipairs(sources) do
    for _, module in ipairs(scan_requires(asset_source(asset))) do
      local key = module .. "\0" .. (asset.virtual_path or "")
      if not available[module] and not module:match("^jit%.") and not seen[key] then
        seen[key] = true
        missing[#missing + 1] = ("  - %s (required by %s)"):format(module, asset.virtual_path or "?")
      end
    end
  end
  if #missing > 0 then
    table.sort(missing)
    ctx.fail(table.concat({
      "meteorite.release: the Lua payload does not provide every module the release requires.",
      "",
      "Missing:",
      table.concat(missing, "\n"),
      "",
      "Add them to the payload, or list modules the server's environment provides in `lua_externals`.",
    }, "\n"))
  end
  return #sources
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
      if opts.lua ~= false and assets_mod.package_is_lua_module(package) then
        copy_tree_assets(ctx, assets, artifact_path, "files/share/lua", "lua", "lua_module", opts.flavor)
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
