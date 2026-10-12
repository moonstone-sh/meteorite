-- Shared structural LuaCATS mapping for client DTOs and route contexts.
local M = {}

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


M.render = schema_type
M.sorted_keys = sorted_keys
return M
