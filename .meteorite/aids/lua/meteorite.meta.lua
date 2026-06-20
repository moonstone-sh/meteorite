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
---@type MeteoriteModule
local meteorite = {}

---@class MeteoriteContext
---@field params table
---@field query table
---@field state table
local Context = {}

---@param body string
function Context:text(body) end

---@param value table|string|number|boolean
function Context:json(value) end

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

---@class MeteoriteParams_get_user
---@field id integer

---@class MeteoriteContext_get_user : MeteoriteContext
---@field params MeteoriteParams_get_user

---@class MeteoriteParams_put_user
---@field id integer

---@class MeteoriteContext_put_user : MeteoriteContext
---@field params MeteoriteParams_put_user

---@class MeteoriteParams_patch_user
---@field id integer

---@class MeteoriteContext_patch_user : MeteoriteContext
---@field params MeteoriteParams_patch_user

---@class MeteoriteParams_delete_user
---@field id integer

---@class MeteoriteContext_delete_user : MeteoriteContext
---@field params MeteoriteParams_delete_user

---@class MeteoriteParams_get_device
---@field device_id string

---@class MeteoriteContext_get_device : MeteoriteContext
---@field params MeteoriteParams_get_device

---@class MeteoriteParams_file
---@field name string

---@class MeteoriteContext_file : MeteoriteContext
---@field params MeteoriteParams_file

---@class MeteoriteParams_slug
---@field slug string

---@class MeteoriteContext_slug : MeteoriteContext
---@field params MeteoriteParams_slug

---@class MeteoriteParams_uuid
---@field id string

---@class MeteoriteContext_uuid : MeteoriteContext
---@field params MeteoriteParams_uuid

---@class MeteoriteParams_hex
---@field digest string

---@class MeteoriteContext_hex : MeteoriteContext
---@field params MeteoriteParams_hex

---@class MeteoriteParams_email
---@field email string

---@class MeteoriteContext_email : MeteoriteContext
---@field params MeteoriteParams_email

---@class MeteoriteParams_token
---@field token string

---@class MeteoriteContext_token : MeteoriteContext
---@field params MeteoriteParams_token

---@class MeteoriteQuery_search
---@field exact boolean|nil
---@field page integer|nil
---@field q string

---@class MeteoriteContext_search : MeteoriteContext
---@field query MeteoriteQuery_search

---@class MeteoriteParams_hybrid_inline_params
---@field id integer

---@class MeteoriteContext_hybrid_inline_params : MeteoriteContext
---@field params MeteoriteParams_hybrid_inline_params

return meteorite
