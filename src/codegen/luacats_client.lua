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

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function lua_key(value)
  if tostring(value):match("^[A-Za-z_][A-Za-z0-9_]*$") then return value end
  return "[" .. string.format("%q", tostring(value)) .. "]"
end

local function literal(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if value == nil then return "nil" end
  return "any"
end

local function schema_type(schema, root, resolving)
  if type(schema) ~= "table" then return "any" end
  root, resolving = root or schema, resolving or {}
  local ref = type(schema["$ref"]) == "string" and schema["$ref"]:match("^#/%$defs/(.+)$") or nil
  if ref then
    if resolving[ref] or not (root["$defs"] and root["$defs"][ref]) then return "any" end
    resolving[ref] = true
    local value = schema_type(root["$defs"][ref], root, resolving)
    resolving[ref] = nil
    return value
  end
  if type(schema.enum) == "table" then
    local values = {}
    for _, value in ipairs(schema.enum) do values[#values + 1] = literal(value) end
    table.sort(values)
    return #values > 0 and table.concat(values, "|") or "never"
  end
  if type(schema.anyOf) == "table" then
    local values = {}
    for _, value in ipairs(schema.anyOf) do values[#values + 1] = schema_type(value, root, resolving) end
    table.sort(values)
    return #values > 0 and table.concat(values, "|") or "any"
  end
  if schema.type == "string" then return "string" end
  if schema.type == "integer" or schema.type == "number" then return "number" end
  if schema.type == "boolean" then return "boolean" end
  if schema.type == "null" then return "nil" end
  if schema.type == "array" then return schema_type(schema.items, root, resolving) .. "[]" end
  if schema.type == "object" or schema.properties then
    local required, fields = {}, {}
    for _, name in ipairs(schema.required or {}) do required[name] = true end
    for _, name in ipairs(sorted_keys(schema.properties)) do
      fields[#fields + 1] = lua_key(name) .. (required[name] and ": " or "?: ") .. schema_type(schema.properties[name], root, resolving)
    end
    return "{ " .. table.concat(fields, ", ") .. " }"
  end
  return "any"
end

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
