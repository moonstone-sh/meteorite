local lua_client = {}

local function sorted_routes(graph)
  local routes = {}
  for _, route in ipairs((graph and graph.routes) or {}) do
    routes[#routes + 1] = route
  end
  table.sort(routes, function(a, b)
    local left = tostring(a.method or "") .. " " .. tostring(a.raw_path or a.path or "") .. " " .. tostring(a.id or "")
    local right = tostring(b.method or "") .. " " .. tostring(b.raw_path or b.path or "") .. " " .. tostring(b.id or "")
    return left < right
  end)
  return routes
end

local function sorted_messages(graph)
  local messages = {}
  for _, route in ipairs((graph and graph.messages) or {}) do
    messages[#messages + 1] = route
  end
  table.sort(messages, function(a, b)
    local left = tostring((a.message and a.message.name) or "") .. " " .. tostring(a.id or "")
    local right = tostring((b.message and b.message.name) or "") .. " " .. tostring(b.id or "")
    return left < right
  end)
  return messages
end

local function identifier(value)
  value = tostring(value or "")
  value = value:gsub("[^%w_]+", "_"):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if value == "" then value = "route" end
  if value:match("^%d") then value = "route_" .. value end
  return value
end

local function route_name(route, seen)
  local meta = route.meta or route.openapi or {}
  local candidate = route.operation_id or route.operationId or meta.operationId
  if not candidate and route.message and route.message.name then candidate = route.message.name end
  if not candidate then candidate = tostring(route.method or "GET"):lower() .. "_" .. tostring(route.raw_path or route.path or "/") end
  local name = identifier(candidate)
  local base = name
  local suffix = 2
  while seen[name] do
    name = base .. "_" .. tostring(suffix)
    suffix = suffix + 1
  end
  seen[name] = true
  return name
end

local function message_name(route, seen)
  local candidate = route.operation_id or route.operationId
  if not candidate and route.message and route.message.name then candidate = route.message.name end
  if not candidate then candidate = route.id or route.canonical_id or "message" end
  local name = identifier(candidate)
  local base = name
  local suffix = 2
  while seen[name] do
    name = base .. "_" .. tostring(suffix)
    suffix = suffix + 1
  end
  seen[name] = true
  return name
end

local function quote(value)
  return string.format("%q", tostring(value or ""))
end

function lua_client.emit(graph, opts)
  opts = opts or {}
  local module_name = opts.module_name or "client"
  local lines = {
    "local " .. identifier(module_name) .. " = {}",
    "",
    "local function encode(value)",
    "  return tostring(value):gsub(\"([^%w%-%._~])\", function(char)",
    "    return string.format(\"%%%02X\", string.byte(char))",
    "  end)",
    "end",
    "",
    "local function encode_path(value)",
    "  return tostring(value):gsub(\"([^%w%-%._~/])\", function(char)",
    "    return string.format(\"%%%02X\", string.byte(char))",
    "  end)",
    "end",
    "",
    "local function apply_path(template, params)",
    "  params = params or {}",
    "  return (template:gsub(\":([%a_][%w_]*)%*\", function(name)",
    "    local value = params[name]",
    "    if value == nil then error(\"missing path param `\" .. name .. \"`\") end",
    "    return encode_path(value)",
    "  end):gsub(\":([%a_][%w_]*)\", function(name)",
    "    local value = params[name]",
    "    if value == nil then error(\"missing path param `\" .. name .. \"`\") end",
    "    return encode(value)",
    "  end):gsub(\"%*$\", function()",
    "    local value = params.wildcard",
    "    if value == nil then error(\"missing path param `wildcard`\") end",
    "    return encode_path(value)",
    "  end))",
    "end",
    "",
    "local function append_query(path, query)",
    "  local parts = {}",
    "  for key, value in pairs(query or {}) do",
    "    if value ~= nil then parts[#parts + 1] = encode(key) .. \"=\" .. encode(value) end",
    "  end",
    "  table.sort(parts)",
    "  if #parts == 0 then return path end",
    "  return path .. \"?\" .. table.concat(parts, \"&\")",
    "end",
    "",
    "function " .. identifier(module_name) .. ".new(transport)",
    "  transport = transport or {}",
    "  assert(type(transport.request) == \"function\", \"Meteorite Lua client requires transport.request(opts)\")",
    "  return setmetatable({ _request = transport.request }, { __index = " .. identifier(module_name) .. " })",
    "end",
    "",
    identifier(module_name) .. ".routes = {",
  }

  local seen = {}
  local route_entries = {}
  for _, route in ipairs(sorted_routes(graph)) do
    local name = route_name(route, seen)
    route_entries[#route_entries + 1] = { name = name, route = route }
    lines[#lines + 1] = string.format("  %s = { method = %s, path = %s },", name, quote(route.method), quote(route.raw_path or route.path))
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local message_entries = {}
  lines[#lines + 1] = identifier(module_name) .. ".messages = {"
  for _, route in ipairs(sorted_messages(graph)) do
    local name = message_name(route, seen)
    local message = route.message and route.message.name or route.id or route.canonical_id
    message_entries[#message_entries + 1] = { name = name, route = route, message = message }
    lines[#lines + 1] = string.format("  %s = { message = %s },", name, quote(message))
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  for _, entry in ipairs(route_entries) do
    local route = entry.route
    lines[#lines + 1] = "function " .. identifier(module_name) .. ":" .. entry.name .. "(args)"
    lines[#lines + 1] = "  args = args or {}"
    lines[#lines + 1] = "  local path = append_query(apply_path(" .. quote(route.raw_path or route.path) .. ", args.params), args.query)"
    lines[#lines + 1] = "  return self._request({ method = " .. quote(route.method) .. ", path = path, headers = args.headers, body = args.body })"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
  end

  for _, entry in ipairs(message_entries) do
    lines[#lines + 1] = "function " .. identifier(module_name) .. ":" .. entry.name .. "(args)"
    lines[#lines + 1] = "  args = args or {}"
    lines[#lines + 1] = "  return self._request({ message = " .. quote(entry.message) .. ", metadata = args.metadata, body = args.body, content_type = args.content_type })"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "return " .. identifier(module_name)
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function lua_client.route_names(graph)
  local seen = {}
  local names = {}
  for _, route in ipairs(sorted_routes(graph)) do
    names[#names + 1] = route_name(route, seen)
  end
  for _, route in ipairs(sorted_messages(graph)) do
    names[#names + 1] = message_name(route, seen)
  end
  return names
end

return lua_client
