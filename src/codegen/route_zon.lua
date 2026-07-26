--- Route/message ZON metadata serialization.

local helpers = require("codegen.helpers")
local schema_doc = require("codegen.schema_doc")

local route_zon = {}

function route_zon.schema_to_zon(item)
  if item.kind == "pattern" then
    return { name = item.name, kind = "pattern", pattern_id = item.pattern_id or item.id }
  end
  local out = { name = item.name, type = { __meteorite_enum = true, value = item.type or "string" } }
  if item.max_len then out.max_len = item.max_len end
  if item.exact_len then out.exact_len = item.exact_len end
  if item.optional then out.optional = true end
  if item.decode then out.decode = true end
  if item.pattern_id then out.pattern_id = item.pattern_id end
  return out
end

function route_zon.route_to_zon(route)
  local segments = {}
  for _, segment in ipairs(route.path.segments) do
    if segment.kind == "literal" then
      segments[#segments + 1] = { literal = segment.value }
    elseif segment.kind == "wildcard" then
      segments[#segments + 1] = { wildcard = true }
    else
      local param_schema = { name = segment.name, type = "string" }
      for _, item in ipairs(route.params) do if item.name == segment.name then param_schema = item end end
      local entry = { param = route_zon.schema_to_zon(param_schema) }
      if segment.catch_all then entry.catch_all = true end
      segments[#segments + 1] = entry
    end
  end
  local query = {}
  for _, item in ipairs(route.query) do query[#query + 1] = route_zon.schema_to_zon(item) end
  local validation = { headers = {}, cookies = {}, json_body = {}, form_body = {} }
  for domain, items in pairs(route.validation or {}) do
    validation[domain] = {}
    for _, item in ipairs(items) do validation[domain][#validation[domain] + 1] = route_zon.schema_to_zon(item) end
  end
  local handler
  if route.handler.kind == "zig" then handler = { zig_symbol = { id = route.handler.symbol, symbol = route.handler.import or route.handler.symbol } }
  elseif route.handler.kind == "zig_file" then handler = { zig_file = { id = route.handler.symbol, path = route.handler.path, decl = route.handler.decl or "handle" } }
  elseif route.handler.kind == "lua" then handler = { lua_file = { id = route.id, path = route.handler.path or route.handler.module } }
  elseif route.handler.kind == "file" then handler = { file = { artifact_path = route.handler.artifact_path, content_type = route.handler.content_type, content_length = route.handler.content_length, etag = route.handler.etag, cache_control = route.handler.cache_control, only_accept = route.handler.only_accept } }
  elseif route.handler.kind == "dir" then handler = { dir = { param = route.handler.param, cache_control = route.handler.cache_control, immutable = route.handler.immutable, manifest = route.handler.manifest or {} } }
  else
    local lifted = route.handler.lifted or { id = route.id }
    handler = {
      inline_lua = {
        id = lifted.id or route.id,
        chunk_path = lifted.runtime_path or lifted.chunk_path or "",
        source_file = lifted.source_file,
        source_line = lifted.source_line,
        source_column = lifted.source_column,
        nparams = lifted.nparams,
        arg_mode = lifted.arg_mode,
      },
    }
  end
  local capabilities = {}
  for _, ref in ipairs(route.capabilities or {}) do capabilities[#capabilities + 1] = { [ref.kind] = ref.name } end
  local runtime = {
    requires_lua = route.runtime.requires_lua,
    requires_http = route.runtime.requires_http,
    requires_auth = route.runtime.requires_auth,
    requires_zig_capability = route.runtime.requires_zig_capability,
    execution_class = { __meteorite_enum = true, value = route.runtime.execution_class },
  }
  local execution = {
    class = { __meteorite_enum = true, value = route.execution.class },
    may_block = route.execution.may_block,
    requires_lua = route.execution.requires_lua,
    requires_worker_pool = route.execution.requires_worker_pool,
  }
  return {
    id = route.id,
    canonical_id = route.canonical_id,
    http = route.http,
    message = route.message,
    method = helpers.method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    query = query,
    validation = validation,
    responses = schema_doc.response_schemas(route.responses),
    handler = handler,
    runtime = runtime,
    execution = execution,
    memory = route.memory,
    capabilities = capabilities,
    scope = helpers.normalized_scope(route.scope),
    source = route.source,
  }
end

return route_zon
