local source = debug.getinfo(1, "S").source:gsub("^@", "")
local met_dir = source:match("^(.*)/meteorite%.lua$") or source:match("^(.*)/src/meteorite%.lua$")
if met_dir then
  local sub_dir = met_dir .. "/meteorite"
  package.path = table.concat({
    sub_dir .. "/?.lua",
    sub_dir .. "/?/init.lua",
    met_dir .. "/?.lua",
    met_dir .. "/?/init.lua",
    package.path,
  }, ";")
end

local app_core = require("core.app")
local schema_exports = require("core.schema_exports")
local handler_exports = require("core.handler_exports")
local utility_exports = require("core.utility_exports")

---@class MeteoriteAppOptions
---@field name? string
---@field profile? string|MeteoriteProfile
---@field host? string bind address (default "127.0.0.1")
---@field port? integer bind port (default 8080)
---@field trusted_proxy? nil unsupported in the current release; proxy-derived IP headers remain untrusted
---@field trust_proxy? nil unsupported alias
---@field trusted_proxies? nil unsupported alias

---@class MeteoriteRouteOptions
---@field params? table<string, MeteoriteSchemaValue>
---@field query? table<string, MeteoriteSchemaValue>
---@field body? {max?: number|string, [string]: any}
---@field memory? {max_body?: number|string, request_arena?: number|string}
---@field capabilities? table<string, any>
---@field message? string|{name?: string, pattern?: string}
---@field metadata? table<string, MeteoriteSchemaValue>
---@field plugins? table
---@field context? table
---@field id? string

---@class MeteoriteCanonicalRouteSpec
---@field route string Route path pattern (e.g. "/users/:id")
---@field handler? MeteoriteHandler Route handler
---@field pipeline? fun(p: any) Multi-stage pipeline builder
---@field params? table<string, MeteoriteSchemaValue> Path parameter validators
---@field query? table<string, MeteoriteSchemaValue> Query parameter validators
---@field body? {max?: number|string, [string]: any} Body limits
---@field memory? {max_body?: number|string, request_arena?: number|string} Resource limits
---@field capabilities? table<string, any> Capabilities required
---@field message? string|{name?: string, pattern?: string} Native message name
---@field metadata? table<string, MeteoriteSchemaValue> Native metadata
---@field policy? table Route plugin policy
---@field hooks? table Route hook overrides
---@field id? string Route identifier

--- Handler context for inline Lua and Lua-file handlers.
--- Use `ctx` or `c` as the first parameter name for lazy_context mode
--- (method-based access). Use `req` for request_table mode (table access).
---@class MeteoriteContext
---@field params table<string, string|integer|number|boolean> Route path parameters (table access in request_table mode)
---@field state table<string, any> Request-local mutable state
---@field scope table<string, string|integer|number|boolean|table> Read-only effective mounted-scope context
---@field query table<string, string|integer|number|boolean|nil> Validated query values (table access in request_table mode)
---@field param fun(self: MeteoriteContext, name: string): string|integer|nil Look up a route parameter by name
---@field query fun(self: MeteoriteContext, name: string): string|nil Look up a percent-decoded query value (first-wins for repeated keys)
---@field query_all fun(self: MeteoriteContext, name: string): string[]|nil Look up all values for a repeated query parameter
---@field message fun(self: MeteoriteContext): string Native message name for ipc_unixsocket requests
---@field metadata fun(self: MeteoriteContext, name: string): string|nil Native IPC metadata lookup; distinct from HTTP headers
---@field header fun(self: MeteoriteContext, name: string): string|nil Case-insensitive HTTP request header lookup; nil on native IPC backends
---@field body fun(self: MeteoriteContext): string Raw request body (cached, single-read)
---@field json_body fun(self: MeteoriteContext): table|nil, string|nil Parse JSON body, returns (data, err)
---@field form_body fun(self: MeteoriteContext): table|nil, string|nil Parse URL-encoded form body, returns (data, err)
---@field text fun(self: MeteoriteContext, status_or_body: integer|string, body?: string, opts?: {headers?: table<string, string>}): table Response helper: text/plain; charset=utf-8
---@field json fun(self: MeteoriteContext, status_or_value: integer|table, value?: table, opts?: {status?: integer, headers?: table<string, string>}): table Response helper: application/json
---@field pretty_json fun(self: MeteoriteContext, status_or_value: integer|table, value?: table, opts?: {status?: integer, headers?: table<string, string>}): table Response helper: pretty-printed application/json
---@field bytes fun(self: MeteoriteContext, status: integer, content_type: string, body: string, opts?: {headers?: table<string, string>}): table Response helper: arbitrary content type
---@field timeout fun(self: MeteoriteContext, ms: number, fn: function): table Run a function with a timeout; returns 504 if exceeded
---@field html fun(self: MeteoriteContext, status_or_body: integer|string, body?: string, opts?: {headers?: table<string, string>}): table Response helper: text/html; charset=utf-8
---@field escape_html fun(self: MeteoriteContext, value: string): string Escape HTML special characters to prevent XSS
---@field compression_headers fun(self: MeteoriteContext, opts?: {encoding?: string, vary?: string[]}): table<string, string> Build compression-related headers with correct Vary
---@field cookie fun(self: MeteoriteContext, name: string): string|nil Parse request cookie by name
---@field set_cookie fun(self: MeteoriteContext, name: string, value: string, opts?: {path?: string, domain?: string, max_age?: integer, expires?: string, secure?: boolean, http_only?: boolean, same_site?: string}): string Build a Set-Cookie header value with secure defaults
---@field request_id fun(self: MeteoriteContext): string Get or generate a safe X-Request-ID
---@field secure_headers fun(self: MeteoriteContext, opts?: table): table<string, string> Build secure response headers
---@field cors_headers fun(self: MeteoriteContext, opts?: table): table<string, string> Build CORS response headers
---@field constant_time_equal fun(self: MeteoriteContext, left: string, right: string): boolean Constant-time string comparison
---@field basic_auth fun(self: MeteoriteContext): string|nil, string|nil Parse Basic auth, returns (username, password)
---@field bearer_token fun(self: MeteoriteContext): string|nil Parse Bearer token from Authorization header
---@field safe_header fun(self: MeteoriteContext, name: string): string|nil Redact sensitive header for logging
---@field safe_headers fun(self: MeteoriteContext, names: string[]): table<string, string> Redact sensitive headers for logging
---@field log fun(self: MeteoriteContext, level: string|table, message?: string|table, fields?: table, opts?: {format?: string}): table Structured logging helper
---@field timing_stage fun(self: MeteoriteContext, metrics: table, name: string, fn: function, opts?: {desc?: string}): any Record a timing stage
---@field server_timing fun(self: MeteoriteContext, metrics: table): table<string, string> Build Server-Timing header
---@field http fun(self: MeteoriteContext, name: string): MeteoriteHttpClient Get HTTP capability client
---@field auth fun(self: MeteoriteContext, name: string): MeteoriteAuthClient Get auth capability client
---@field zig fun(self: MeteoriteContext, name: string): MeteoriteZigClient Get Zig helper capability
---@field get fun(self: MeteoriteContext, key: string): any Get request-local state value
---@field set fun(self: MeteoriteContext, key: string, value: any): any Set request-local state value
---@field scope fun(self: MeteoriteContext, name: string): any Get scope context value

