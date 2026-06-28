local profiles = require("core.profile")

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
      local catch_all = false
      local name = segment:sub(2)
      if name:sub(-1) == "*" then
        catch_all = true
        name = name:sub(1, -2)
        assert(segment == path:match("[^/]+$"), "catch-all path param must be the final route segment: " .. path)
      end
      assert(name:match("^[%a_][%w_]*$"), "invalid path param name: " .. name)
      segments[#segments + 1] = { kind = "param", name = name, catch_all = catch_all }
    else
      segments[#segments + 1] = { kind = "literal", value = segment }
    end
  end
  return segments
end

route.parse_path = parse_path

local function handler_shape(handler)
  local kind = type(handler)
  if kind == "string" then return { kind = "zig", symbol = handler } end
  if kind == "function" then return { kind = "inline_lua", value = handler } end
  if kind == "table" and handler.kind == "lua" then return { kind = "lua", module = handler.module, path = handler.path } end
  if kind == "table" and handler.kind == "zig" then return { kind = "zig", symbol = handler.symbol } end
  if kind == "table" and handler.kind == "zig_file" then return { kind = "zig_file", path = handler.path, decl = handler.decl or "handle" } end
  if kind == "table" and handler.kind == "file" then return handler end
  if kind == "table" and handler.kind == "dir" then return handler end
  error("unsupported handler shape: " .. kind)
end

local function root_scope()
  return { id = "root", parent = "", path_prefix = "", chain = {}, plugins = {}, context = {} }
end

function route.declare(method, path, options, handler)
  local memory = options.memory or {}
  if options.body and options.body.max ~= nil and memory.max_body == nil then
    memory.max_body = options.body.max
  end
  return {
    method = method,
    raw_path = path,
    path = { segments = parse_path(path) },
    params = options.params or {},
    query = options.query or {},
    memory = memory,
    capabilities = options.capabilities or {},
    scope = options.scope or root_scope(),
    handler = handler_shape(handler),
    source = source_info(4),
  }
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

local function path_symbol_id(path)
  local value = tostring(path):gsub("%.zig$", "")
  value = value:gsub("[/\\]+", "_"):gsub("%W", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  if value == "" then value = "zig_file" end
  return value
end

local function normalize_handler(handler)
  if handler.kind == "zig" then return { kind = "zig", symbol = symbol_id(handler.symbol), import = handler.symbol } end
  if handler.kind == "zig_file" then return { kind = "zig_file", symbol = path_symbol_id(handler.path), path = handler.path, decl = handler.decl or "handle" } end
  if handler.kind == "lua" then return { kind = "lua", module = handler.module, path = handler.path } end
  if handler.kind == "file" then return handler end
  if handler.kind == "dir" then return handler end
  return { kind = "inline_lua", value = handler.value }
end

local function static_lua_error(key, declaration)
  error(table.concat({
    "static build cannot include inline Lua handler",
    "",
    "route:",
    "  " .. key,
    "",
    "declared at:",
    "  " .. tostring(declaration.source.file) .. ":" .. tostring(declaration.source.line or 0) .. ":" .. tostring(declaration.source.column or 1),
    "",
    "hint:",
    "  build hybrid:",
    "    moon build --mode hybrid",
    "",
    "  or move this route to a Zig handler:",
    "    app:get(\"/\", \"handlers.index\")",
  }, "\n"))
end

local function suggest_validator(source)
  if type(source) ~= "string" then return nil end
  local lowered = source:lower()
  if lowered:find("@[a-z0-9%%-]+%.", 1) or lowered:find("[a-z0-9%%.!#%%&'*/=?^_`{|}~-]+@", 1) then
    return "email"
  end
  if source:find("^[a-f0-9]{", 1, true) then
    return "hex"
  end
  if source:find("^[0-9a-f]{8}%-[0-9a-f]{4}%-[0-9a-f]{4}%-[0-9a-f]{4}%-[0-9a-f]{12}$", 1) then
    return "uuid"
  end
  return nil
end

local function format_bytes(bytes)
  if bytes >= 1024 * 1024 and bytes % (1024 * 1024) == 0 then return tostring(bytes / (1024 * 1024)) .. "mb" end
  if bytes >= 1024 and bytes % 1024 == 0 then return tostring(bytes / 1024) .. "kb" end
  return tostring(bytes) .. "b"
end

local function validate_pattern_budget(patterns_list, memory)
  if #patterns_list > memory.max_patterns then
    error("pattern count exceeded profile budget: " .. tostring(#patterns_list) .. " > " .. tostring(memory.max_patterns))
  end
  local total_dfa_bytes = 0
  for _, pattern in ipairs(patterns_list) do
    local report = pattern.report or {}
    local dfa_states = report.dfa_states or 0
    local estimated_bytes = report.estimated_bytes or 0
    local source = pattern.source
    local suggested = suggest_validator(source)

    if dfa_states > memory.max_dfa_states_per_pattern then
      local lines = {
        "pattern exceeded DFA state budget",
        "",
        "pattern: " .. tostring(pattern.id or pattern.pattern_id or "<anonymous>"),
        "max_dfa_states: " .. tostring(memory.max_dfa_states_per_pattern),
        "generated_states: " .. tostring(dfa_states),
        "",
        "hint:",
        "  increase profile.static.max_dfa_states_per_pattern in the app profile,",
        "  or pass a larger max_dfa_states to m.pattern(...).",
      }
      if suggested then
        table.insert(lines, "")
        table.insert(lines, "This pattern looks like an " .. suggested .. " validator. Consider using:")
        table.insert(lines, "    " .. (suggested == "hex" and "m.hex({ len = 32 })" or suggested == "uuid" and "m.uuid()" or "m." .. suggested .. "()"))
      end
      error(table.concat(lines, "\n"))
    end
    if estimated_bytes > memory.max_dfa_bytes_per_pattern then
      local lines = {
        "pattern exceeded DFA byte budget",
        "",
        "pattern: " .. tostring(pattern.id or pattern.pattern_id or "<anonymous>"),
        "max_dfa_bytes: " .. tostring(format_bytes(memory.max_dfa_bytes_per_pattern)),
        "estimated_size: " .. tostring(format_bytes(estimated_bytes)),
        "",
        "hint:",
        "  increase profile.static.max_dfa_bytes_per_pattern in the app profile,",
        "  or pass a larger max_dfa_bytes to m.pattern(...).",
      }
      if suggested then
        table.insert(lines, "")
        table.insert(lines, "This pattern looks like an " .. suggested .. " validator. Consider using:")
        table.insert(lines, "    " .. (suggested == "hex" and "m.hex({ len = 32 })" or suggested == "uuid" and "m.uuid()" or "m." .. suggested .. "()"))
      end
      error(table.concat(lines, "\n"))
    end
    total_dfa_bytes = total_dfa_bytes + estimated_bytes
  end
  if total_dfa_bytes > memory.max_dfa_bytes_total then
    error(table.concat({
      "pattern exceeded total DFA byte budget",
      "",
      "max_dfa_bytes_total: " .. tostring(format_bytes(memory.max_dfa_bytes_total)),
      "estimated_size: " .. tostring(format_bytes(total_dfa_bytes)),
      "",
      "hint:",
      "  increase profile.static.max_dfa_bytes_total",
      "  remove unused patterns",
    }, "\n"))
  end
end

function route.normalize_app(app, opts)
  opts = opts or {}
  local mode = opts.mode or "dev"
  local resolved_profile = profiles.resolve(app.profile or (app.options and app.options.profile))
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
    if mode == "release-static" and handler.kind ~= "zig" and handler.kind ~= "zig_file" and handler.kind ~= "file" and handler.kind ~= "dir" then
      static_lua_error(key, declaration)
    end

    if handler.kind == "dir" then
      local found = false
      for _, segment in ipairs(declaration.path.segments) do
        if segment.kind == "param" and segment.name == handler.param and segment.catch_all then found = true end
      end
      assert(found, table.concat({
        "m.dir route requires a catch-all path param",
        "",
        "Route:",
        "  " .. declaration.raw_path,
        "",
        "Expected:",
        "  /.../:" .. tostring(handler.param) .. "*",
        "",
        "Handler:",
        "  m.dir(" .. tostring(handler.root) .. ", { param = \"" .. tostring(handler.param) .. "\" })",
      }, "\n"))
    end

    local memory = profiles.route_memory(resolved_profile, declaration.method, declaration.memory)
    local normalized = {
      id = (handler.kind == "zig" or handler.kind == "zig_file") and handler.symbol or ("route_" .. tostring(index)),
      method = declaration.method,
      raw_path = declaration.raw_path,
      path = declaration.path,
      params = normalize_schema_map(declaration.params),
      query = normalize_schema_map(declaration.query),
      handler = handler,
      runtime = {
        requires_lua = handler.kind == "inline_lua" or handler.kind == "lua",
        requires_http = false,
        requires_auth = false,
        requires_zig_capability = false,
        execution_class = (handler.kind == "inline_lua" or handler.kind == "lua") and "lua" or "default",
      },
      execution = {
        class = (handler.kind == "inline_lua" or handler.kind == "lua") and "lua" or "default",
        may_block = false,
        requires_lua = handler.kind == "inline_lua" or handler.kind == "lua",
        requires_worker_pool = false,
      },
      capabilities = declaration.capabilities,
      scope = declaration.scope or root_scope(),
      memory = memory,
      source = declaration.source,
      source_form = declaration.source_form or "legacy_signature",
      _migration_hint = (declaration.source_form == nil or declaration.source_form == "legacy_signature") and {
        "legacy route signature detected",
        "",
        "current:",
        "  app:" .. string.lower(declaration.method) .. "(\"" .. declaration.raw_path .. "\", handler)",
        "",
        "canonical:",
        "  app:" .. string.lower(declaration.method) .. "({",
        "    route = \"" .. declaration.raw_path .. "\",",
        "    handler = handler,",
        "  })",
      } or nil,
      pipeline = declaration.pipeline,
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
  local budget_memory = profiles.route_memory(resolved_profile, "GET", {})
  validate_pattern_budget(patterns, budget_memory)
  local listen = {
    host = (app.options and app.options.host) or "127.0.0.1",
    port = (app.options and app.options.port) or 8080,
  }
  local plugins = {}
  local plugin_seen = {}
  for _, route in ipairs(routes) do
    for _, plugin in ipairs(route.scope.plugins or {}) do
      if type(plugin) == "table" and plugin.__meteorite_plugin and not plugin_seen[plugin] then
        plugin_seen[plugin] = true
        plugins[#plugins + 1] = { id = plugin.id, kind = plugin.kind, options = plugin.options, execute = plugin.execute, source = plugin.source }
      end
    end
  end
  table.sort(plugins, function(a, b) return a.id < b.id end)
  return {
    format = "meteorite.graph.v0",
    meteorite_version = "0.1.0",
    app = { name = app.name },
    profile = resolved_profile,
    mode = mode,
    listen = listen,
    routes = routes,
    patterns = patterns,
    plugins = plugins,
    capabilities = app.capabilities or {},
    middleware = app.middleware,
  }
end

return route
