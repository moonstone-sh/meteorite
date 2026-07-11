--- Build report, memory report, and LuaLS aids generation.
--- Extracted from emitter.lua.

local helpers = require("codegen.helpers")
local zon = require("codegen.zon")
local fs = require("utils.fs")

local report = {}

local function json_schema_for(item)
  local kind = item.type or item.kind or "string"
  local out = { type = "string" }
  if kind == "u64" or kind == "i32" then
    out.type = "integer"
    if kind == "u64" then out.minimum = 0 end
  elseif kind == "bool" then
    out.type = "boolean"
  elseif kind == "uuid" then
    out.format = "uuid"
  elseif kind == "email" then
    out.format = "email"
  elseif kind == "hex" then
    out.pattern = "^[0-9A-Fa-f]+$"
  elseif kind == "slug" then
    out.pattern = "^[A-Za-z0-9_-]+$"
  elseif kind == "token" then
    out.pattern = "^[A-Za-z0-9._~-]+$"
  elseif kind == "pattern" then
    out["x-meteorite-pattern-id"] = item.pattern_id or item.id
  end
  if item.max_len then out.maxLength = item.max_len end
  if item.exact_len then
    out.minLength = item.exact_len
    out.maxLength = item.exact_len
  end
  if item.min then out.minimum = item.min end
  if item.max then out.maximum = item.max end
  return out
end

