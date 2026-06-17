local route = require("meteorite.route")
local schema = require("meteorite.schema")
local patterns = require("meteorite.patterns")

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

function App:get(path, options, handler)
  return add_route(self, "GET", path, options, handler)
end

function App:post(path, options, handler)
  return add_route(self, "POST", path, options, handler)
end

function App:use(plugin_or_middleware, options)
  if type(plugin_or_middleware) == "table" and plugin_or_middleware.__meteorite_plugin then
    plugin_or_middleware.apply(self, options or plugin_or_middleware.options or {})
    return self
  end
  self.middleware[#self.middleware + 1] = plugin_or_middleware
  return self
end

function App:_add_middleware(middleware)
  self.middleware[#self.middleware + 1] = middleware
  return middleware
end

function App:normalize(opts)
  return route.normalize_app(self, opts or {})
end

function M.app(opts)
  opts = opts or {}
  return setmetatable({
    name = opts.name or "meteorite-app",
    routes = {},
    middleware = {},
    options = opts,
    __meteorite_app = true,
  }, App)
end

function M.string(opts) return schema.scalar("string", opts) end
function M.slug(opts) return schema.scalar("slug", opts) end
function M.u64(opts) return schema.scalar("u64", opts) end
function M.i32(opts) return schema.scalar("i32", opts) end
function M.uuid(opts) return schema.scalar("uuid", opts) end
function M.hex(opts) return schema.scalar("hex", opts) end
function M.bool(opts) return schema.scalar("bool", opts) end

function M.pattern(name, source, opts)
  return patterns.define(name, source, opts)
end

M.patterns = patterns

function M.lua(module_ref)
  return { kind = "lua", module = module_ref }
end

function M.validation_error(message)
  return { kind = "validation_error", message = message }
end

function M.plugin(spec)
  spec = spec or {}
  spec.__meteorite_plugin = true
  return spec
end

function M._enum(value)
  return { __meteorite_enum = true, value = value }
end

return M
