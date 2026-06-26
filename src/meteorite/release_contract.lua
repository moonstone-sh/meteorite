local release_assets = require("meteorite.release_assets")

local contract_mod = {}

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return root .. "/" .. value
end

local function file_exists(file_path)
  local f = io.open(file_path, "rb")
  if f then f:close(); return true end
  return false
end

function contract_mod.normalize_mode(mode)
  mode = mode or "hybrid"
  if mode == "hybrid" or mode == "release-hybrid" then return "release-hybrid", "hybrid" end
  if mode == "static" or mode == "release-static" then return "release-static", "static" end
  error("meteorite.release: unsupported mode `" .. tostring(mode) .. "`; expected hybrid or static")
end

function contract_mod.normalize_opts(opts)
  opts = opts or {}
  local project = opts.project or opts.moonstone_project
  if project then
    opts.root = opts.root or project.root
    opts.runtime = opts.runtime or project.runtime
    opts.packages = opts.packages or project.packages
    opts.target = opts.target or (project.runtime and project.runtime.target)
  end
  return opts
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

function contract_mod.for_graph(graph, release_mode)
  local refs = lua_references(graph)
  return {
    format = "meteorite.release_contract.v0",
    validation_mode = release_mode,
    graph_may_be_produced_by_lua = true,
    retained_lua_nodes = refs,
    requires_target_lua = release_mode == "hybrid" and #refs > 0,
  }
end

function contract_mod.fail_static_lua(ctx, refs)
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

local function runtime_source_from_opts(opts)
  local runtime = opts.runtime or {}
  return opts.lua_source
    or opts.runtime_source
    or runtime.source_payload_path
    or runtime.source_payload
    or runtime.source
    or os.getenv("METEORITE_LUA_SOURCE")
end

function contract_mod.target_from_opts(opts)
  local runtime = opts.runtime or {}
  return opts.target or runtime.target or runtime.abi_target
end

function contract_mod.is_cross_target(target)
  return target and target ~= "" and target ~= "native" and target ~= "any"
end

function contract_mod.validate_target_lua(ctx, root, contract, opts)
  if contract.validation_mode ~= "hybrid" then
    return { status = "not_required" }
  end
  local target = contract_mod.target_from_opts(opts)
  if not contract.requires_target_lua then
    return { status = "not_required", target = target }
  end

  local source = runtime_source_from_opts(opts)
  if contract_mod.is_cross_target(target) and (not source or source == "") then
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
    return { status = contract_mod.is_cross_target(target) and "target_build_required" or "source_payload_available", target = target, source_payload_path = source }
  end

  return { status = "host_env", target = target }
end

function contract_mod.validate_packages(ctx, contract, opts)
  local target = contract_mod.target_from_opts(opts)
  if contract.validation_mode ~= "hybrid" or not contract.requires_target_lua or not contract_mod.is_cross_target(target) then return end
  for _, package in ipairs(opts.packages or {}) do
    if release_assets.package_is_lua_cmodule(package) then
      if not package.source_payload_path or package.source_payload_path == "" then
        ctx.fail("meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot rebuild Lua C module `" .. tostring(package.name) .. "`: missing source_payload_path")
      end
      if not package.rockspec_payload_path or package.rockspec_payload_path == "" then
        ctx.fail("meteorite.release({ mode = 'hybrid', target = '" .. tostring(target) .. "' }) cannot rebuild Lua C module `" .. tostring(package.name) .. "`: missing rockspec_payload_path")
      end
    end
  end
end

return contract_mod
