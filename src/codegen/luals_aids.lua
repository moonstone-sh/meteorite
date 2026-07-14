--- LuaLS aid generation for Meteorite graph outputs.

local helpers = require("codegen.helpers")
local fs = require("utils.fs")

local luals_aids = {}

function luals_aids.emit(graph, output)
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
    "---@field trusted_proxy? nil unsupported in the current release; proxy-derived IP headers remain untrusted",
    "---@field trust_proxy? nil unsupported alias",
    "---@field trusted_proxies? nil unsupported alias",
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
    "---@return table|nil",
    "function Context:peer() end",
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

return luals_aids
