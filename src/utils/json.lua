--- Minimal JSON encoder for Lua.
--- Handles nil, boolean, number, string, array, and object types.
---
--- @class JsonModule
--- @field encode fun(value: any): string  Encode a Lua value as JSON

---@type JsonModule
local json = {}

local function escape(value)
  return tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

local function is_array(value)
  local max, count = 0, 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    if key > max then max = key end
    count = count + 1
  end
  return max == count
end

local encode
--- Encode a Lua value as JSON.
---@param value any  Value to encode
---@return string  JSON text
encode = function(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. escape(value) .. '"' end
  if kind == "table" then
    local parts = {}
    if is_array(value) then
      for i = 1, #value do parts[#parts + 1] = encode(value[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key, _ in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
      parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode " .. kind .. " as json")
end

json.encode = encode


--- Encode a Lua value as pretty-printed JSON with 2-space indentation.
---@param value any  Value to encode
---@param indent? string  Current indentation (internal use)
---@return string  Pretty-printed JSON text
local function pretty_encode(value, indent)
  indent = indent or ""
  local next_indent = indent .. "  "
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. escape(value) .. '"' end
  if kind == "table" then
    if is_array(value) then
      if #value == 0 then return "[]" end
      local parts = {}
      for i = 1, #value do parts[#parts + 1] = next_indent .. pretty_encode(value[i], next_indent) end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for key, _ in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if #keys == 0 then return "{}" end
    local parts = {}
    for _, key in ipairs(keys) do
      parts[#parts + 1] = next_indent .. encode(tostring(key)) .. ": " .. pretty_encode(value[key], next_indent)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  error("cannot encode " .. kind .. " as json")
end

json.pretty_encode = pretty_encode

return json
