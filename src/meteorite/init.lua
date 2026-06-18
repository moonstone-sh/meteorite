local route = require("meteorite.route")
local schema = require("meteorite.schema")
local patterns = require("meteorite.patterns")

---@class MeteoriteAppOptions
---@field name? string

---@class MeteoriteRouteOptions
---@field params? table<string, MeteoriteSchemaValue>
---@field query? table<string, MeteoriteSchemaValue>
---@field body? {max?: number|string, [string]: any}
---@field memory? {max_body?: number|string, request_arena?: number|string}
---@field capabilities? table<string, any>

---@alias MeteoriteHandler string|fun(c: MeteoriteContext): any|{kind: "lua", module: string, path?: string}|{kind: "zig", symbol: string}|{kind: "zig_file", path: string, decl?: string}

local M = {}

local App = {}
App.__index = App

local function normalize_args(path, options, handler)
  if handler == nil then
    handler = options
    options = {}
  end
  return path, options or {}, handler
end

local function add_route(self, method, path, options, handler)
  path, options, handler = normalize_args(path, options, handler)
  local declaration = route.declare(method, path, options, handler)
  self.routes[#self.routes + 1] = declaration
  return declaration
end

---@class MeteoriteApp
---@field name string
---@field routes table
---@field middleware table
---@field capabilities table<string, any>
---@field cache table
---@field options table
local AppDoc = {}

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:get(path, options, handler)
  return add_route(self, "GET", path, options, handler)
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:post(path, options, handler)
  return add_route(self, "POST", path, options, handler)
end

---@param plugin_or_middleware table|function
---@param options? table
---@return MeteoriteApp
function App:use(plugin_or_middleware, options)
  if type(plugin_or_middleware) == "table" and plugin_or_middleware.__meteorite_plugin then
    plugin_or_middleware.apply(self, options or plugin_or_middleware.options or {})
    return self
  end
  self.middleware[#self.middleware + 1] = plugin_or_middleware
  return self
end

---@param kind string
---@param spec table
---@return MeteoriteApp
function App:capability(kind, spec)
  assert(type(kind) == "string" and kind ~= "", "capability kind must be a non-empty string")
  assert(type(spec) == "table", "capability spec must be a table")
  self.capabilities[kind] = spec
  return self
end

---@param middleware function
---@return table
function App:_add_middleware(middleware)
  self.middleware[#self.middleware + 1] = middleware
  return middleware
end

---@param opts? {mode?: string}
---@return table
function App:normalize(opts)
  return route.normalize_app(self, opts or {})
end

---@class MeteoriteModule
---@field patterns table
local MDoc = {}

---@param opts? MeteoriteAppOptions
---@return MeteoriteApp
function M.app(opts)
  opts = opts or {}
  return setmetatable({
    name = opts.name or "meteorite-app",
    routes = {},
    middleware = {},
    capabilities = {},
    cache = {},
    options = opts,
    __meteorite_app = true,
  }, App)
end

---@class MeteoritePatternDef
---@field type "string"|"slug"|"u64"|"i32"|"uuid"|"hex"|"bool"|"pattern"
---@field optional? boolean
---@field decode? boolean
---@field max_len? integer
---@field exact_len? integer
---@field min? integer
---@field max? integer
---@field pattern? MeteoritePattern
---@field validator? any

---@class MeteoriteSchemaValue : MeteoritePatternDef

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean, validate?: string|function|table}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.string(opts) return schema.scalar("string", opts) end

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.slug(opts) return schema.scalar("slug", opts) end

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.u64(opts) return schema.scalar("u64", opts) end

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.i32(opts) return schema.scalar("i32", opts) end

---@param opts? {optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.uuid(opts) return schema.scalar("uuid", opts) end

---@param opts? {len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.hex(opts) return schema.scalar("hex", opts) end

---@param opts? {optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.bool(opts) return schema.scalar("bool", opts) end

---@class MeteoritePattern
---@field id string
---@field kind "pattern"
---@field name string
---@field type "pattern"
---@field pattern_id string

---@param name_or_source string
---@param source_or_opts? string|table
---@param opts? {max_dfa_states?: integer, max_dfa_bytes?: number|string}
---@return MeteoritePattern
function M.pattern(name_or_source, source_or_opts, opts)
  if type(source_or_opts) == "table" or source_or_opts == nil then
    return patterns.define(nil, name_or_source, source_or_opts)
  end
  return patterns.define(name_or_source, source_or_opts, opts)
end

---@param path_or_symbol string
---@param opts? {decl?: string}
---@return {kind: "zig"|"zig_file", symbol: string, path?: string, decl?: string}
function M.zig(path_or_symbol, opts)
  opts = opts or {}
  if tostring(path_or_symbol):match("%.zig$") or tostring(path_or_symbol):find("/") then
    return { kind = "zig_file", path = path_or_symbol, decl = opts.decl or "handle" }
  end
  return { kind = "zig", symbol = path_or_symbol }
end

---@param module_ref string
---@return {kind: "lua", module: string, path: string}
function M.lua(module_ref)
  return { kind = "lua", module = module_ref, path = module_ref }
end

---@param kind "zig"|"zig_file"|"lua"
---@param ref string
---@param opts? {decl?: string, path?: string}
---@return {kind: string, symbol?: string, path?: string, module?: string, decl?: string}
function M.handler(kind, ref, opts)
  opts = opts or {}
  if kind == "zig" then return { kind = "zig", symbol = ref } end
  if kind == "zig_file" then return { kind = "zig_file", path = ref, decl = opts.decl or "handle" } end
  if kind == "lua" then return { kind = "lua", module = ref, path = opts.path or ref } end
  error("unsupported handler kind: " .. tostring(kind))
end

M.patterns = patterns

---@param message string
---@return {kind: "validation_error", message: string}
function M.validation_error(message)
  return { kind = "validation_error", message = message }
end

---@param spec table
---@return table
function M.plugin(spec)
  spec = spec or {}
  spec.__meteorite_plugin = true
  return spec
end

---@param value any
---@return {__meteorite_enum: true, value: any}
function M._enum(value)
  return { __meteorite_enum = true, value = value }
end

return M
