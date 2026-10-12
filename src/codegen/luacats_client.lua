--- Ambient LuaCATS declarations for the same public DTOs as the TS client.
--- No runtime module is produced or required: Hydronium/LuaX only includes the
--- generated .d.lua file in LuaLS's workspace library.
local luacats_client = {}

local function sorted_routes(graph)
  local routes = {}
  for _, route in ipairs((graph and graph.routes) or {}) do routes[#routes + 1] = route end
  table.sort(routes, function(a, b)
    return (tostring(a.method) .. " " .. tostring(a.raw_path) .. " " .. tostring(a.id)) < (tostring(b.method) .. " " .. tostring(b.raw_path) .. " " .. tostring(b.id))
  end)
  return routes
end

local function identifier(value)
  value = tostring(value or ""):gsub("[^%w_]", "_"):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if value == "" then value = "route" end
  if value:match("^%d") then value = "route_" .. value end
  return value
end

local function pascal(value)
  local out = ""
  for part in identifier(value):gmatch("[^_]+") do out = out .. part:sub(1, 1):upper() .. part:sub(2) end
  return out == "" and "Route" or out
end

local function route_name(route, seen)
  local meta = route.meta or route.openapi or {}
  local base = route.operation_id or route.operationId or meta.operationId
    or (tostring(route.method or "get"):lower() .. "_" .. tostring(route.raw_path or route.path or "route"))
  local name, n = identifier(base), 2
  local first = name
  while seen[name] do name = first .. "_" .. tostring(n); n = n + 1 end
  seen[name] = true
  return name
end

local lua_schema = require("codegen.lua_schema")
local schema_type = lua_schema.render
local sorted_keys = lua_schema.sorted_keys

local function response_schema(route)
  for _, status in ipairs(sorted_keys(route.responses)) do
    if tostring(status):match("^2") then
      local response = route.responses[status]
      if type(response) == "table" then return response.schema or response.json or response.body end
    end
  end
end

function luacats_client.emit(graph)
  local lines, seen = { "---@meta \"meteorite-client\"", "" }, {}
  for _, route in ipairs(sorted_routes(graph)) do
    local base = pascal(route_name(route, seen))
    if route.json_contract and route.json_contract.schema then
      lines[#lines + 1] = "---@alias " .. base .. "Request " .. schema_type(route.json_contract.schema)
    end
    lines[#lines + 1] = "---@alias " .. base .. "Response " .. schema_type(response_schema(route))
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

return luacats_client