---@alias MeteoriteHandler string|fun(c: MeteoriteContext): string|table|nil|{kind: "lua", module: string, path?: string}|{kind: "zig", symbol: string}|{kind: "zig_file", path: string, decl?: string}
--- A bare string return is sugar for 200 text/plain; charset=utf-8.
--- A table return provides {status?, content_type?, body?, headers?}.
--- nil means no response (204 if no response helper was called).

---@type MeteoriteModule
local M = {}

local plugin_counter = 0

local function source_info(level)
  local info = debug.getinfo(level or 2, "Sl") or {}
  local source = tostring(info.source or "")
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  return { file = source ~= "" and source or "<unknown>", line = info.currentline or 0, column = 1 }
end

--- HTTP capability client for outbound requests.
---@class MeteoriteHttpClient
---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field patch fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse

---@class MeteoriteHttpResponse
---@field status integer
---@field headers table<string, string>
---@field body any

--- Auth capability client for token management.
---@class MeteoriteAuthClient
---@field bearer fun(self: MeteoriteAuthClient): string Get bearer token
---@field authorization fun(self: MeteoriteAuthClient): string Get authorization header value
---@field headers fun(self: MeteoriteAuthClient): table<string, string> Get auth headers table
---@field refresh fun(self: MeteoriteAuthClient): string Refresh token

--- Zig helper capability client.
---@class MeteoriteZigClient
---@field [string] any Zig helper functions

--- Plugin/middleware specification for scoped execution.
---@class MeteoritePlugin
---@field kind string Plugin kind identifier
---@field id string Unique plugin id
---@field execute fun(ctx: MeteoriteContext): string|table|nil Plugin entry point; return a response to short-circuit
---@field options table Plugin options
---@field __meteorite_plugin true

---@class MeteoriteModule
---@field patterns table
---@field profiles table
---@field template table Small dependency-free `{{name}}` string template helper; not an HTML engine
---@field app fun(opts?: MeteoriteAppOptions): MeteoriteApp
---@field profile fun(name_or_table?: string|table, opts?: table): table
---@field string fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean, validate?: string|function|table, pattern?: MeteoritePattern}): MeteoriteSchemaValue
---@field slug fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field u64 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field i32 fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field uuid fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field hex fun(opts?: {len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field email fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field token fun(opts?: {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field bool fun(opts?: {optional?: boolean, decode?: boolean}): MeteoriteSchemaValue
---@field pattern fun(name_or_source: string, source_or_opts?: string|table, opts?: table): MeteoritePattern
---@field zig fun(path_or_symbol: string, opts?: {decl?: string}): table
---@field lua fun(module_ref: string): table
---@field file fun(path: string, opts?: table): table
---@field dir fun(root: string, opts?: table): table
---@field site fun(app: MeteoriteApp, opts: table): MeteoriteApp
local MDoc = {}

---@param opts? MeteoriteAppOptions
---@return MeteoriteApp
function M.app(opts)
  return app_core.new(opts)
end

---@class MeteoritePatternDef
---@field type "string"|"slug"|"u64"|"i32"|"uuid"|"hex"|"email"|"token"|"bool"|"pattern"
---@field optional? boolean
---@field decode? boolean
---@field max_len? integer
---@field exact_len? integer
---@field min? integer
---@field max? integer
---@field pattern? MeteoritePattern
---@field validator? any

---@class MeteoriteSchemaValue : MeteoritePatternDef

schema_exports.install(M)

handler_exports.install(M)

utility_exports.install(M)

---@param spec table
---@return table
function M.plugin(spec)
  spec = spec or {}
  plugin_counter = plugin_counter + 1
  spec.__meteorite_plugin = true
  spec.kind = spec.kind or "custom"
  spec.id = spec.id or (spec.kind .. "_" .. tostring(plugin_counter))
  spec.options = spec.options or {}
  spec.source = spec.source or source_info(3)
  return spec
end

return M
