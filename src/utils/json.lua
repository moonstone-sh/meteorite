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

return json
