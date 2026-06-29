---@meta

---@diagnostic disable: missing-return, lowercase-global

---@class MeteoriteAppOptions
---@field name? string
---@field profile? string|table

---@class MeteoriteRouteOptions
---@field params? table<string, MeteoriteSchemaValue>
---@field query? table<string, MeteoriteSchemaValue>
---@field body? {max?: number|string, [string]: any}
---@field memory? {max_body?: number|string, request_arena?: number|string}
---@field capabilities? table<string, any>

---@alias MeteoriteHandler string|fun(c: MeteoriteContext): any|{kind: string, module?: string, path?: string, symbol?: string, decl?: string}

---@class MeteoriteSchemaValue
---@field type string
---@field optional? boolean
---@field max_len? integer
---@field exact_len? integer
---@field pattern? MeteoritePattern

---@class MeteoritePattern : MeteoriteSchemaValue
---@field id string
---@field kind "pattern"
---@field pattern_id string

---@class MeteoriteApp
---@field name string
---@field routes table
---@field middleware table
---@field capabilities table<string, any>
---@field cache table
---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field get fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field use fun(self: MeteoriteApp, plugin_or_middleware: table|function, options?: table): MeteoriteApp
---@field capability fun(self: MeteoriteApp, kind: string, spec: table): MeteoriteApp
---@field get fun(self: MeteoriteApp, path: "/orders/:id", handler: fun(c: MeteoriteContext_handlers_get_order): any): table
---@field get fun(self: MeteoriteApp, path: "/orders/:id", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_handlers_get_order): any): table
---@field get fun(self: MeteoriteApp, path: "/health", handler: fun(c: MeteoriteContext_health): any): table
---@field get fun(self: MeteoriteApp, path: "/health", options: MeteoriteRouteOptions, handler: fun(c: MeteoriteContext_health): any): table

---@class MeteoriteModule
---@field profiles table
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
---@type MeteoriteModule
local meteorite = {}

---@class MeteoriteContext
---@field params table<string, string|integer|number|boolean>
---@field query table<string, string|integer|number|boolean|nil>
---@field state table<string, any>
local Context = {}

---@param body string
function Context:text(body) end

---@param value table|string|number|boolean
---@param opts? {status?: integer}
function Context:json(value, opts) end

---@param status integer
---@param content_type string
---@param body string
function Context:bytes(status, content_type, body) end

---@return string
function Context:body() end

---@param name string
---@return MeteoriteHttpClient
function Context:http(name) end

---@param name string
---@return MeteoriteAuthClient
function Context:auth(name) end

---@param name string
---@return MeteoriteZigClient
function Context:zig(name) end

---@param key string
---@return any
function Context:get(key) end

---@param key string
---@param value any
function Context:set(key, value) end

---@class MeteoriteHttpClient
---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field patch fun(self: MeteoriteHttpClient, path: string, opts?: table): table
---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): table
local HttpClient = {}

---@class MeteoriteAuthClient
---@field headers fun(self: MeteoriteAuthClient): table<string, string>
local AuthClient = {}

---@class MeteoriteZigClient
---@field [string] function
local ZigClient = {}

---@class MeteoriteParams_handlers_get_order
---@field id integer

---@class MeteoriteContext_handlers_get_order : MeteoriteContext
---@field params MeteoriteParams_handlers_get_order

return meteorite
