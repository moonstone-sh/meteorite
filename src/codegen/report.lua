--- Build report, memory report, and LuaLS aids generation.
--- Extracted from emitter.lua.

local helpers = require("codegen.helpers")
local zon = require("codegen.zon")
local fs = require("utils.fs")

local report = {}
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
    method = helpers.method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    query = query,
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
  for _, route in ipairs(graph.routes or {}) do
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

function report.emit_build_report(graph, output, mode)
  local inline, zig = 0, 0
  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "inline_lua" then inline = inline + 1 end
    if route.handler.kind == "zig" or route.handler.kind == "zig_file" then zig = zig + 1 end
  end
  local memory = graph.memory_report or report.memory_report(graph)
  local lines = {
    "Meteorite build",
    "  mode: " .. (mode == "release-static" and "static" or "hybrid"),
    "  backend: fast_http",
    "  Lua runtime: " .. (mode == "release-static" and "removed" or "included"),
    "  Lua state: single_locked",
    "  workers: auto",
    "  inline Lua handlers: " .. tostring(inline),
    "  Zig handlers: " .. tostring(zig),
    "  HTTP capabilities: " .. (#report.capability_names(graph.capabilities, "http") > 0 and table.concat(report.capability_names(graph.capabilities, "http"), ", ") or "none"),
    "  Auth capabilities: " .. (#report.capability_names(graph.capabilities, "auth") > 0 and table.concat(report.capability_names(graph.capabilities, "auth"), ", ") or "none"),
    "  Zig capabilities: " .. (#report.capability_names(graph.capabilities, "zig") > 0 and table.concat(report.capability_names(graph.capabilities, "zig"), ", ") or "none"),
    "  patterns: " .. tostring(#graph.patterns),
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
    "function Context:text(body) end",
    "",
    "---@param value table|string|number|boolean",
    "---@param opts? {status?: integer}",
    "function Context:json(value, opts) end",
    "",
    "---@param status integer",
    "---@param content_type string",
    "---@param body string",
    "function Context:bytes(status, content_type, body) end",
    "",
    "---@return string",
    "function Context:body() end",
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
