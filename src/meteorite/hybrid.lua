local json = require("meteorite.json")

local hybrid = {}
local app_stores = setmetatable({}, { __mode = "k" })

local function app_store(app)
  local store = app_stores[app]
  if not store then
    store = { capabilities = {} }
    app_stores[app] = store
  end
  return store
end

local function split_path(path)
  if path == "/" then return {} end
  local out = {}
  for part in tostring(path):gmatch("[^/]+") do out[#out + 1] = part end
  return out
end

local function split_target(target)
  local path, query = tostring(target):match("^([^?]*)%??(.*)$")
  if path == "" then path = "/" end
  return path, query or ""
end

local function parse_query(raw)
  local out = {}
  for part in tostring(raw):gmatch("[^&]+") do
    local key, value = part:match("^([^=]*)=(.*)$")
    if not key then key, value = part, "" end
    if key ~= "" and out[key] == nil then out[key] = value end
  end
  return out
end

local function pattern_match(pattern, value)
  if not pattern or not pattern.parsed then return true end
  if #value < pattern.parsed.min or #value > pattern.parsed.max then return false end
  for i = 1, #value do
    local byte = value:byte(i)
    local ok = false
    for _, range in ipairs(pattern.parsed.ranges) do
      if byte >= range[1] and byte <= range[2] then ok = true; break end
    end
    if not ok then return false end
  end
  return true
end

local function validate_schema(schema, value)
  local kind = schema.kind or schema.type or "string"
  if schema.max_len and #value > schema.max_len then return false end
  if schema.exact_len and #value ~= schema.exact_len then return false end
  if schema.pattern and not pattern_match(schema.pattern, value) then return false end
  if kind == "pattern" then return pattern_match(schema, value) end
  if kind == "u64" then return value:match("^%d+$") ~= nil end
  if kind == "i32" then return value:match("^-?%d+$") ~= nil end
  if kind == "slug" then return value:match("^[a-z0-9_-]+$") ~= nil end
  if kind == "hex" then return value:match("^[0-9a-fA-F]+$") ~= nil end
  if kind == "uuid" then return value:match("^[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+$") ~= nil end
  return true
end

local function convert_schema(schema, value)
  local kind = schema.kind or schema.type or "string"
  if kind == "u64" or kind == "i32" then return tonumber(value) end
  if kind == "bool" then return value == "true" or value == "1" end
  return value
end

local function match_query(route, query_values)
  local out = {}
  for _, schema in ipairs(route.query or {}) do
    local value = query_values[schema.name]
    if value == nil then
      if not schema.optional then return nil end
      out[schema.name] = nil
    else
      if not validate_schema(schema, value) then return nil end
      out[schema.name] = convert_schema(schema, value)
    end
  end
  return out
end

local function match_route(route, method, path)
  if route.method ~= method then return nil, "method" end
  local parts = split_path(path)
  local segments = route.path.segments
  if #parts ~= #segments then return nil end
  local params = {}
  local schemas = {}
  for _, schema in ipairs(route.params or {}) do schemas[schema.name] = schema end
  for i, segment in ipairs(segments) do
    local value = parts[i]
    if segment.kind == "literal" then
      if segment.value ~= value then return nil end
    else
      local schema = schemas[segment.name] or { type = "string" }
      if not validate_schema(schema, value) then return nil end
      params[segment.name] = value
    end
  end
  return params
end

local Context = {}
Context.__index = Context

function Context:text(status_or_body, body)
  local status, response_body = 200, status_or_body
  if type(status_or_body) == "number" then status, response_body = status_or_body, body end
  self.response = { status = status, content_type = "text/plain; charset=utf-8", body = tostring(response_body or "") }
  return self.response
end

function Context:json(status_or_value, value)
  local status, body = 200, status_or_value
  if type(status_or_value) == "number" then status, body = status_or_value, value end
  self.response = { status = status, content_type = "application/json", body = json.encode(body) }
  return self.response
end

function Context:bytes(status, content_type, body)
  if body == nil then body, content_type, status = content_type, "application/octet-stream", 200 end
  self.response = { status = status, content_type = content_type, body = body or "" }
  return self.response
end

function Context:body()
  return self.request.body or ""
end

function Context:header(name)
  local headers = self.request.headers or {}
  return headers[name]
end

function Context:set(key, value)
  self.state[key] = value
  return value
end

function Context:get(key)
  return self.state[key]
end

function Context:cache(name)
  name = name or "default"
  local cache = self.worker_cache[name]
  if not cache then
    cache = {}
    self.worker_cache[name] = cache
  end
  return cache
end

---@class MeteoriteHttpResponse
---@field status integer
---@field headers table<string, string>
---@field body any

---@class MeteoriteHttpClient
---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
local HttpClient = {}
HttpClient.__index = HttpClient

local http_client = require("meteorite.http_client")

local function http_request(method, base_url, path, opts)
  return http_client.request(method, base_url, path, opts)
end

function HttpClient:get(path, opts)
  return http_request("GET", self.base_url, path, opts)
end

function HttpClient:post(path, opts)
  return http_request("POST", self.base_url, path, opts)
end

function HttpClient:put(path, opts)
  return http_request("PUT", self.base_url, path, opts)
end

function HttpClient:patch(path, opts)
  return http_request("PATCH", self.base_url, path, opts)
end

function HttpClient:delete(path, opts)
  return http_request("DELETE", self.base_url, path, opts)
end

function Context:http(name)
  local capability = assert(self.capabilities.http and self.capabilities.http[name], "undeclared http capability: " .. tostring(name))
  local base_url = capability.base_url
  assert(type(base_url) == "string", "http capability missing base_url")
  return setmetatable({ base_url = base_url, requests = self.http_requests }, HttpClient)
end

local Auth = {}
Auth.__index = Auth

function Auth:refresh()
  self.refreshing = true
  self.refresh_count = (self.refresh_count or 0) + 1
  local audience = self.spec.audience or self.name
  self.token = "demo-token-for-" .. tostring(audience)
  self.expires_at = os.time() + 3600
  self.last_error = nil
  self.refreshing = false
  return self.token
end

function Auth:bearer()
  local now = os.time()
  local refresh_before = self.spec.refresh_before_seconds or 30
  if not self.token or (self.expires_at or 0) - refresh_before <= now then
    if self.refreshing then
      return self.token or ""
    end
    self:refresh()
  end
  return "Bearer " .. self.token
end

function Auth:authorization()
  return self:bearer()
end

function Auth:headers()
  return { authorization = self:authorization() }
end

function Context:auth(name)
  local spec = assert(self.capabilities.auth and self.capabilities.auth[name], "undeclared auth capability: " .. tostring(name))
  local key = "auth." .. tostring(name)
  local auth = self.capability_store[key]
  if not auth then
    auth = setmetatable({ name = name, spec = spec, token = nil, expires_at = 0, refreshing = false, refresh_count = 0 }, Auth)
    self.capability_store[key] = auth
  end
  return auth
end

local default_zig = {
  data_cruncher = {
    device_name = function(device_id) return "device:" .. tostring(device_id) end,
  },
}

function Context:zig(name)
  assert(self.capabilities.zig and self.capabilities.zig[name], "undeclared zig capability: " .. tostring(name))
  return (self.zig_helpers and self.zig_helpers[name]) or default_zig[name] or error("missing zig helper: " .. tostring(name))
end

function Context:scope(name)
  return self.scope[name]
end

local function new_context(opts)
  local params = opts.params or {}
  return setmetatable({
    request = opts.request,
    params = params,
    query = opts.query or {},
    state = {},
    scope = opts.scope or {},
    worker_cache = opts.worker_cache or {},
    capability_store = opts.capability_store or {},
    capabilities = opts.capabilities or {},
    zig_helpers = opts.zig_helpers,
    http_requests = {},
  }, Context)
end

local function build_plugin_map(plugins)
  local map = {}
  for _, plugin in ipairs(plugins or {}) do map[plugin.id] = plugin end
  return map
end

local function execute_scope_plugins(route, ctx, plugin_map)
  for _, plugin_ref in ipairs(route.scope.plugins or {}) do
    local plugin = type(plugin_ref) == "table" and plugin_ref.__meteorite_plugin and plugin_ref or plugin_map[plugin_ref]
    if plugin and type(plugin.execute) == "function" then
      local result = plugin.execute(ctx)
      if result then
        if type(result) == "string" then
          return { status = 200, content_type = "text/plain", body = result, http_requests = ctx.http_requests, state = ctx.state }
        end
        return {
          status = result.status or 200,
          content_type = result.content_type or "text/plain",
          body = result.body or "",
          http_requests = ctx.http_requests,
          state = ctx.state,
        }
      end
    end
  end
  return nil
end

function hybrid.invoke(app, request, opts)
  opts = opts or {}
  local store = opts.store or app_store(app)
  local graph = app:normalize({ mode = opts.mode or "dev" })
  local plugin_map = build_plugin_map(graph.plugins)
  local method = request.method or "GET"
  local path, raw_query = split_target(request.path or "/")
  local query_values = parse_query(raw_query)
  local path_matched = false
  for _, route in ipairs(graph.routes) do
    local params = match_route(route, method, path)
    if params then
      local query = match_query(route, query_values)
      if not query then return { status = 404, content_type = "text/plain", body = "not found" } end
      local ctx = new_context({ request = request, params = params, query = query, scope = route.scope.context or {}, capabilities = graph.capabilities, zig_helpers = opts.zig_helpers, worker_cache = app.cache, capability_store = store.capabilities })
      local plugin_response = execute_scope_plugins(route, ctx, plugin_map)
      if plugin_response then return plugin_response end
      if route.handler.kind == "inline_lua" then
        local response = route.handler.value(ctx) or ctx.response or ctx:text(204, "")
        response.http_requests = ctx.http_requests
        response.state = ctx.state
        return response
      elseif route.handler.kind == "lua" then
        local handler = require(route.handler.module)
        local response = handler(ctx) or ctx.response or ctx:text(204, "")
        response.http_requests = ctx.http_requests
        response.state = ctx.state
        return response
      end
      return { status = 501, content_type = "text/plain", body = "handler requires Zig runtime" }
    end
    if match_route(route, route.method, path) then path_matched = true end
  end
  if path_matched then return { status = 405, content_type = "text/plain", body = "method not allowed" } end
  return { status = 404, content_type = "text/plain", body = "not found" }
end

return hybrid
