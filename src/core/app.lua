--- Meteorite app construction, routing, mounting, and normalization.

local route = require("core.route")
local contract = require("core.contract")
local scope_model = require("core.scope")

local app_core = {}

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
          memory = rc.memory, capabilities = rc.capabilities, message = rc.message, message_source = rc.message_source, scope = scope,
        }, handler_stage.fn_ref)
        declaration.handler = { kind = "inline_lua", value = handler_stage.fn_ref }
      elseif handler_stage.strat == "lua" then
        declaration = route.declare(method, rc.route, {
          params = rc.params, query = rc.query, body = rc.body,
          memory = rc.memory, capabilities = rc.capabilities, message = rc.message, message_source = rc.message_source, scope = scope,
        }, { kind = "lua", path = handler_stage.path, module = handler_stage.module })
      elseif handler_stage.strat == "zig" then
        declaration = route.declare(method, rc.route, {
          params = rc.params, query = rc.query, body = rc.body,
          memory = rc.memory, capabilities = rc.capabilities, message = rc.message, message_source = rc.message_source, scope = scope,
        }, handler_stage.symbol and handler_stage.symbol or handler_stage.path)
        if handler_stage.path then
          declaration.handler = { kind = "zig_file", path = handler_stage.path, decl = handler_stage.decl or "handle" }
        end
      end
      declaration.id = rc.id
      -- Store the pipeline on the declaration for graph inspection
      declaration.pipeline = rc.pipeline
      declaration.policy = rc.policy
      declaration.source_form = rc._source_form
    elseif rc.handler then
      -- Special file/dir handler
      declaration = route.declare(method, rc.route, {
        params = rc.params, query = rc.query, body = rc.body,
        memory = rc.memory, capabilities = rc.capabilities, message = rc.message, message_source = rc.message_source, scope = scope,
      }, rc.handler)
      declaration.id = rc.id
      declaration.policy = rc.policy
    else
      -- No handler or pipeline — shouldn't happen after validation
      declaration = route.declare(method, rc.route, {
        params = rc.params, query = rc.query, body = rc.body,
        memory = rc.memory, capabilities = rc.capabilities, message = rc.message, message_source = rc.message_source, scope = scope,
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
---@field get fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field get fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field head fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field head fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field head fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field post fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field post fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field put fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field put fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field patch fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field patch fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field delete fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field delete fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field all fun(self: MeteoriteApp, spec: MeteoriteCanonicalRouteSpec): table
---@field all fun(self: MeteoriteApp, path: string, options: MeteoriteRouteOptions, handler: MeteoriteHandler): table
---@field route fun(self: MeteoriteApp, method: string, path: string, options_or_handler?: MeteoriteRouteOptions|MeteoriteHandler, maybe_handler?: MeteoriteHandler): table
---@field message fun(self: MeteoriteApp, name: string, options_or_handler?: MeteoriteRouteOptions|MeteoriteHandler, maybe_handler?: MeteoriteHandler): table
---@field websocket fun(self: MeteoriteApp, path: string, ...): nil Unsupported in the current release; fails with an explicit diagnostic
---@field ws fun(self: MeteoriteApp, path: string, ...): nil Unsupported alias for websocket
---@field use fun(self: MeteoriteApp, plugin_or_middleware: table|function, options?: table): MeteoriteApp
---@field mount fun(self: MeteoriteApp, prefix: string, options_or_fn?: table|function, maybe_fn?: function): MeteoriteApp
---@field scope fun(self: MeteoriteApp, prefix: string, options_or_fn?: table|function, maybe_fn?: function): MeteoriteApp
---@field capability fun(self: MeteoriteApp, kind: string, spec: table): MeteoriteApp
---@field normalize fun(self: MeteoriteApp, opts?: {mode?: string}): table
---@field __meteorite_app true
local AppDoc = {}

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:get(path_or_spec, options, handler)
  return add_route(self, "GET", path_or_spec, options, handler)
end

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:head(path_or_spec, options, handler)
  return add_route(self, "HEAD", path_or_spec, options, handler)
end

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:post(path_or_spec, options, handler)
  return add_route(self, "POST", path_or_spec, options, handler)
end

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:put(path_or_spec, options, handler)
  return add_route(self, "PUT", path_or_spec, options, handler)
end

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:patch(path_or_spec, options, handler)
  return add_route(self, "PATCH", path_or_spec, options, handler)
end

---@param path_or_spec string|MeteoriteCanonicalRouteSpec
---@param options? MeteoriteRouteOptions|MeteoriteHandler
---@param handler? MeteoriteHandler
---@return table
function App:delete(path_or_spec, options, handler)
  return add_route(self, "DELETE", path_or_spec, options, handler)
end

---@param method string
---@param path string
---@param options_or_handler? MeteoriteRouteOptions|MeteoriteHandler
---@param maybe_handler? MeteoriteHandler
---@return table
function App:route(method, path, options_or_handler, maybe_handler)
  return add_route(self, string.upper(method), path, options_or_handler, maybe_handler)
end

local function unsupported_websocket(path)
  error(table.concat({
    "Meteorite does not support WebSocket routes in the current service-layer release.",
    "",
    "Requested path: " .. tostring(path or "<unknown>"),
    "",
    "Reason: Meteorite currently compiles request/response HTTP and native IPC graphs; connection-upgrade lifecycle, backpressure, and long-lived stream contracts are not part of the release compiler contract yet.",
    "",
    "Use an external WebSocket service/proxy beside the compiled Meteorite server, or expose polling/native IPC messages until WebSocket support is designed.",
  }, "\n"), 2)
end

function App:websocket(path, ...)
  return unsupported_websocket(path)
end

function App:ws(path, ...)
  return unsupported_websocket(path)
end

---@param name string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:message(name, options, handler)
  if type(name) == "table" then
    local decl = {}
    for key, value in pairs(name) do decl[key] = value end
    local message_name = decl.name or (type(decl.message) == "table" and decl.message.name)
    assert(type(message_name) == "string" and message_name ~= "", "message declaration requires name")
    decl.route = decl.route or ("/__meteorite/message/" .. tostring(message_name):gsub("%.", "/"))
    decl.params = decl.metadata or decl.params or {}
    decl.message = { name = message_name }
    decl.message_source = "message"
    local declaration = add_route(self, "OTHER", decl)
    declaration.source_form = "message_canonical"
    return declaration
  end
  if handler == nil then
    handler = options
    options = {}
  end
  options = options or {}
  if self.__meteorite_scope then options.scope = self.__meteorite_scope end
  options.params = options.metadata or options.params or {}
  options.message = { name = name }
  options.message_source = "message"
  local declaration = route.declare("OTHER", "/__meteorite/message/" .. tostring(name):gsub("%.", "/"), options, handler)
  declaration.source_form = "message_signature"
  self.routes[#self.routes + 1] = declaration
  return declaration
end

---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:options(path, options, handler)
  return add_route(self, "OPTIONS", path, options, handler)
end

--- Declare a route that matches any HTTP method.
--- The route is dispatched for GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS.
--- Method-specific routes at the same path take priority over app:all() routes.
---@param path string
---@param options? MeteoriteRouteOptions
---@param handler MeteoriteHandler
---@return table
function App:all(path, options, handler)
  return add_route(self, "ALL", path, options, handler)
end

---@param plugin_or_middleware table|function
---@param options? table
---@return MeteoriteApp
function App:use(plugin_or_middleware, options)
  if type(plugin_or_middleware) == "table" and plugin_or_middleware.__meteorite_graph_plugin then
    self.graph_plugins = self.graph_plugins or {}
    for _, existing in ipairs(self.graph_plugins) do
      if existing.id == plugin_or_middleware.id then
        error("duplicate graph plugin id: " .. tostring(plugin_or_middleware.id), 2)
      end
    end
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
    local scope = self.__meteorite_scope or scope_model.root()
    local attachment = scope_model.attach_plugin(scope, plugin, options)
    self.__meteorite_request_plugins = self.__meteorite_request_plugins or {}
    local existing = self.__meteorite_request_plugins[attachment.id]
    if existing and existing ~= attachment.definition then
      error("conflicting request plugin identity: " .. tostring(attachment.id), 2)
    end
    self.__meteorite_request_plugins[attachment.id] = attachment.definition
    return self
  end
  error(table.concat({
    "raw app:use(function) middleware is not supported",
    "",
    "Raw middleware is not part of Meteorite's normalized release graph and would otherwise be a silent no-op.",
    "",
    "hint: use m.plugin({ id = \"...\", execute = function(ctx) ... end }) for a scoped request plugin,",
    "or use a canonical route pipeline for explicit stage metadata.",
  }, "\n"), 2)
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
  local parent_scope = self.__meteorite_scope or scope_model.root()
  local mounted_scope = scope_model.new_child(parent_scope, prefix, options, source_info(3))
  local registry = self.__meteorite_scope_registry or {}
  if registry[mounted_scope.id] then
    error(table.concat({
      "duplicate mounted scope id",
      "",
      "scope id: " .. tostring(mounted_scope.id),
      "first declaration: " .. tostring(registry[mounted_scope.id].source.file) .. ":" .. tostring(registry[mounted_scope.id].source.line),
      "second declaration: " .. tostring(mounted_scope.source.file) .. ":" .. tostring(mounted_scope.source.line),
      "",
      "hint: scope IDs are globally unique within an app; pass a distinct id = \"...\".",
    }, "\n"), 2)
  end
  registry[mounted_scope.id] = mounted_scope
  self.__meteorite_request_plugins = self.__meteorite_request_plugins or {}
  for _, attachment in ipairs(mounted_scope.plugins) do
    local existing = self.__meteorite_request_plugins[attachment.id]
    local definition = attachment.definition or attachment
    if existing and existing ~= definition then
      error("conflicting request plugin identity: " .. tostring(attachment.id), 2)
    end
    self.__meteorite_request_plugins[attachment.id] = definition
  end
  local child = setmetatable({
    name = self.name,
    routes = {},
    middleware = {},
    capabilities = self.capabilities,
    cache = self.cache,
    options = self.options,
    profile = self.profile,
    __meteorite_scope = mounted_scope,
    __meteorite_scope_registry = registry,
    __meteorite_request_plugins = self.__meteorite_request_plugins,
    __meteorite_app = true,
  }, App)
  build_fn(child)
  for _, declaration in ipairs(child.routes) do
    scope_model.merge_route(mounted_scope, declaration)
    declaration.raw_path = scope_model.join_path(prefix, declaration.raw_path)
    declaration.path = { segments = route.parse_path(declaration.raw_path) }
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


function app_core.new(opts)
  opts = opts or {}
  if opts.trusted_proxy ~= nil or opts.trust_proxy ~= nil or opts.trusted_proxies ~= nil then
    error(table.concat({
      "Meteorite does not support trusted proxy configuration in the current service-layer release.",
      "",
      "Reason: proxy-derived client IP headers require compile-time/startup trust boundaries, CIDR or hop validation, and distinct raw-vs-trusted request APIs before they can be used safely.",
      "Hint: treat Forwarded, X-Forwarded-For, X-Real-IP, and CF-Connecting-IP as untrusted request headers, or enforce trusted proxy policy outside Meteorite for this release.",
    }, "\n"))
  end
  local initial_scope = scope_model.root()
  return setmetatable({
    name = opts.name or "meteorite-app",
    routes = {},
    middleware = {},
    capabilities = {},
    cache = {},
    options = opts,
    profile = opts.profile,
    __meteorite_scope = initial_scope,
    __meteorite_scope_registry = { root = initial_scope },
    __meteorite_request_plugins = {},
    __meteorite_app = true,
  }, App)
end

app_core.App = App

return app_core
