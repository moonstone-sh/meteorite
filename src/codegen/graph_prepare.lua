--- Graph preparation and capability reference validation before Zig emission.

local helpers = require("codegen.helpers")
local lifter = require("codegen.lifter")
local static_compiler = require("codegen.static")

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

function graph_prepare.prepare_graph(graph, output, mode)
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
      route.runtime.requires_lua = true
      route.runtime.execution_class = "lua"
      route.execution.class = "lua"
      route.execution.requires_lua = true
    end
  end
  return graph
end

return graph_prepare
