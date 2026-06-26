local zon = {}

local preferred = {
  "format", "meteorite_version", "graph_hash", "mode", "app", "name", "routes", "id", "method", "raw_path", "path", "segments",
  "kind", "value", "params", "query", "type", "max_len", "optional", "decode", "handler", "symbol", "module", "import", "source", "file", "line", "column",
}
local rank = {}
for i, key in ipairs(preferred) do rank[key] = i end

local function keys_of(value)
  local keys = {}
  for key, _ in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ra = rank[a] or 10000
    local rb = rank[b] or 10000
    if ra ~= rb then return ra < rb end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function is_array(value)
  local max = 0
  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" then return false end
    if key > max then max = key end
    count = count + 1
  end
  return count == max
end

local function quote(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local emit
local function emit_array(value, indent)
  if #value == 0 then return ".{}" end
  local next_indent = indent .. "    "
  local lines = { ".{" }
  for _, item in ipairs(value) do
    lines[#lines + 1] = next_indent .. emit(item, next_indent) .. ","
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

local function emit_object(value, indent)
  local next_indent = indent .. "    "
  local lines = { ".{" }
  for _, key in ipairs(keys_of(value)) do
    local item = value[key]
    if type(item) ~= "function" then
      lines[#lines + 1] = next_indent .. "." .. key .. " = " .. emit(item, next_indent) .. ","
    end
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

emit = function(value, indent)
  indent = indent or ""
  local kind = type(value)
  if kind == "string" then return quote(value) end
  if kind == "number" then return tostring(value) end
  if kind == "boolean" then return tostring(value) end
  if kind == "nil" then return "null" end
  if kind == "function" then error("cannot serialize Lua function to ZON") end
  if kind == "table" then
    if value.__meteorite_enum then return "." .. value.value end
    if is_array(value) then return emit_array(value, indent) end
    return emit_object(value, indent)
  end
  error("cannot serialize " .. kind .. " to ZON")
end

function zon.encode(value)
  return emit(value, "") .. "\n"
end

return zon
