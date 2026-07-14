--- Zig capability config emission.

local helpers = require("codegen.helpers")

local graph_capabilities = {}

function graph_capabilities.is_array_table(value)
  if type(value) ~= "table" then return false end
  local keys = {}
  for k, _ in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
  end)
  for i, k in ipairs(keys) do
    if k ~= i then return false end
  end
  return #keys > 0
end

function graph_capabilities.value_to_zig(value, indent)
  indent = indent or ""
  local value_type = type(value)
  if value_type == "string" then return helpers.zig_string(value) end
  if value_type == "number" then
    if value == math.floor(value) then
      return string.format("%d", value)
    end
    return string.format("%g", value)
  end
  if value_type == "boolean" then return value and "true" or "false" end
  if value_type ~= "table" then return "null" end
  if graph_capabilities.is_array_table(value) then
    local items = {}
    for _, item in ipairs(value) do
      items[#items + 1] = graph_capabilities.value_to_zig(item, indent .. "    ")
    end
    return ".{ " .. table.concat(items, ", ") .. " }"
  end
  local keys = {}
  for key, _ in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  local fields = {}
  for _, key in ipairs(keys) do
    fields[#fields + 1] = "." .. helpers.zig_ident(key) .. " = " .. graph_capabilities.value_to_zig(value[key], indent .. "    ")
  end
  return ".{" .. "\n" .. indent .. "    " .. table.concat(fields, "," .. "\n" .. indent .. "    ") .. "\n" .. indent .. "}"
end

function graph_capabilities.emit(graph, lines)
  lines[#lines + 1] = "pub const capabilities = struct {"
  local kinds = { "http", "auth", "zig" }
  for _, kind in ipairs(kinds) do
    lines[#lines + 1] = "    pub const " .. helpers.zig_ident(kind) .. " = struct {"
    local configs = (graph.capabilities or {})[kind] or {}
    local names = {}
    for name, _ in pairs(configs) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      lines[#lines + 1] = "        pub const " .. helpers.zig_ident(name) .. " = " .. graph_capabilities.value_to_zig(configs[name], "        ") .. ";"
    end
    lines[#lines + 1] = "    };"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
end

return graph_capabilities
