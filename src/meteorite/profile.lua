local profile = {}

local function parse_size(value, default)
  if value == nil then return default end
  if type(value) == "number" then return value end
  local n, unit = tostring(value):match("^(%d+)%s*([kKmMgG]?[bB]?)$")
  assert(n, "invalid memory size: " .. tostring(value))
  n = tonumber(n)
  unit = unit:lower()
  if unit == "kb" or unit == "k" then return n * 1024 end
  if unit == "mb" or unit == "m" then return n * 1024 * 1024 end
  if unit == "gb" or unit == "g" then return n * 1024 * 1024 * 1024 end
  return n
end

local function clone(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = clone(v) end
  return out
end

local builtin = {
  default = {
    name = "default",
    request = {
      request_arena = "256kb",
      max_uri_bytes = "8kb",
      max_path_bytes = "4kb",
      max_query_bytes = "4kb",
      max_query_pairs = 64,
      max_path_segments = 32,
      max_body = {
        get = 0,
        post = "1mb",
        put = "1mb",
        patch = "1mb",
        delete = 0,
      },
      max_response_bytes = "1mb",
      max_capability_response_bytes = "64kb",
      lua_heap = 0,
    },
    static = {
      max_patterns = 64,
      max_dfa_states_per_pattern = 256,
      max_dfa_bytes_per_pattern = "32kb",
      max_dfa_bytes_total = "128kb",
      max_graph_bytes = "256kb",
    },
    capabilities = {
      max_http_response_bytes = "64kb",
      max_auth_token_bytes = "8kb",
    },
  },
}

builtin.hybrid_dev = clone(builtin.default)
builtin.hybrid_dev.name = "hybrid_dev"
builtin.hybrid_dev.request.lua_heap = "2mb"
builtin.hybrid_dev.request.max_response_bytes = "1mb"

builtin.appliance_small = clone(builtin.default)
builtin.appliance_small.name = "appliance_small"
builtin.appliance_small.request.request_arena = "64kb"
builtin.appliance_small.request.max_uri_bytes = "4kb"
builtin.appliance_small.request.max_path_bytes = "2kb"
builtin.appliance_small.request.max_query_bytes = "2kb"
builtin.appliance_small.request.max_body.post = "128kb"
builtin.appliance_small.request.max_body.put = "128kb"
builtin.appliance_small.request.max_body.patch = "128kb"
builtin.appliance_small.request.max_response_bytes = "128kb"
builtin.appliance_small.request.max_capability_response_bytes = "32kb"
builtin.appliance_small.static.max_dfa_bytes_total = "32kb"
builtin.appliance_small.static.max_graph_bytes = "64kb"

local function deep_merge(base, override)
  local out = clone(base)
  for k, v in pairs(override or {}) do
    if type(v) == "table" and type(out[k]) == "table" then out[k] = deep_merge(out[k], v)
    else out[k] = clone(v) end
  end
  return out
end

local aliases = {
  default = "default",
  dev = "hybrid_dev",
  hybrid_dev = "hybrid_dev",
  appliance_small = "appliance_small",
  small = "appliance_small",
}

function profile.define(name_or_table, opts)
  if type(name_or_table) == "table" then
    return deep_merge(builtin.default, name_or_table)
  end
  local name = name_or_table or "default"
  local key = aliases[name] or name
  local base = builtin[key]
  assert(base, "unknown Meteorite profile: " .. tostring(name))
  local out = deep_merge(base, opts or {})
  out.name = name
  return out
end

local function lower_method(method)
  return tostring(method or "GET"):lower()
end

function profile.resolve(app_profile)
  return profile.define(app_profile or "default")
end

function profile.route_memory(resolved, method, route_memory)
  local req = resolved.request or {}
  local static = resolved.static or {}
  route_memory = route_memory or {}
  local body_defaults = req.max_body or {}
  local max_body_default = body_defaults[lower_method(method)] or 0
  local max_body = route_memory.max_body
  if max_body == nil then max_body = route_memory.body_max end
  local memory = {
    profile_name = resolved.name or "default",
    request_arena_bytes = parse_size(route_memory.request_arena, parse_size(req.request_arena, 256 * 1024)),
    max_body_bytes = parse_size(max_body, parse_size(max_body_default, 0)),
    max_uri_bytes = parse_size(route_memory.max_uri, parse_size(route_memory.max_uri_bytes, parse_size(req.max_uri_bytes, 8 * 1024))),
    max_path_bytes = parse_size(route_memory.max_path, parse_size(route_memory.max_path_bytes, parse_size(req.max_path_bytes, 4 * 1024))),
    max_query_bytes = parse_size(route_memory.max_query, parse_size(route_memory.max_query_bytes, parse_size(req.max_query_bytes, 4 * 1024))),
    max_query_pairs = route_memory.max_query_pairs or req.max_query_pairs or 64,
    max_path_segments = route_memory.max_path_segments or req.max_path_segments or 32,
    max_response_bytes = parse_size(route_memory.max_response, parse_size(route_memory.max_response_bytes, parse_size(req.max_response_bytes, 1024 * 1024))),
    max_capability_response_bytes = parse_size(route_memory.max_capability_response, parse_size(route_memory.max_capability_response_bytes, parse_size(req.max_capability_response_bytes, 64 * 1024))),
    lua_heap_bytes = parse_size(route_memory.lua_heap, parse_size(route_memory.lua_heap_bytes, parse_size(req.lua_heap, 0))),
    max_patterns = static.max_patterns or 64,
    max_dfa_states_per_pattern = static.max_dfa_states_per_pattern or 256,
    max_dfa_bytes_per_pattern = parse_size(static.max_dfa_bytes_per_pattern, 32 * 1024),
    max_dfa_bytes_total = parse_size(static.max_dfa_bytes_total, 128 * 1024),
    max_graph_bytes = parse_size(static.max_graph_bytes, 256 * 1024),
  }
  memory.estimated_peak_bytes = memory.request_arena_bytes + memory.max_body_bytes + memory.max_uri_bytes + memory.max_response_bytes + memory.max_capability_response_bytes + memory.lua_heap_bytes
  return memory
end

profile.parse_size = parse_size
profile.builtin = builtin
profile.profiles = {
  default = profile.define("default"),
  hybrid_dev = profile.define("hybrid_dev"),
  appliance_small = profile.define("appliance_small"),
}

return profile