local function object_schema(items)
  local properties = {}
  local required = {}
  for _, item in ipairs(items or {}) do
    properties[item.name] = json_schema_for(item)
    if item.optional ~= true then required[#required + 1] = item.name end
  end
  table.sort(required)
  local out = { type = "object", properties = properties, additionalProperties = false }
  if #required > 0 then out.required = required end
  return out
end

local function response_schemas(responses)
  local out = {}
  for status, spec in pairs(responses or {}) do
    local key = tostring(status)
    if type(spec) == "table" then
      if spec.schema then out[key] = spec.schema
      elseif spec.json then out[key] = object_schema(spec.json)
      elseif spec.body then out[key] = object_schema(spec.body)
      else out[key] = spec end
    end
  end
  return out
end

local function response_count(responses)
  local count = 0
  for _, _ in pairs(responses or {}) do count = count + 1 end
  return count
end

local function has_fields(schema)
  local props = schema and schema.properties or {}
  for _, _ in pairs(props) do return true end
  return false
end

local function path_template(raw_path)
  return tostring(raw_path or ""):gsub(":([%a_][%w_]*)%*", "{%1}"):gsub(":([%a_][%w_]*)", "{%1}")
end

local function parameter_list(location, items)
  local parameters = {}
  for _, item in ipairs(items or {}) do
    parameters[#parameters + 1] = {
      name = item.name,
      in_ = location,
      required = location == "path" or item.optional ~= true,
      schema = json_schema_for(item),
    }
  end
  return parameters
end

local function append_all(target, source)
  for _, item in ipairs(source or {}) do target[#target + 1] = item end
end

local function security_schemes(route)
  local schemes = {}
  local validation = route.validation or {}
  for _, item in ipairs(validation.headers or {}) do
    local name = tostring(item.name or "")
    local lowered = name:lower()
    if lowered == "authorization" then schemes[#schemes + 1] = "authorization-header"
    elseif lowered:find("token", 1, true) or lowered:find("api%-key") then schemes[#schemes + 1] = name end
  end
  for _, item in ipairs(validation.cookies or {}) do schemes[#schemes + 1] = "cookie:" .. tostring(item.name) end
  if route.runtime and route.runtime.requires_auth then schemes[#schemes + 1] = "meteorite-auth-capability" end
  table.sort(schemes)
  return schemes
end

function report.schema_to_zon(item)
  if item.kind == "pattern" then
    return { name = item.name, kind = "pattern", pattern_id = item.pattern_id or item.id }
  end
  local out = { name = item.name, type = { __meteorite_enum = true, value = item.type or "string" } }
  if item.max_len then out.max_len = item.max_len end
  if item.exact_len then out.exact_len = item.exact_len end
  if item.optional then out.optional = true end
  if item.decode then out.decode = true end
  if item.pattern_id then out.pattern_id = item.pattern_id end
  return out
end

function report.schema_ir(graph)
  local routes = {}
  local messages = {}
  for _, route in ipairs(graph.routes or {}) do
    local validation = route.validation or {}
    routes[#routes + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      http = route.http,
      message = route.message,
      method = helpers.method_enum(route.method),
      path = route.raw_path,
      params = object_schema(route.params),
      query = object_schema(route.query),
      headers = object_schema(validation.headers),
      cookies = object_schema(validation.cookies),
      json_body = object_schema(validation.json_body),
      form_body = object_schema(validation.form_body),
      responses = response_schemas(route.responses),
    }
  end
  for _, route in ipairs(graph.messages or {}) do
    local validation = route.validation or {}
    messages[#messages + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      message = route.message,
      metadata = object_schema(route.params),
      json_body = object_schema(validation.json_body),
      form_body = object_schema(validation.form_body),
      responses = response_schemas(route.responses),
    }
  end
  return {
    format = "meteorite.schema-ir.v0",
    routes = routes,
    messages = messages,
  }
end

function report.openapi_plan(graph)
  local routes = {}
  local messages = {}
  for _, route in ipairs(graph.routes or {}) do
    local validation = route.validation or {}
    local json_body = object_schema(validation.json_body)
    local form_body = object_schema(validation.form_body)
    local request_body = {}
    if has_fields(json_body) then request_body["application/json"] = json_body end
    if has_fields(form_body) then request_body["application/x-www-form-urlencoded"] = form_body end
    local parameters = {}
    append_all(parameters, parameter_list("path", route.params))
    append_all(parameters, parameter_list("query", route.query))
    append_all(parameters, parameter_list("header", validation.headers))
    append_all(parameters, parameter_list("cookie", validation.cookies))
    routes[#routes + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      http = route.http,
      message = route.message,
      method = helpers.method_enum(route.method),
      path = route.raw_path,
      template = path_template(route.raw_path),
      operationId = route.id,
      parameters = parameters,
      requestBody = request_body,
      responses = response_count(route.responses) > 0 and response_schemas(route.responses) or {
        default = {
          description = "Meteorite route response schema not declared",
          missing_schema = true,
        },
      },
      security = security_schemes(route),
    }
  end
  for _, route in ipairs(graph.messages or {}) do
    local validation = route.validation or {}
    messages[#messages + 1] = {
      id = route.id,
      canonical_id = route.canonical_id,
      message = route.message,
      metadata = object_schema(route.params),
      json_body = object_schema(validation.json_body),
      form_body = object_schema(validation.form_body),
      responses = response_count(route.responses) > 0 and response_schemas(route.responses) or {
        default = { description = "Meteorite message response schema not declared", missing_schema = true },
      },
    }
  end
  return {
    format = "meteorite.openapi-plan.v0",
    openapi = "3.1.0",
    routes = routes,
    messages = messages,
  }
end

function report.route_to_zon(route)
  local segments = {}
  for _, segment in ipairs(route.path.segments) do
    if segment.kind == "literal" then
      segments[#segments + 1] = { literal = segment.value }
    else
      local param_schema = { name = segment.name, type = "string" }
      for _, item in ipairs(route.params) do if item.name == segment.name then param_schema = item end end
      local entry = { param = report.schema_to_zon(param_schema) }
      if segment.catch_all then entry.catch_all = true end
      segments[#segments + 1] = entry
    end
  end
  local query = {}
  for _, item in ipairs(route.query) do query[#query + 1] = report.schema_to_zon(item) end
  local validation = { headers = {}, cookies = {}, json_body = {}, form_body = {} }
  for domain, items in pairs(route.validation or {}) do
    validation[domain] = {}
    for _, item in ipairs(items) do validation[domain][#validation[domain] + 1] = report.schema_to_zon(item) end
  end
  local handler
  if route.handler.kind == "zig" then handler = { zig_symbol = { id = route.handler.symbol, symbol = route.handler.import or route.handler.symbol } }
  elseif route.handler.kind == "zig_file" then handler = { zig_file = { id = route.handler.symbol, path = route.handler.path, decl = route.handler.decl or "handle" } }
  elseif route.handler.kind == "lua" then handler = { lua_file = { id = route.id, path = route.handler.path or route.handler.module } }
  elseif route.handler.kind == "file" then handler = { file = { artifact_path = route.handler.artifact_path, content_type = route.handler.content_type, content_length = route.handler.content_length, etag = route.handler.etag, cache_control = route.handler.cache_control, only_accept = route.handler.only_accept } }
  elseif route.handler.kind == "dir" then handler = { dir = { param = route.handler.param, cache_control = route.handler.cache_control, immutable = route.handler.immutable, manifest = route.handler.manifest or {} } }
  else handler = { inline_lua = route.handler.lifted or { id = route.id } } end
  local capabilities = {}
  for _, ref in ipairs(route.capabilities or {}) do capabilities[#capabilities + 1] = { [ref.kind] = ref.name } end
  local runtime = {
    requires_lua = route.runtime.requires_lua,
    requires_http = route.runtime.requires_http,
    requires_auth = route.runtime.requires_auth,
    requires_zig_capability = route.runtime.requires_zig_capability,
    execution_class = { __meteorite_enum = true, value = route.runtime.execution_class },
  }
  local execution = {
    class = { __meteorite_enum = true, value = route.execution.class },
    may_block = route.execution.may_block,
    requires_lua = route.execution.requires_lua,
    requires_worker_pool = route.execution.requires_worker_pool,
  }
  return {
    id = route.id,
    canonical_id = route.canonical_id,
    http = route.http,
    message = route.message,
    method = helpers.method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    query = query,
    validation = validation,
    responses = response_schemas(route.responses),
    handler = handler,
    runtime = runtime,
    execution = execution,
    memory = route.memory,
    capabilities = capabilities,
    scope = helpers.normalized_scope(route.scope),
    source = route.source,
  }
end

function report.capability_names(capabilities, kind)
  local out = {}
  for name, _ in pairs((capabilities or {})[kind] or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function report.format_bytes(bytes)
  bytes = tonumber(bytes or 0) or 0
  if bytes >= 1024 * 1024 and bytes % (1024 * 1024) == 0 then return tostring(bytes / (1024 * 1024)) .. "mb" end
  if bytes >= 1024 and bytes % 1024 == 0 then return tostring(bytes / 1024) .. "kb" end
  return tostring(bytes) .. "b"
end

function report.memory_report(graph, routes_text)
  local peak_route = nil
  local peak_bytes = 0
  local max_uri_bytes, max_path_bytes, max_query_bytes = 0, 0, 0
  local max_query_pairs, max_path_segments = 0, 0
  for _, route in ipairs(graph.nodes or graph.routes or {}) do
    local memory = route.memory or {}
    if (memory.estimated_peak_bytes or 0) > peak_bytes then
      peak_route = route
      peak_bytes = memory.estimated_peak_bytes or 0
    end
    if (memory.max_uri_bytes or 0) > max_uri_bytes then max_uri_bytes = memory.max_uri_bytes or 0 end
    if (memory.max_path_bytes or 0) > max_path_bytes then max_path_bytes = memory.max_path_bytes or 0 end
    if (memory.max_query_bytes or 0) > max_query_bytes then max_query_bytes = memory.max_query_bytes or 0 end
    if (memory.max_query_pairs or 0) > max_query_pairs then max_query_pairs = memory.max_query_pairs or 0 end
    if (memory.max_path_segments or 0) > max_path_segments then max_path_segments = memory.max_path_segments or 0 end
  end
  local dfa_bytes = 0
  local dfa_states = 0
  for _, pattern in ipairs(graph.patterns or {}) do
    local report = pattern.report or {}
    dfa_bytes = dfa_bytes + (report.estimated_bytes or 0)
    dfa_states = dfa_states + (report.dfa_states or 0)
  end
  local profile = graph.profile or {}
  return {
    profile = profile.name or ((peak_route and peak_route.memory and peak_route.memory.profile_name) or "default"),
    peak_route = peak_route and (peak_route.method .. " " .. peak_route.raw_path) or "none",
    estimated_peak_bytes = peak_bytes,
    max_uri_bytes = max_uri_bytes,
    max_path_bytes = max_path_bytes,
    max_query_bytes = max_query_bytes,
    max_query_pairs = max_query_pairs,
    max_path_segments = max_path_segments,
    dfa_bytes = dfa_bytes,
    dfa_states = dfa_states,
    graph_bytes = #(routes_text or ""),
  }
end

function report.emit_build_report(graph, output, mode, backend)
  backend = backend or "fast_http"
  local inline, zig = 0, 0
  local validation_counts = { params = 0, query = 0, headers = 0, cookies = 0, json_body = 0, form_body = 0 }
  local missing_response_schemas = 0
  for _, route in ipairs(graph.nodes or graph.routes) do
    if route.handler.kind == "inline_lua" then inline = inline + 1 end
    if route.handler.kind == "zig" or route.handler.kind == "zig_file" then zig = zig + 1 end
    validation_counts.params = validation_counts.params + #(route.params or {})
    validation_counts.query = validation_counts.query + #(route.query or {})
    local validation = route.validation or {}
    validation_counts.headers = validation_counts.headers + #(validation.headers or {})
    validation_counts.cookies = validation_counts.cookies + #(validation.cookies or {})
    validation_counts.json_body = validation_counts.json_body + #(validation.json_body or {})
    validation_counts.form_body = validation_counts.form_body + #(validation.form_body or {})
    if response_count(route.responses) == 0 then missing_response_schemas = missing_response_schemas + 1 end
  end
  local memory = graph.memory_report or report.memory_report(graph)
  local lines = {
    "Meteorite build",
    "  mode: " .. (mode == "release-static" and "static" or "hybrid"),
    "  backend: " .. backend,
    "  transport: " .. ((backend == "ipc_unixsocket" or backend == "ipc_unixsocket_http") and "unix" or "tcp"),
    "  protocol: " .. (backend == "ipc_unixsocket" and "meteorite.ipc.v0" or "http/1.1"),
    "  Lua runtime: " .. (mode == "release-static" and "removed" or "included"),
    "  Lua state: single_locked",
    "  workers: auto",
    "  inline Lua handlers: " .. tostring(inline),
    "  Zig handlers: " .. tostring(zig),
    "  HTTP capabilities: " .. (#report.capability_names(graph.capabilities, "http") > 0 and table.concat(report.capability_names(graph.capabilities, "http"), ", ") or "none"),
    "  Auth capabilities: " .. (#report.capability_names(graph.capabilities, "auth") > 0 and table.concat(report.capability_names(graph.capabilities, "auth"), ", ") or "none"),
    "  Zig capabilities: " .. (#report.capability_names(graph.capabilities, "zig") > 0 and table.concat(report.capability_names(graph.capabilities, "zig"), ", ") or "none"),
    "  patterns: " .. tostring(#graph.patterns),
    "  validators: params=" .. tostring(validation_counts.params) .. " query=" .. tostring(validation_counts.query) .. " headers=" .. tostring(validation_counts.headers) .. " cookies=" .. tostring(validation_counts.cookies) .. " json=" .. tostring(validation_counts.json_body) .. " form=" .. tostring(validation_counts.form_body),
    "  response schemas: declared=" .. tostring(#graph.routes - missing_response_schemas) .. " missing=" .. tostring(missing_response_schemas),
    "  memory profile: " .. tostring(memory.profile),
    "  peak route memory: " .. report.format_bytes(memory.estimated_peak_bytes) .. " (" .. tostring(memory.peak_route) .. ")",
    "  max URI: " .. report.format_bytes(memory.max_uri_bytes),
    "  max path: " .. report.format_bytes(memory.max_path_bytes),
    "  max query: " .. report.format_bytes(memory.max_query_bytes) .. " / " .. tostring(memory.max_query_pairs) .. " pairs",
    "  DFA tables: " .. report.format_bytes(memory.dfa_bytes) .. " / " .. tostring(memory.dfa_states) .. " states",
    "  graph data: ~" .. report.format_bytes(memory.graph_bytes),
    "  artifact: dist/server",
    "",
  }
  helpers.write_file(output .. "/build-report.txt", table.concat(lines, "\n"))
end

function report.emit_luals_aids(graph, output)
  local aid_dir = output .. "/../../aids/lua"
  fs.mkdir_p(aid_dir)
  local function lua_string(value)
    return '"' .. tostring(value or ""):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  local function context_class(route)
    return "MeteoriteContext_" .. helpers.zig_ident(route.id)
  end
  local function append_route_overloads(target)
    for _, route in ipairs(graph.routes) do
      local method = tostring(route.method or "get"):lower()
      local path_literal = lua_string(route.raw_path or route.path or "")
      local ctx_name = context_class(route)
      target[#target + 1] = "---@field " .. method .. " fun(self: MeteoriteApp, path: " .. path_literal .. ", handler: fun(c: " .. ctx_name .. "): any): table"
      target[#target + 1] = "---@field " .. method .. " fun(self: MeteoriteApp, path: " .. path_literal .. ", options: MeteoriteRouteOptions, handler: fun(c: " .. ctx_name .. "): any): table"
    end
  end
  local lines = {
    "---@meta",
    "",
    "---@diagnostic disable: missing-return, lowercase-global",
    "",
    "---@class MeteoriteAppOptions",
    "---@field name? string",
    "---@field profile? string|table",
    "",
    "---@class MeteoriteRouteOptions",
    "---@field params? table<string, MeteoriteSchemaValue>",
    "---@field query? table<string, MeteoriteSchemaValue>",
    "---@field headers? table<string, MeteoriteSchemaValue>",
    "---@field cookies? table<string, MeteoriteSchemaValue>",
    "---@field json? table<string, MeteoriteSchemaValue>",
    "---@field json_body? table<string, MeteoriteSchemaValue>",
    "---@field form? table<string, MeteoriteSchemaValue>",
    "---@field form_body? table<string, MeteoriteSchemaValue>",
    "---@field responses? table<string|integer, table>",
    "---@field body? {max?: number|string, [string]: any}",
    "---@field memory? {max_body?: number|string, request_arena?: number|string}",
    "---@field capabilities? table<string, any>",
    "",
    "---@alias MeteoriteHandler string|fun(c: MeteoriteContext): any|{kind: string, module?: string, path?: string, symbol?: string, decl?: string}",
    "",
    "---@class MeteoriteSchemaValue",
    "---@field type string",
    "---@field optional? boolean",
    "---@field max_len? integer",
    "---@field exact_len? integer",
    "---@field pattern? MeteoritePattern",
    "",
    "---@class MeteoritePattern : MeteoriteSchemaValue",
    "---@field id string",
    "---@field kind \"pattern\"",
    "---@field pattern_id string",
    "",
    "---@class MeteoriteApp",
    "---@field name string",
    "---@field routes table",
    "---@field middleware table",
    "---@field capabilities table<string, any>",
    "---@field cache table",
    "---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table",
    "---@field get fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table",
    "---@field post fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table",
    "---@field post fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table",
    "---@field put fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table",
    "---@field put fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table",
    "---@field patch fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table",
    "---@field patch fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table",
    "---@field delete fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table",
    "---@field delete fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table",
    "---@field use fun(self: MeteoriteApp, plugin_or_middleware: table|function, options?: table): MeteoriteApp",
    "---@field capability fun(self: MeteoriteApp, kind: string, spec: table): MeteoriteApp",
  }
  append_route_overloads(lines)
  for _, line in ipairs({
    "",
    "---@class MeteoriteModule",
    "---@field profiles table",
    "---@field app fun(opts?: MeteoriteAppOptions): MeteoriteApp",
    "---@field profile fun(name_or_table?: string|table, opts?: table): table",
    "---@field string fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean, validate?: string|function|table, pattern?: MeteoritePattern}): MeteoriteSchemaValue",
    "---@field slug fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field u64 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field i32 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field uuid fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field hex fun(opts?: {len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field email fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field token fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field bool fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue",
    "---@field pattern fun(name_or_source: string, source_or_opts?: string|table, opts?: table): MeteoritePattern",
    "---@field zig fun(path_or_symbol: string, opts?: {decl?: string}): table",
    "---@field lua fun(module_ref: string): table",
    "---@field file fun(path: string, opts?: table): table",
    "---@field dir fun(root: string, opts?: table): table",
    "---@field site fun(app: MeteoriteApp, opts: table): MeteoriteApp",
    "---@type MeteoriteModule",
    "local meteorite = {}",
    "",
    "---@class MeteoriteContext",
    "---@field params table<string, string|integer|number|boolean>",
    "---@field query table<string, string|integer|number|boolean|nil>",
    "---@field state table<string, any>",
    "local Context = {}",
    "",
    "---@param body string",
    "---@param opts? {headers?: table<string, string>}",
    "function Context:text(body) end",
    "",
    "---@param value table|string|number|boolean",
    "---@param opts? {status?: integer, headers?: table<string, string>}",
    "function Context:json(value, opts) end",
    "",
    "---@param status integer",
    "---@param content_type string",
    "---@param body string",
    "---@param opts? {headers?: table<string, string>}",
    "function Context:bytes(status, content_type, body) end",
    "",
    "---@return string",
    "function Context:body() end",
    "",
    "---@return table|nil value",
    "---@return string|nil err",
    "function Context:json_body() end",
    "",
    "---@return table|nil value",
    "---@return string|nil err",
    "function Context:form_body() end",
    "",
    "---@param opts? {csp?: string, hsts?: boolean|table, frame_options?: string|false, referrer_policy?: string|false, coop?: string|false, permissions_policy?: string, nosniff?: boolean, extra?: table<string, string>}",
    "---@return table<string, string>",
    "function Context:secure_headers(opts) end",
    "",
    "---@param opts? {origin?: string, origins?: string|string[], methods?: string|string[], headers?: string|string[], credentials?: boolean, max_age?: integer, maxAge?: integer, expose_headers?: string|string[], exposeHeaders?: string|string[]}",
    "---@return table<string, string>",
    "function Context:cors_headers(opts) end",
    "",
    "---@param metrics table[]|table<string, number|table>",
    "---@return table<string, string>",
    "function Context:server_timing(metrics) end",
    "",
    "---@param metrics table[]",
    "---@param name string",
    "---@param fn function",
    "---@param opts? {desc?: string, description?: string}",
    "---@return any",
    "function Context:timing_stage(metrics, name, fn, opts) end",
    "",
    "---@param left string",
    "---@param right string",
    "---@return boolean",
    "function Context:constant_time_equal(left, right) end",
    "",
    "---@return string|nil username",
    "---@return string|nil password",
    "function Context:basic_auth() end",
    "",
    "---@return string|nil",
    "function Context:bearer_token() end",
    "",
    "---@param name string",
    "---@return string|nil",
    "function Context:safe_header(name) end",
    "",
    "---@param names string[]",
    "---@return table<string, string>",
    "function Context:safe_headers(names) end",
    "",
    "---@param level string|table",
    "---@param message? string|table",
    "---@param fields? table",
    "---@param opts? {format?: 'json'|'plain'}",
    "---@return table",
    "function Context:log(level, message, fields, opts) end",
    "",
    "---@param name string",
    "---@return string|nil",
    "function Context:header(name) end",
    "",
    "---@param name string",
    "---@return string|nil",
    "function Context:query(name) end",
    "",
    "---@param name string",
    "---@return string[]|nil",
    "function Context:query_all(name) end",
    "",
    "---@param name string",
    "---@return string|integer|nil",
    "function Context:param(name) end",
    "",
    "---@return string",
    "function Context:request_id() end",
    "",
    "---@param name string",
    "---@return string|nil",
    "function Context:cookie(name) end",
    "",
    "---@param name string",
    "---@param value string",
    "---@param opts? {path?: string, domain?: string, max_age?: integer, expires?: string, secure?: boolean, http_only?: boolean, same_site?: 'Lax'|'Strict'|'None'|'lax'|'strict'|'none'}",
    "---@return string",
    "function Context:set_cookie(name, value, opts) end",
    "",
    "---@param name string",
    "---@return MeteoriteHttpClient",
    "function Context:http(name) end",
    "",
    "---@param name string",
    "---@return MeteoriteAuthClient",
    "function Context:auth(name) end",
    "",
    "---@param name string",
    "---@return MeteoriteZigClient",
    "function Context:zig(name) end",
    "",
    "---@param key string",
    "---@return any",
    "function Context:get(key) end",
    "",
    "---@param key string",
    "---@param value any",
    "function Context:set(key, value) end",
    "",
    "---@class MeteoriteHttpClient",
    "---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): table",
    "---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): table",
    "---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): table",
    "---@field patch fun(self: MeteoriteHttpClient, path: string, opts?: table): table",
    "---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): table",
    "local HttpClient = {}",
    "",
    "---@class MeteoriteAuthClient",
    "---@field headers fun(self: MeteoriteAuthClient): table<string, string>",
    "local AuthClient = {}",
    "",
    "---@class MeteoriteZigClient",
    "---@field [string] function",
    "local ZigClient = {}",
    "",
  }) do lines[#lines + 1] = line end
  for _, route in ipairs(graph.routes) do
    if #route.params > 0 then
      local class_name = "MeteoriteParams_" .. helpers.zig_ident(route.id)
      lines[#lines + 1] = "---@class " .. class_name
      for _, param in ipairs(route.params) do
        local lua_type = (param.type == "u64" or param.type == "i32") and "integer" or "string"
        lines[#lines + 1] = "---@field " .. param.name .. " " .. lua_type
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---@class MeteoriteContext_" .. helpers.zig_ident(route.id) .. " : MeteoriteContext"
      lines[#lines + 1] = "---@field params " .. class_name
      lines[#lines + 1] = ""
    end
    if #(route.query or {}) > 0 then
      local class_name = "MeteoriteQuery_" .. helpers.zig_ident(route.id)
      lines[#lines + 1] = "---@class " .. class_name
      for _, item in ipairs(route.query) do
        local lua_type = (item.type == "u64" or item.type == "i32") and "integer" or (item.type == "bool" and "boolean" or "string")
        if item.optional then lua_type = lua_type .. "|nil" end
        lines[#lines + 1] = "---@field " .. item.name .. " " .. lua_type
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---@class MeteoriteContext_" .. helpers.zig_ident(route.id) .. " : MeteoriteContext"
      lines[#lines + 1] = "---@field query " .. class_name
      lines[#lines + 1] = ""
    end
  end
  lines[#lines + 1] = "return meteorite"
  local meteorite_module = table.concat(lines, "\n") .. "\n"
  helpers.write_file(aid_dir .. "/meteorite.lua", meteorite_module)
  helpers.write_file(aid_dir .. "/meteorite.meta.lua", meteorite_module)

  local route_lines = {
    "---@meta",
    "",
    "---@diagnostic disable: missing-return, lowercase-global",
    "",
  }
  for _, route in ipairs(graph.routes) do
    local route_id = helpers.zig_ident(route.id)
    if #route.params > 0 then
      route_lines[#route_lines + 1] = "---@class MeteoriteParams_" .. route_id
      for _, param in ipairs(route.params) do
        local lua_type = (param.type == "u64" or param.type == "i32") and "integer" or "string"
        route_lines[#route_lines + 1] = "---@field " .. param.name .. " " .. lua_type
      end
      route_lines[#route_lines + 1] = ""
    end
    if #(route.query or {}) > 0 then
      route_lines[#route_lines + 1] = "---@class MeteoriteQuery_" .. route_id
      for _, item in ipairs(route.query) do
        local lua_type = (item.type == "u64" or item.type == "i32") and "integer" or (item.type == "bool" and "boolean" or "string")
        if item.optional then lua_type = lua_type .. "|nil" end
        route_lines[#route_lines + 1] = "---@field " .. item.name .. " " .. lua_type
      end
      route_lines[#route_lines + 1] = ""
    end
    route_lines[#route_lines + 1] = "---@class MeteoriteContext_" .. route_id .. " : MeteoriteContext"
    if #route.params > 0 then route_lines[#route_lines + 1] = "---@field params MeteoriteParams_" .. route_id end
    if #(route.query or {}) > 0 then route_lines[#route_lines + 1] = "---@field query MeteoriteQuery_" .. route_id end
    route_lines[#route_lines + 1] = ""
  end
  helpers.write_file(aid_dir .. "/routes.meta.lua", table.concat(route_lines, "\n") .. "\n")
  helpers.write_file(aid_dir .. "/lfs.lua", table.concat({
    "---@meta",
    "",
    "---@class LuaFileSystem",
    "---@field currentdir fun(): string",
    "---@field chdir fun(path: string): boolean|string, string?",
    "---@field mkdir fun(path: string): boolean|string, string?",
    "---@field rmdir fun(path: string): boolean|string, string?",
    "---@field attributes fun(path: string, attributename?: string): table|string|number|boolean|nil, string?",
    "---@field dir fun(path: string): fun(): string?",
    "---@type LuaFileSystem",
    "local lfs = {}",
    "return lfs",
    "",
  }, "\n"))
  fs.mkdir_p(aid_dir .. "/luasql")
  helpers.write_file(aid_dir .. "/luasql/sqlite3.lua", table.concat({
    "---@meta",
    "",
    "---@class LuaSqlCursor",
    "---@field fetch fun(self: LuaSqlCursor, row?: table, mode?: string): table|nil",
    "---@field close fun(self: LuaSqlCursor): boolean|nil, string?",
    "",
    "---@class LuaSqlConnection",
    "---@field execute fun(self: LuaSqlConnection, sql: string): LuaSqlCursor|integer|nil, string?",
    "---@field close fun(self: LuaSqlConnection): boolean|nil, string?",
    "---@field getlastautoid fun(self: LuaSqlConnection): integer",
    "",
    "---@class LuaSqlEnvironment",
    "---@field connect fun(self: LuaSqlEnvironment, database: string): LuaSqlConnection|nil, string?",
    "---@field close fun(self: LuaSqlEnvironment): boolean|nil, string?",
    "",
    "---@class LuaSqlSqlite3Module",
    "---@field sqlite3 fun(): LuaSqlEnvironment",
    "---@type LuaSqlSqlite3Module",
    "local sqlite3 = {}",
    "return sqlite3",
    "",
  }, "\n"))
end

return report
