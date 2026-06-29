local route = require("core.route")
local contract = require("core.contract")
local schema = require("core.schema")
local patterns = require("core.patterns")
local profile_mod = require("core.profile")
local handler_factories = require("core.handler_factories")
local site_macro = require("core.site")

---@class MeteoriteAppOptions
---@field name? string
---@field profile? string|MeteoriteProfile
---@field host? string bind address (default "127.0.0.1")
---@field port? integer bind port (default 8080)

---@class MeteoriteRouteOptions
---@field params? table<string, MeteoriteSchemaValue>
---@field query? table<string, MeteoriteSchemaValue>
---@field body? {max?: number|string, [string]: any}
---@field memory? {max_body?: number|string, request_arena?: number|string}
---@field capabilities? table<string, any>
---@field plugins? table
---@field context? table
---@field id? string

---@alias MeteoriteHandler string|fun(c: MeteoriteContext): any|{kind: "lua", module: string, path?: string}|{kind: "zig", symbol: string}|{kind: "zig_file", path: string, decl?: string}

---@type MeteoriteModule
local M = {}

local plugin_counter = 0

local App = {}
App.__index = App

local function normalize_args(path, options, handler)
  if handler == nil then
    handler = options
    options = {}
  end
  return path, options or {}, handler
end

local function add_route(self, method, path_or_table, options_or_handler, maybe_handler)
  -- Detect canonical table form: app:get({ route = "/path", pipeline = ... })
  if type(path_or_table) == "table" and path_or_table.route ~= nil then
    local scope = self.__meteorite_scope
    local rc = contract.build(method, path_or_table, scope)
    -- Lower RouteContract to the existing declaration format
    local declaration
    if rc.pipeline and #rc.pipeline > 0 then
      -- Pipeline form: use the last handle stage (or first stage) as the handler
      -- for backward compat with the existing graph system
      local handler_stage = nil
      for _, stage in ipairs(rc.pipeline) do
        if stage.kind == "handle" then handler_stage = stage end
      end
      if not handler_stage then
        handler_stage = rc.pipeline[#rc.pipeline]
      end
      -- Lower the handler stage to the existing handler_shape format
      if handler_stage.strat == "inline_lua" then
        declaration = route.declare(method, rc.route, {
          params = rc.params, query = rc.query, body = rc.body,
          memory = rc.memory, capabilities = rc.capabilities, scope = scope,
        }, handler_stage.fn_ref)
        declaration.handler = { kind = "inline_lua", value = handler_stage.fn_ref }
      elseif handler_stage.strat == "lua" then
        declaration = route.declare(method, rc.route, {
          params = rc.params, query = rc.query, body = rc.body,
          memory = rc.memory, capabilities = rc.capabilities, scope = scope,
        }, { kind = "lua", path = handler_stage.path, module = handler_stage.module })
      elseif handler_stage.strat == "zig" then
        declaration = route.declare(method, rc.route, {
          params = rc.params, query = rc.query, body = rc.body,
          memory = rc.memory, capabilities = rc.capabilities, scope = scope,
        }, handler_stage.symbol and handler_stage.symbol or handler_stage.path)
        if handler_stage.path then
          declaration.handler = { kind = "zig_file", path = handler_stage.path, decl = handler_stage.decl or "handle" }
        end
      end
      -- Store the pipeline on the declaration for graph inspection
      declaration.pipeline = rc.pipeline
      declaration.policy = rc.policy
      declaration.source_form = rc._source_form
    elseif rc.handler then
      -- Special file/dir handler
      declaration = route.declare(method, rc.route, {
        params = rc.params, query = rc.query, body = rc.body,
        memory = rc.memory, capabilities = rc.capabilities, scope = scope,
      }, rc.handler)
      declaration.policy = rc.policy
    else
      -- No handler or pipeline — shouldn't happen after validation
      declaration = route.declare(method, rc.route, {
        params = rc.params, query = rc.query, body = rc.body,
        memory = rc.memory, capabilities = rc.capabilities, scope = scope,
      }, "handlers.unreachable")
      declaration.policy = rc.policy
    end
    self.routes[#self.routes + 1] = declaration
    return declaration
  end

  -- Legacy positional form: app:get(path, opts?, handler)
  local path, options, handler = normalize_args(path_or_table, options_or_handler, maybe_handler)
  if self.__meteorite_scope then
    options.scope = self.__meteorite_scope
  end
  local declaration = route.declare(method, path, options, handler)
  declaration.source_form = "legacy_signature"
  self.routes[#self.routes + 1] = declaration
  return declaration
end

local function join_path(prefix, path)
  if prefix == nil or prefix == "" or prefix == "/" then return path end
  if path == "/" then return prefix end
  return prefix:gsub("/$", "") .. path
end

local function merge_map(parent, child)
  local out = {}
  for k, v in pairs(parent or {}) do out[k] = v end
  for k, v in pairs(child or {}) do out[k] = v end
  return out
end

local function append_list(parent, child)
  local out = {}
  for _, value in ipairs(parent or {}) do out[#out + 1] = value end
  for _, value in ipairs(child or {}) do out[#out + 1] = value end
  return out
end

local function root_scope()
  return { id = "root", parent = "", path_prefix = "", chain = {}, plugins = {}, context = {} }
end

local function scope_ref(scope)
  return { id = scope.id or "root", path_prefix = scope.path_prefix or "" }
end

local function scope_chain(parent_scope, mounted_scope)
  local out = {}
  for _, item in ipairs(parent_scope.chain or {}) do out[#out + 1] = item end
  out[#out + 1] = scope_ref(mounted_scope)
  return out
end

local function scope_id(prefix)
  local value = tostring(prefix or "/"):gsub("^/", ""):gsub("/$", "")
  if value == "" then return "root" end
  return value:gsub("%W", "_")
end


local function source_info(level)
  local info = debug.getinfo(level or 3, "Sl") or {}
  local source = info.source or info.short_src or "<unknown>"
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  return { file = source, line = info.currentline or info.linedefined or 0, column = 1 }
end

---@class MeteoriteApp
---@field name string
---@field routes table
---@field middleware table
---@field capabilities table<string, any>
---@field cache table
---@field options table
---@field profile string|table|nil
---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field get fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field head fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field head fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field use fun(self: MeteoriteApp, plugin_or_middleware: table|function, options?: table): MeteoriteApp
---@field mount fun(self: MeteoriteApp, prefix: string, options_or_fn?: table|function, maybe_fn?: function): MeteoriteApp
---@field scope fun(self: MeteoriteApp, prefix: string, options_or_fn?: table|function, maybe_fn?: function): MeteoriteApp
---@field capability fun(self: MeteoriteApp, kind: string, spec: table): MeteoriteApp
---@field normalize fun(self: MeteoriteApp, opts?: {mode?: string}): table
---@field __meteorite_app true
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
function App:head(path, options, handler)
  return add_route(self, "HEAD", path, options, handler)
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:post(path, options, handler)
  return add_route(self, "POST", path, options, handler)
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:put(path, options, handler)
  return add_route(self, "PUT", path, options, handler)
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:patch(path, options, handler)
  return add_route(self, "PATCH", path, options, handler)
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:delete(path, options, handler)
  return add_route(self, "DELETE", path, options, handler)
end

---@param plugin_or_middleware table|function
---@param options? table
---@return MeteoriteApp
function App:use(plugin_or_middleware, options)
  if type(plugin_or_middleware) == "table" and plugin_or_middleware.__meteorite_graph_plugin then
    -- Graph plugin (new contract system) — register for graph passes
    self.graph_plugins = self.graph_plugins or {}
    self.graph_plugins[#self.graph_plugins + 1] = plugin_or_middleware
    return self
  end
  if type(plugin_or_middleware) == "table" and plugin_or_middleware.__meteorite_plugin then
    -- Legacy scope plugin — register in scope chain
    local plugin = plugin_or_middleware
    options = options or {}
    if plugin.options then
      for k, v in pairs(options) do plugin.options[k] = v end
    else
      plugin.options = options
    end
    local scope = self.__meteorite_scope or root_scope()
    scope.plugins = scope.plugins or {}
    scope.plugins[#scope.plugins + 1] = plugin
    return self
  end
  self.middleware[#self.middleware + 1] = plugin_or_middleware
  return self
end

---@param prefix string
---@param options_or_fn? table|function
---@param maybe_fn? function
---@return MeteoriteApp
function App:mount(prefix, options_or_fn, maybe_fn)
  local options = type(options_or_fn) == "table" and options_or_fn or {}
  local build_fn = type(options_or_fn) == "function" and options_or_fn or maybe_fn
  assert(type(prefix) == "string" and prefix:sub(1, 1) == "/", "mount prefix must start with /")
  assert(type(build_fn) == "function", "mount requires a function")
  local parent_scope = self.__meteorite_scope or root_scope()
  local mounted_scope = {
    id = options.id or scope_id(join_path(parent_scope.path_prefix or "", prefix)),
    parent = parent_scope.id or "root",
    path_prefix = join_path(parent_scope.path_prefix or "", prefix),
    plugins = append_list(parent_scope.plugins, options.plugins),
    context = merge_map(parent_scope.context, options.context),
  }
  mounted_scope.chain = scope_chain(parent_scope, mounted_scope)
  local child = setmetatable({
    name = self.name,
    routes = {},
    middleware = {},
    capabilities = self.capabilities,
    cache = self.cache,
    options = self.options,
    profile = self.profile,
    __meteorite_scope = mounted_scope,
    __meteorite_app = true,
  }, App)
  build_fn(child)
  for _, declaration in ipairs(child.routes) do
    declaration.raw_path = join_path(prefix, declaration.raw_path)
    declaration.path = { segments = route.parse_path(declaration.raw_path) }
    declaration.params = merge_map(options.params, declaration.params)
    declaration.query = merge_map(options.query, declaration.query)
    declaration.capabilities = merge_map(options.capabilities, declaration.capabilities)
    self.routes[#self.routes + 1] = declaration
  end
  return self
end

App.scope = App.mount

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
      profile = opts.profile,
      __meteorite_scope = root_scope(),
      __meteorite_app = true,
    }, App)
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

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.email(opts) return schema.scalar("email", opts) end

---@param opts? {max?: integer, max_len?: integer, optional?: boolean, decode?: boolean}
---@return MeteoriteSchemaValue
---@return MeteoriteSchemaValue
function M.token(opts) return schema.scalar("token", opts) end

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
function M.zig(path_or_symbol, opts) return handler_factories.zig(path_or_symbol, opts) end

---@param module_ref string
---@return {kind: "lua", module: string, path: string}
function M.lua(module_ref) return handler_factories.lua(module_ref) end

---@param path string
---@param opts? {content_type?: string, cache?: string, only?: table, name?: string}
---@return table
function M.file(path, opts) return handler_factories.file(path, opts) end

---@param root string
---@param opts table
---@return table
function M.dir(root, opts) return handler_factories.dir(root, opts) end

---@param app MeteoriteApp
---@param opts table
---@return MeteoriteApp
function M.site(app, opts) return site_macro.apply(app, opts, handler_factories) end

---@param kind "zig"|"zig_file"|"lua"
---@param ref string
---@param opts? {decl?: string, path?: string}
---@return {kind: string, symbol?: string, path?: string, module?: string, decl?: string}
function M.handler(kind, ref, opts) return handler_factories.handler(kind, ref, opts) end

M.patterns = patterns
M.profiles = profile_mod.profiles

---@param name_or_table? string|table
---@param opts? table
---@return table
function M.profile(name_or_table, opts)
  return profile_mod.define(name_or_table, opts)
end

---@param message string
---@return {kind: "validation_error", message: string}
function M.validation_error(message)
  return { kind = "validation_error", message = message }
end

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

---@param map table
---@return table
function M.context(map)
  map = map or {}
  map.__meteorite_context = true
  return map
end

---@param value any
---@return {__meteorite_enum: true, value: any}
function M._enum(value)
  return { __meteorite_enum = true, value = value }
end

return M
