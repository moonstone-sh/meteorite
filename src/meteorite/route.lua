local route = {}

local function source_info(level)
  local info = debug.getinfo(level or 3, "Sl") or {}
  local file = info.short_src or info.source or "?"
  if file:sub(1, 1) == "@" then file = file:sub(2) end
  return { file = file, line = info.currentline or 0, column = 1 }
end

local function parse_path(path)
  assert(type(path) == "string" and path ~= "", "route path must be a non-empty string")
  assert(path:sub(1, 1) == "/", "route path must start with /")
  if path == "/" then return {} end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    assert(segment ~= "", "empty route segment in " .. path)
    assert(segment ~= "*", "wildcard routes are not supported in Meteorite v0.1")
    if segment:sub(1, 1) == ":" then
      local name = segment:sub(2)
      assert(name:match("^[%a_][%w_]*$"), "invalid path param name: " .. name)
      segments[#segments + 1] = { kind = "param", name = name }
    else
      segments[#segments + 1] = { kind = "literal", value = segment }
    end
  end
  return segments
end

local function handler_shape(handler)
  local kind = type(handler)
  if kind == "string" then return { kind = "zig", symbol = handler } end
  if kind == "function" then return { kind = "inline_lua", value = handler } end
  if kind == "table" and handler.kind == "lua" then return { kind = "lua", module = handler.module } end
  error("unsupported handler shape: " .. kind)
end

function route.declare(method, path, options, handler)
  return {
    method = method,
    raw_path = path,
    path = { segments = parse_path(path) },
    params = options.params or {},
    query = options.query or {},
    memory = options.memory or {},
    handler = handler_shape(handler),
    source = source_info(4),
  }
end

local function parse_size(value, default)
  if value == nil then return default end
  if type(value) == "number" then return value end
  local n, unit = tostring(value):match("^(%d+)%s*([kKmMgG]?[bB]?)$")
  assert(n, "invalid memory size: " .. tostring(value))
  n = tonumber(n)
  unit = unit:lower()
  if unit == "kb" or unit == "k" then return n * 1024 end
  if unit == "mb" or unit == "m" then return n * 1024 * 1024 end
  if unit == "gb" or unit == "g" then return n * 1024 * 1024 * 1024 end
  return n
end

local function segment_params(segments)
  local seen = {}
  for _, segment in ipairs(segments) do
    if segment.kind == "param" then seen[segment.name] = true end
  end
  return seen
end

local function clone_schema(schema)
  local out = {}
  for k, v in pairs(schema or {}) do out[k] = v end
  return out
end

local function sorted_keys(table_value)
  local keys = {}
  for k, _ in pairs(table_value or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function normalize_schema_map(map)
  local out = {}
  for _, name in ipairs(sorted_keys(map)) do
    local item = clone_schema(map[name])
    item.name = name
    if item.kind == "pattern" then
      item.pattern_id = item.id
    elseif type(item.pattern) == "table" and item.pattern.kind == "pattern" then
      item.pattern_id = item.pattern.id
    end
    out[#out + 1] = item
  end
  return out
end

local function symbol_id(symbol)
  return tostring(symbol):match("([%w_]+)$") or tostring(symbol):gsub("%W", "_")
end

local function normalize_handler(handler)
  if handler.kind == "zig" then return { kind = "zig", symbol = symbol_id(handler.symbol), import = handler.symbol } end
  if handler.kind == "lua" then return { kind = "lua", module = handler.module } end
  return { kind = "inline_lua" }
end

function route.normalize_app(app, opts)
  opts = opts or {}
  local mode = opts.mode or "dev"
  local routes = {}
  local patterns = {}
  local pattern_seen = {}
  local seen = {}
  for index, declaration in ipairs(app.routes) do
    local key = declaration.method .. " " .. declaration.raw_path
    assert(not seen[key], "duplicate route: " .. key)
    seen[key] = true

    local path_param_names = segment_params(declaration.path.segments)
    for name, _ in pairs(declaration.params) do
      assert(path_param_names[name], "param declared but not present in path: " .. name)
    end
    for name, _ in pairs(path_param_names) do
      if declaration.params[name] == nil then declaration.params[name] = { type = "string" } end
    end

    local handler = normalize_handler(declaration.handler)
    if mode == "release-static" and handler.kind ~= "zig" then
      error("release-static rejects non-Zig handler at " .. key)
    end

    local normalized = {
      id = handler.kind == "zig" and handler.symbol or ("route_" .. tostring(index)),
      method = declaration.method,
      raw_path = declaration.raw_path,
      path = declaration.path,
      params = normalize_schema_map(declaration.params),
      query = normalize_schema_map(declaration.query),
      handler = handler,
      memory = {
        max_body_bytes = parse_size(declaration.memory.max_body, declaration.method == "POST" and 1024 * 1024 or 0),
        request_arena_bytes = parse_size(declaration.memory.request_arena, 256 * 1024),
      },
      source = declaration.source,
    }
    for _, param in ipairs(normalized.params) do
      local pattern = nil
      if param.kind == "pattern" then pattern = param end
      if type(param.pattern) == "table" and param.pattern.kind == "pattern" then pattern = param.pattern end
      if pattern and not pattern_seen[pattern.id] then
        pattern_seen[pattern.id] = true
        patterns[#patterns + 1] = pattern
      end
    end
    routes[#routes + 1] = normalized
  end
  return {
    format = "meteorite.graph.v0",
    meteorite_version = "0.1.0",
    app = { name = app.name },
    mode = mode,
    routes = routes,
    patterns = patterns,
    middleware = app.middleware,
  }
end

return route
