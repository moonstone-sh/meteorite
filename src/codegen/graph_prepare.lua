--- Graph preparation and capability reference validation before Zig emission.

local helpers = require("codegen.helpers")
local lifter = require("codegen.lifter")
local static_compiler = require("codegen.static")
local flavor = require("meteorite.flavor")

local graph_prepare = {}

local function graph_nodes(graph)
  return graph.nodes or graph.routes or {}
end

function graph_prepare.scan_capabilities(source)
  local refs, seen = {}, {}
  local function add(kind, name)
    local key = kind .. "." .. name
    if seen[key] then return end
    seen[key] = true
    refs[#refs + 1] = { kind = kind, name = name }
  end
  for name in tostring(source):gmatch("c:http%(%s*[\"']([^\"']+)[\"']%s*%)") do add("http", name) end
  for name in tostring(source):gmatch("c:auth%(%s*[\"']([^\"']+)[\"']%s*%)") do add("auth", name) end
  for name in tostring(source):gmatch("c:zig%(%s*[\"']([^\"']+)[\"']%s*%)") do add("zig", name) end
  table.sort(refs, function(a, b) return (a.kind .. a.name) < (b.kind .. b.name) end)
  return refs
end

function graph_prepare.validate_capability_refs(graph, route, refs)
  for _, ref in ipairs(refs) do
    if not (graph.capabilities and graph.capabilities[ref.kind] and graph.capabilities[ref.kind][ref.name]) then
      error(table.concat({
        "route uses undeclared " .. ref.kind:upper() .. " capability `" .. ref.name .. "`",
        "",
        "route:",
        "  " .. route.method .. " " .. route.raw_path,
        "",
        "source:",
        "  " .. tostring(route.source.file) .. ":" .. tostring(route.source.line or 0) .. ":" .. tostring(route.source.column or 1),
        "",
        "hint:",
        "  declare it on the app with app:capability(\"" .. ref.kind .. "\", { " .. ref.name .. " = { ... } })",
      }, "\n"))
    end
  end
end

--- Point an `m.lua(...)` handler at the flavor variant the embedded Lua
--- will load (`src/app/x.lua` -> `src/app/x@lua54.lua`). The server
--- `loadfile`s handler paths, which bypasses both `moon sync`'s projection
--- and any runtime searcher, so the choice has to be made here.
function graph_prepare.resolve_lua_variant(route, output, target)
  local declared = route.handler.path
  if type(declared) ~= "string" or not declared:match("%.lua$") then return end
  local root = declared:match("^/") and nil or helpers.project_root_from_output(output)
  local ok, resolved, tags = pcall(flavor.resolve_file, declared, target, root)
  if not ok then
    error(table.concat({
      "cannot choose a Lua flavor variant for handler `" .. tostring(route.id) .. "`",
      "",
      "route:",
      "  " .. tostring(route.method) .. " " .. tostring(route.raw_path),
      "",
      "reason:",
      "  " .. tostring(resolved),
    }, "\n"), 0)
  end
  if tags then
    route.handler.declared_path = declared
    route.handler.path = resolved
    route.handler.flavor = target and target.id or nil
  end
end

--- Does the project keep flavor variants of its own modules under src/?
--- Those are found at run time by `require`, not by handler path.
function graph_prepare.project_has_variants(root)
  if not io.popen then return false end
  local src = helpers.path_join(root, "src")
  local pipe = io.popen("find " .. string.format("%q", src) .. " -name '*@*.lua' 2>/dev/null")
  if not pipe then return false end
  local found = false
  for line in pipe:lines() do
    if flavor.is_variant(line) then found = true break end
  end
  pipe:close()
  return found
end

function graph_prepare.prepare_graph(graph, output, mode)
  local lua_target
  for _, plugin in ipairs(graph.plugins or {}) do
    if type(plugin.execute) ~= "function" then
      error("plugin " .. tostring(plugin.id) .. " must declare an execute function")
    end
    local lifted = lifter.lift_plugin(plugin, { output = output })
    plugin.handler = { kind = "inline_lua", lifted = lifted }
    plugin.execute = nil
  end
  for _, route in ipairs(graph_nodes(graph)) do
    local plugin_ids = {}
    for _, plugin in ipairs(route.scope.plugins or {}) do
      if type(plugin) == "table" and plugin.__meteorite_plugin then
        plugin_ids[#plugin_ids + 1] = plugin.id
      elseif type(plugin) == "string" then
        plugin_ids[#plugin_ids + 1] = plugin
      end
    end
    route.scope.plugins = plugin_ids
    if route.handler.kind == "zig_file" and not tostring(route.handler.path or ""):match("^/") then
      route.handler.source_path = helpers.path_join(helpers.project_root_from_output(output), route.handler.path)
    end
    static_compiler.prepare_route(route, output, mode)
    if route.handler.kind == "inline_lua" then
      local lifted = lifter.lift(route, { output = output, mode = mode })
      route.handler.lifted = lifted
      local file = io.open(lifted.chunk_path, "rb")
      local source = file and file:read("*a") or ""
      if file then file:close() end
      route.capabilities = graph_prepare.scan_capabilities(source)
      graph_prepare.validate_capability_refs(graph, route, route.capabilities)
      route.runtime.requires_lua = true
      route.runtime.execution_class = "lua"
      route.execution.class = "lua"
      route.execution.requires_lua = true
      for _, ref in ipairs(route.capabilities) do
        if ref.kind == "http" then route.runtime.requires_http = true end
        if ref.kind == "auth" then route.runtime.requires_auth = true end
        if ref.kind == "zig" then route.runtime.requires_zig_capability = true end
      end
    elseif route.handler.kind == "lua" then
      if flavor.variants() then
        lua_target = lua_target or flavor.target()
        graph_prepare.resolve_lua_variant(route, output, lua_target)
      end
      -- Installed package handlers can resolve to absolute Moonstone/CAS paths.
      -- A release must load its own copy after deployment, never that host path.
      local source_path = route.handler.path or route.handler.module
      if tostring(mode):match("^release") and tostring(source_path):match("^/") then
        local source, err = helpers.read_file(source_path)
        if not source then error("cannot package Lua handler " .. tostring(source_path) .. ": " .. tostring(err)) end
        local runtime_path = ".meteorite/lua/handlers/" .. helpers.zig_ident(route.id) .. ".lua"
        local target = helpers.path_join(helpers.project_root_from_output(output), runtime_path)
        helpers.mkdir_p(helpers.dirname(target))
        helpers.write_file(target, source)
        route.handler.source_path = source_path
        route.handler.path = runtime_path
      end
      route.runtime.requires_lua = true
      route.runtime.execution_class = "lua"
      route.execution.class = "lua"
      route.execution.requires_lua = true
    end
  end
  -- Development servers load the project's own modules straight from src/,
  -- so a project with variant modules gets Moonstone's runtime searcher in
  -- the embedded Lua (graph.zig `lua_variant_flavor`). Releases ship those
  -- modules already projected (ballad/release_assets.lua) and need none.
  if not tostring(mode):match("^release") and flavor.variants() then
    local requires_lua = false
    for _, route in ipairs(graph_nodes(graph)) do
      if route.runtime and route.runtime.requires_lua then requires_lua = true break end
    end
    if requires_lua and graph_prepare.project_has_variants(helpers.project_root_from_output(output)) then
      graph.lua_variant_flavor = lua_target or flavor.target()
    end
  end
  return graph
end

return graph_prepare
