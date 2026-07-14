--- Route declaration and graph normalization.
--- Parses route paths, normalizes handlers, and builds the application graph.
---
--- @class RouteModule
--- @field parse_path fun(path: string): table[]  Parse a route path into segments
--- @field declare fun(method: string, path: string, options: table, handler: any): table  Declare a route
--- @field normalize_app fun(app: table, opts: table): table  Normalize app into graph

---@type RouteModule
local profiles = require("core.profile")

local route = {}

local function source_info(level)
  local info = debug.getinfo(level or 3, "Sl") or {}
  local file = info.short_src or info.source or "?"
  if file:sub(1, 1) == "@" then file = file:sub(2) end
  return { file = file, line = info.currentline or 0, column = 1 }
end

--- Parse a route path into segments.
---@param path string  Route path (e.g. "/users/:id")
---@return table[]  Array of segments (literal or param)
local function parse_path(path)
  assert(type(path) == "string" and path ~= "", "route path must be a non-empty string")
  assert(path:sub(1, 1) == "/", "route path must start with /")
  if path == "/" then return {} end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    assert(segment ~= "", "empty route segment in " .. path)
    if segment == "*" then
      assert(segment == path:match("[^/]+$"), "wildcard * must be the final route segment: " .. path)
      segments[#segments + 1] = { kind = "wildcard" }
    elseif segment:sub(1, 1) == ":" then
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

--- Declare a route.
---@param method string  HTTP method
---@param path string  Route path pattern
---@param options table  Route options (params, query, body, memory, capabilities)
---@param handler any  Handler (string, function, or table)
---@return table  Route declaration
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
    headers = options.headers or {},
    cookies = options.cookies or {},
    json_body = options.json or options.json_body or (options.body and options.body.json) or {},
    form_body = options.form or options.form_body or (options.body and options.body.form) or {},
    responses = options.responses or {},
    description = options.description or nil,
    summary = options.summary or nil,
    tags = options.tags or nil,
    operation_id = options.operationId or options.operation_id or nil,
    memory = memory,
    capabilities = options.capabilities or {},
    message = options.message,
    message_source = options.message_source,
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

--- Check if a route path contains a wildcard segment.
local function has_wildcard(segments)
  for _, segment in ipairs(segments or {}) do
    if segment.kind == "wildcard" then return true end
  end
  return false
end

route.has_wildcard = has_wildcard

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

local function normalize_validation_contract(declaration)
  return {
    headers = normalize_schema_map(declaration.headers),
    cookies = normalize_schema_map(declaration.cookies),
    json_body = normalize_schema_map(declaration.json_body),
    form_body = normalize_schema_map(declaration.form_body),
  }
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

local function message_symbol_id(name)
  local value = tostring(name or "message"):gsub("%W", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  if value == "" then value = "message" end
  return "message_" .. value
end

local method_message_suffix = {
  GET = "get",
  POST = "create",
  PUT = "put",
  PATCH = "patch",
  DELETE = "delete",
}

local function normalize_message_name(value)
  assert(type(value) == "string" and value ~= "", "message name must be a non-empty string")
  local normalized = value:gsub("^/+", ""):gsub("/+$", ""):gsub("/", ".")
  for segment in normalized:gmatch("[^%.]+") do
    assert(segment:match("^[%a_][%w_]*$"), "invalid message name: " .. value .. " (expected dot-separated identifiers such as users.get)")
  end
  assert(not normalized:match("%.%.") and normalized:sub(1, 1) ~= "." and normalized:sub(-1) ~= ".", "invalid message name: " .. value .. " (expected dot-separated identifiers such as users.get)")
  return normalized
end

local function inferred_message_segment(value)
  local segment = tostring(value or ""):lower():gsub("%W+", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  if segment == "" then return nil end
  if not segment:match("^[%a_]") then segment = "_" .. segment end
  return segment
end

local function infer_message_name(method, raw_path, segments)
  local literals = {}
  for _, segment in ipairs(segments or {}) do
    if segment.kind == "literal" then
      local value = inferred_message_segment(segment.value)
      if value then literals[#literals + 1] = value end
    end
  end
  local base = #literals > 0 and table.concat(literals, ".") or inferred_message_segment(raw_path:gsub("^/+", ""):gsub("/.*$", ""))
  if not base or base == "" then base = "root" end
  local suffix = method_message_suffix[method] or tostring(method):lower()
  return normalize_message_name(base .. "." .. suffix)
end

local function message_param_names(segments)
  local out = {}
  for _, segment in ipairs(segments or {}) do
    if segment.kind == "param" then out[#out + 1] = segment.name end
  end
  return out
end

local function normalize_message_projection(declaration)
  local explicit = declaration.message
  local name
  local pattern
  local source = declaration.message_source or "inferred"
  if type(explicit) == "string" then
    name = normalize_message_name(explicit)
    pattern = name
    source = declaration.message_source or "explicit"
  elseif type(explicit) == "table" then
    name = normalize_message_name(explicit.name or explicit[1] or explicit.pattern)
    pattern = explicit.pattern and normalize_message_name(explicit.pattern) or name
    source = declaration.message_source or "explicit"
  else
    name = infer_message_name(declaration.method, declaration.raw_path, declaration.path.segments)
    pattern = name
  end
  return {
    name = name,
    pattern = pattern,
    params = declaration.message_source == "message" and sorted_keys(declaration.params) or message_param_names(declaration.path.segments),
    source = source,
    slash_alias = name:gsub("%.", "/"),
  }
end

local function normalize_handler(handler)
  if handler.kind == "zig" then return { kind = "zig", symbol = symbol_id(handler.symbol), import = handler.symbol } end
  if handler.kind == "zig_file" then return { kind = "zig_file", symbol = path_symbol_id(handler.path), path = handler.path, decl = handler.decl or "handle" } end
  if handler.kind == "lua" then return { kind = "lua", module = handler.module, path = handler.path } end
  if handler.kind == "file" then return handler end
  if handler.kind == "dir" then return handler end
  return { kind = "inline_lua", value = handler.value }
end

local function static_lua_error(key, declaration, route_id, handler)
  local handler_kind = handler and handler.kind or "inline_lua"
  error(table.concat({
    "static build cannot include " .. (handler_kind == "lua" and "Lua handler" or "inline Lua handler"),
    "",
    "mode:",
    "  release-static",
    "",
    "route id:",
    "  " .. tostring(route_id),
    "",
    "route:",
    "  " .. key,
    "",
    "declared at:",
    "  " .. tostring(declaration.source.file) .. ":" .. tostring(declaration.source.line or 0) .. ":" .. tostring(declaration.source.column or 1),
    "",
    "remediation:",
    "  build hybrid when this route must execute Lua at request time:",
    "    meteorite build --mode hybrid",
    "",
    "  or replace this route with a static-safe Zig/file handler before release-static:",
    "    app:get(\"" .. tostring(declaration.raw_path or "/") .. "\", \"handlers." .. tostring(route_id):gsub("^route_", "route_") .. "\")",
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

local function list_touches(entries, needles)
  for _, entry in ipairs(entries or {}) do
    if type(entry) == "string" then
      for _, needle in ipairs(needles) do
        if entry == needle or entry:find(needle .. ".", 1, true) == 1 then return entry end
      end
    end
  end
  return nil
end

local function validate_backend_resource_contracts(nodes, backend)
  if backend ~= "ipc_unixsocket" and backend ~= "unix_socket" then return end
  local http_only = {
    "request.headers",
    "response.headers",
    "response.cookies",
    "response.redirects",
    "response.static",
    "response.etag",
  }
  for _, route_node in ipairs(nodes or {}) do
    for _, stage in ipairs(route_node.pipeline or {}) do
      local resource = list_touches(stage.reads, http_only) or list_touches(stage.writes, http_only)
      if resource then
        error(table.concat({
          "backend-incompatible pipeline resource",
          "",
          "backend: " .. tostring(backend),
          "route: " .. tostring(route_node.method) .. " " .. tostring(route_node.raw_path),
          "stage: " .. tostring(stage.id or stage.kind or "stage"),
          "resource: " .. tostring(resource),
          "",
          "hint: native IPC stages should use request.message, request.metadata, response.result, or response.metadata; keep HTTP-only helpers behind an HTTP backend.",
        }, "\n"), 0)
      end
    end
  end
end

--- Normalize an app's routes into a graph.
---@param app table  Meteorite app
---@param opts table  Options (mode, etc.)
---@return table  Normalized graph
function route.normalize_app(app, opts)
  opts = opts or {}
  local mode = opts.mode or "dev"
  local backend = opts.backend or _G.METEORITE_BACKEND or "fast_http"
  local resolved_profile = profiles.resolve(app.profile or (app.options and app.options.profile))
  local routes = {}
  local messages = {}
  local nodes = {}
  local patterns = {}
  local pattern_seen = {}
  local seen = {}
  local seen_messages = {}
  for index, declaration in ipairs(app.routes) do
    local key = declaration.method .. " " .. declaration.raw_path
    assert(not seen[key], "duplicate route: " .. key)
    seen[key] = true
    local message = normalize_message_projection(declaration)
    local message_domain = message.source == "message" and "message" or "route"
    local message_key = message_domain .. ":" .. message.name
    assert(not seen_messages[message_key], table.concat({
      "duplicate native message: " .. message.name,
      "",
      "first route:",
      "  " .. tostring(seen_messages[message_key] or "<unknown>"),
      "duplicate route:",
      "  " .. key,
      "",
      "hint: set an explicit unique message name in this graph domain",
    }, "\n"))
    seen_messages[message_key] = key

    local path_param_names = segment_params(declaration.path.segments)
    if declaration.message_source ~= "message" then
      for name, _ in pairs(declaration.params) do
        assert(path_param_names[name], "param declared but not present in path: " .. name)
      end
      for name, _ in pairs(path_param_names) do
        if declaration.params[name] == nil then declaration.params[name] = { type = "string" } end
      end
    end

    local handler = normalize_handler(declaration.handler)
    if mode == "release-static" and handler.kind ~= "zig" and handler.kind ~= "zig_file" and handler.kind ~= "file" and handler.kind ~= "dir" then
      static_lua_error(key, declaration, "route_" .. tostring(index), handler)
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
    local is_message = message.source == "message"
    local normalized = {
      id = is_message and message_symbol_id(message.name) or ((handler.kind == "zig" or handler.kind == "zig_file") and handler.symbol or ("route_" .. tostring(index))),
      method = declaration.method,
      raw_path = declaration.raw_path,
      canonical_id = (message.source == "message" and "message." or "route.") .. message.name,
      http = {
        method = declaration.method,
        path = declaration.raw_path,
      },
      message = message,
      path = declaration.path,
      params = normalize_schema_map(declaration.params),
      query = normalize_schema_map(declaration.query),
      validation = normalize_validation_contract(declaration),
      responses = declaration.responses or {},
      description = declaration.description,
      summary = declaration.summary,
      tags = declaration.tags,
      operation_id = declaration.operation_id,
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
      policy = declaration.policy,
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
    nodes[#nodes + 1] = normalized
    if is_message then messages[#messages + 1] = normalized else routes[#routes + 1] = normalized end
  end
  local budget_memory = profiles.route_memory(resolved_profile, "GET", {})
  validate_pattern_budget(patterns, budget_memory)
  local listen = {
    host = (app.options and app.options.host) or "127.0.0.1",
    port = (app.options and app.options.port) or 8080,
  }
  local trailing_slash = (app.options and app.options.trailing_slash) or "default"
  local plugins = {}
  local plugin_seen = {}
  for _, route in ipairs(nodes) do
    for _, plugin in ipairs(route.scope.plugins or {}) do
      if type(plugin) == "table" and plugin.__meteorite_plugin and not plugin_seen[plugin] then
        plugin_seen[plugin] = true
        plugins[#plugins + 1] = { id = plugin.id, kind = plugin.kind, options = plugin.options, execute = plugin.execute, source = plugin.source }
      end
    end
  end
  table.sort(plugins, function(a, b) return a.id < b.id end)

  -- Run graph plugins (new contract system)
  local graph_plugins = app.graph_plugins or {}
  if #graph_plugins > 0 then
    local plugin_contract = require("core.plugin_contract")
    local hooks_mod = require("core.hooks")

    -- Build the graph object that plugins will mutate
    local plugin_graph = {
      routes = routes,
      messages = messages,
      patterns = patterns,
      plugins = plugins,
      hooks = {},
      capabilities = app.capabilities or {},
    }

    -- Run plugin passes (validate -> transform -> codegen -> profile)
    local plugin_result = plugin_contract.run_passes(plugin_graph, graph_plugins)

    -- Validate hooks
    local hook_errors = hooks_mod.validate_graph(plugin_graph)
    for _, err in ipairs(hook_errors) do
      error("hook validation error: " .. err)
    end

    -- Store plugin results on the graph
    plugin_graph.plugin_diagnostics = plugin_result.diagnostics
    plugin_graph.plugin_codegen_units = plugin_result.codegen_units
    plugin_graph.plugin_profile_counters = plugin_result.profile_counters
  end

  validate_backend_resource_contracts(nodes, backend)

  -- Detect undocumented routes (no summary/description and no response schemas)
  local undocumented = {}
  for _, route in ipairs(nodes) do
    local hasResponses = false
    for status, _ in pairs(route.responses or {}) do hasResponses = true; break end
    if not route.summary and not route.description and not hasResponses then
      undocumented[#undocumented + 1] = {
        method = route.method,
        path = route.raw_path,
        id = route.id,
        source = route.source,
      }
    end
  end
  if #undocumented > 0 and (mode == "release-static" or mode == "release-hybrid") then
    local lines = { "undocumented routes detected in release build", "" }
    for _, r in ipairs(undocumented) do
      lines[#lines + 1] = "  " .. r.method .. " " .. r.path
      lines[#lines + 1] = "    at " .. tostring(r.source.file) .. ":" .. tostring(r.source.line or 0)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "hint: add summary, description, or responses to each route for release documentation"
    local example_path = undocumented[1] and undocumented[1].path or "/example"
    lines[#lines + 1] = '  app:get("' .. example_path .. '", {'
    lines[#lines + 1] = '    summary = "Route summary",'
    lines[#lines + 1] = '    responses = { [200] = { description = "OK" } },'
    lines[#lines + 1] = '  }, handler)'
    local diagnostic = table.concat(lines, "\n")
    local strictDocs = opts.strict_docs == true or _G.METEORITE_STRICT_DOCS == true or os.getenv("METEORITE_STRICT_DOCS") == "1"
    if strictDocs then error(diagnostic, 0) end
    io.stderr:write(diagnostic .. "\n")
  end

  return {
    format = "meteorite.graph.v0",
    meteorite_version = "0.1.0",
    app = { name = app.name },
    profile = resolved_profile,
    mode = mode,
    listen = listen,
    trailing_slash = trailing_slash,
    routes = routes,
    messages = messages,
    nodes = nodes,
    patterns = patterns,
    plugins = plugins,
    capabilities = app.capabilities or {},
    middleware = app.middleware,
    undocumented_routes = undocumented,
  }
end

return route
