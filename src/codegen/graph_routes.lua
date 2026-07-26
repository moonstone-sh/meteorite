--- Zig route module emission.

local helpers = require("codegen.helpers")
local fs = require("utils.fs")

local graph_routes = {}

local function graph_nodes(graph)
  return graph.nodes or graph.routes or {}
end

local function hook_phase_zig(phase)
  if phase == "error" then return '.@"error"' end
  return "." .. phase
end

function graph_routes.route_module_name(route)
  return "route_" .. helpers.zig_ident(route.method .. "_" .. route.raw_path .. "_" .. route.id)
end

function graph_routes.param_pattern_zig(param)
  local pattern = "null"
  local kind = param.type or param.kind or "string"
  if param.kind == "pattern" then
    pattern = "." .. helpers.zig_ident(param.id)
    kind = "pattern"
  elseif param.pattern_id then
    pattern = "." .. helpers.zig_ident(param.pattern_id)
  end
  return kind, pattern
end

function graph_routes.route_handler_zig(route)
  local lifted = route.handler.lifted or {}
  local handler = ".{ .inline_lua = .{ .id = " .. helpers.zig_string(route.id) .. ", .chunk_path = " .. helpers.zig_string(lifted.runtime_path or lifted.chunk_path or "") .. ", .source_file = " .. helpers.zig_string(lifted.source_file or tostring(route.source.file)) .. ", .source_line = " .. tostring(lifted.source_line or route.source.line or 0) .. ", .source_column = " .. tostring(lifted.source_column or route.source.column or 1) .. ", .nparams = " .. tostring(lifted.nparams or 1) .. ", .arg_mode = ." .. tostring(lifted.arg_mode or "request_table") .. " } }"
  if route.handler.kind == "zig" then handler = ".{ .zig_symbol = .{ .id = ." .. route.handler.symbol .. ", .symbol = " .. helpers.zig_string(route.handler.import or route.handler.symbol) .. " } }" end
  if route.handler.kind == "zig_file" then handler = ".{ .zig_file = .{ .id = " .. helpers.zig_string(route.handler.symbol) .. ", .path = " .. helpers.zig_string(route.handler.path) .. ", .decl = " .. helpers.zig_string(route.handler.decl or "handle") .. " } }" end
  if route.handler.kind == "lua" then handler = ".{ .lua_file = .{ .id = " .. helpers.zig_string(route.id) .. ", .path = " .. helpers.zig_string(route.handler.path or route.handler.module) .. " } }" end
  if route.handler.kind == "file" then
    handler = ".{ .file = .{ .artifact_path = " .. helpers.zig_string(route.handler.artifact_path or route.handler.path) .. ", .content_type = " .. helpers.zig_string(route.handler.content_type or "application/octet-stream") .. ", .content_length = " .. tostring(route.handler.content_length or 0) .. ", .etag = " .. helpers.zig_string(route.handler.etag or "") .. ", .cache_control = " .. helpers.zig_string(route.handler.cache_control or route.handler.cache or "no-cache") .. ", .only_accept = " .. (route.handler.only_accept and helpers.zig_string(route.handler.only_accept) or "null") .. " } }"
  end
  if route.handler.kind == "dir" then
    handler = ".{ .dir = .{ .mount_root = " .. helpers.zig_string("") .. ", .param_name = " .. helpers.zig_string(route.handler.param) .. ", .manifest = &data.static_assets, .cache_control = " .. helpers.zig_string(route.handler.cache_control or route.handler.cache or "no-cache") .. ", .immutable = " .. tostring(route.handler.immutable == true) .. " } }"
  end
  return handler
end

function graph_routes.route_runtime_zig(route)
  return ".{ .requires_lua = " .. tostring(route.runtime.requires_lua) .. ", .requires_http = " .. tostring(route.runtime.requires_http) .. ", .requires_auth = " .. tostring(route.runtime.requires_auth) .. ", .requires_zig_capability = " .. tostring(route.runtime.requires_zig_capability) .. ", .execution_class = ." .. route.runtime.execution_class .. " }"
end

function graph_routes.route_execution_zig(route)
  return ".{ .class = ." .. route.execution.class .. ", .may_block = " .. tostring(route.execution.may_block) .. ", .requires_lua = " .. tostring(route.execution.requires_lua) .. ", .requires_worker_pool = " .. tostring(route.execution.requires_worker_pool) .. " }"
end

function graph_routes.route_memory_zig(route)
  local memory = route.memory
  return ".{ .profile_name = " .. helpers.zig_string(memory.profile_name) .. ", .request_arena_bytes = " .. memory.request_arena_bytes .. ", .max_body_bytes = " .. memory.max_body_bytes .. ", .max_uri_bytes = " .. memory.max_uri_bytes .. ", .max_path_bytes = " .. memory.max_path_bytes .. ", .max_query_bytes = " .. memory.max_query_bytes .. ", .max_query_pairs = " .. memory.max_query_pairs .. ", .max_path_segments = " .. memory.max_path_segments .. ", .max_response_bytes = " .. memory.max_response_bytes .. ", .max_capability_response_bytes = " .. memory.max_capability_response_bytes .. ", .lua_heap_bytes = " .. memory.lua_heap_bytes .. ", .estimated_peak_bytes = " .. memory.estimated_peak_bytes .. " }"
end

function graph_routes.route_scope_zig(scope)
  local normalized = helpers.normalized_scope(scope)
  return ".{ .id = " .. helpers.zig_string(normalized.id) .. ", .parent = " .. helpers.zig_string(normalized.parent) .. ", .path_prefix = " .. helpers.zig_string(normalized.path_prefix) .. ", .chain = &data.scope_chain, .plugins = &data.scope_plugins, .context = &data.scope_context }"
end


function graph_routes.plugin_handler_zig(plugin)
  local handler = plugin.handler or {}
  if handler.kind == "inline_lua" then
    return ".{ .inline_lua = .{ .id = " .. helpers.zig_string(plugin.id) .. ", .chunk_path = " .. helpers.zig_string((handler.lifted or {}).runtime_path or (handler.lifted or {}).chunk_path or "") .. ", .source_file = " .. helpers.zig_string((handler.lifted or {}).source_file or "") .. ", .source_line = " .. tostring((handler.lifted or {}).source_line or 0) .. ", .source_column = " .. tostring((handler.lifted or {}).source_column or 1) .. ", .nparams = " .. tostring((handler.lifted or {}).nparams or 1) .. ", .arg_mode = ." .. tostring((handler.lifted or {}).arg_mode or "request_table") .. " } }"
  elseif handler.kind == "lua" then
    return ".{ .lua_file = .{ .id = " .. helpers.zig_string(plugin.id) .. ", .path = " .. helpers.zig_string(handler.path or handler.module) .. " } }"
  elseif handler.kind == "zig" then
    return ".{ .zig_symbol = .{ .id = ." .. handler.symbol .. ", .symbol = " .. helpers.zig_string(handler.import or handler.symbol) .. " } }"
  end
  return ".none"
end

function graph_routes.static_asset_zig(asset)
  return ".{ .request_path = " .. helpers.zig_string(asset.request_path or "")
    .. ", .artifact_path = " .. helpers.zig_string(asset.artifact_path or "")
    .. ", .content_type = " .. helpers.zig_string(asset.content_type or "application/octet-stream")
    .. ", .content_length = " .. tostring(asset.content_length or 0)
    .. ", .etag = " .. helpers.zig_string(asset.etag or "")
    .. ", .cache_control = " .. helpers.zig_string(asset.cache_control or "no-cache")
    .. ", .compressed_br_path = " .. (asset.compressed_br_path and helpers.zig_string(asset.compressed_br_path) or "null")
    .. ", .compressed_br_length = " .. tostring(asset.compressed_br_length or 0)
    .. ", .compressed_br_etag = " .. (asset.compressed_br_etag and helpers.zig_string(asset.compressed_br_etag) or "null")
    .. ", .compressed_gzip_path = " .. (asset.compressed_gzip_path and helpers.zig_string(asset.compressed_gzip_path) or "null")
    .. ", .compressed_gzip_length = " .. tostring(asset.compressed_gzip_length or 0)
    .. ", .compressed_gzip_etag = " .. (asset.compressed_gzip_etag and helpers.zig_string(asset.compressed_gzip_etag) or "null")
    .. " }"
end

function graph_routes.route_module_content(route)
  local lines = {
    "pub fn route(comptime graph: type) graph.Route {",
    "    const data = struct {",
    "        const segments = [_]graph.Segment{",
  }
  local function emit_param_specs(name, specs)
    lines[#lines + 1] = "        const " .. name .. " = [_]graph.ParamSpec{"
    for _, spec in ipairs(specs or {}) do
      local kind, pattern = graph_routes.param_pattern_zig(spec)
      lines[#lines + 1] = "            .{ .name = " .. helpers.zig_string(spec.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(spec.max_len or 0) .. ", .exact_len = " .. tostring(spec.exact_len or 0) .. ", .optional = " .. tostring(spec.optional == true) .. ", .pattern = " .. pattern .. " },"
    end
    lines[#lines + 1] = "        };"
  end
  for _, segment in ipairs(route.path.segments) do
    if segment.kind == "literal" then lines[#lines + 1] = "            .{ .literal = " .. helpers.zig_string(segment.value) .. " },"
    elseif segment.kind == "wildcard" then lines[#lines + 1] = "            .{ .wildcard = {} },"
    elseif segment.catch_all then lines[#lines + 1] = "            .{ .catch_all_param = " .. helpers.zig_string(segment.name) .. " },"
    else lines[#lines + 1] = "            .{ .param = " .. helpers.zig_string(segment.name) .. " }," end
  end
  lines[#lines + 1] = "        };"
  emit_param_specs("query", route.query)
  emit_param_specs("params", route.params)
  local validation = route.validation or {}
  emit_param_specs("validation_headers", validation.headers)
  emit_param_specs("validation_cookies", validation.cookies)
  emit_param_specs("validation_json_body", validation.json_body)
  emit_param_specs("validation_form_body", validation.form_body)
  lines[#lines + 1] = "        const capabilities = [_]graph.CapabilityRef{"
  for _, ref in ipairs(route.capabilities or {}) do
    lines[#lines + 1] = "            .{ ." .. ref.kind .. " = " .. helpers.zig_string(ref.name) .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const message_params = [_][]const u8{"
  for _, name in ipairs((route.message and route.message.params) or {}) do
    lines[#lines + 1] = "            " .. helpers.zig_string(name) .. ","
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const static_assets = [_]graph.StaticAsset{"
  for _, asset in ipairs((route.handler and route.handler.manifest) or {}) do
    lines[#lines + 1] = "            " .. graph_routes.static_asset_zig(asset) .. ","
  end
  lines[#lines + 1] = "        };"
  local scope = helpers.normalized_scope(route.scope)
  lines[#lines + 1] = "        const scope_chain = [_]graph.ScopeRef{"
  for _, item in ipairs(scope.chain) do
    lines[#lines + 1] = "            .{ .id = " .. helpers.zig_string(item.id) .. ", .path_prefix = " .. helpers.zig_string(item.path_prefix) .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const scope_plugins = [_][]const u8{"
  for _, plugin in ipairs(scope.plugins) do
    lines[#lines + 1] = "            " .. helpers.zig_string(plugin) .. ","
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const scope_context = [_]graph.ScopeContextRef{"
  for _, item in ipairs(scope.context) do
    lines[#lines + 1] = "            .{ .key = " .. helpers.zig_string(item.key) .. ", .value = " .. helpers.zig_string(item.value) .. " },"
  end
  lines[#lines + 1] = "        };"
  -- Pipeline stages (inside the data struct)
  if route.pipeline and #route.pipeline > 0 then
    lines[#lines + 1] = "        const pipeline = [_]graph.PipelineStage{"
    for _, stage in ipairs(route.pipeline) do
      local stage_fields = { '.id = ' .. helpers.zig_string(stage.id or "") }
      stage_fields[#stage_fields + 1] = '.kind = .' .. (stage.kind or "handle")
      if stage.phase then stage_fields[#stage_fields + 1] = '.phase = ' .. hook_phase_zig(stage.phase) end
      stage_fields[#stage_fields + 1] = '.strat = .' .. (stage.strat or "inline_lua")
      if stage.path then stage_fields[#stage_fields + 1] = '.path = ' .. helpers.zig_string(stage.path) end
      if stage.symbol then stage_fields[#stage_fields + 1] = '.symbol = ' .. helpers.zig_string(stage.symbol) end
      stage_fields[#stage_fields + 1] = '.may_short_circuit = ' .. tostring(stage.may_short_circuit ~= false)
      if stage.owner then stage_fields[#stage_fields + 1] = '.owner = ' .. helpers.zig_string(stage.owner) end
      lines[#lines + 1] = "            .{ " .. table.concat(stage_fields, ", ") .. " },"
    end
    lines[#lines + 1] = "        };"
  else
    lines[#lines + 1] = "        const pipeline = [_]graph.PipelineStage{};"
  end
  lines[#lines + 1] = "    };"
  local scope_zig = graph_routes.route_scope_zig(route.scope)
    local pipeline_zig = ".{}"
  if route.pipeline and #route.pipeline > 0 then
    local stage_lines = { ".{" }
    for _, stage in ipairs(route.pipeline) do
      local stage_fields = {
        ".id = " .. helpers.zig_string(stage.id or ""),
        ".kind = ." .. (stage.kind or "handle"),
        ".strat = ." .. (stage.strat or "inline_lua"),
        ".may_short_circuit = " .. tostring(stage.may_short_circuit ~= false),
      }
      if stage.phase then stage_fields[#stage_fields + 1] = ".phase = " .. hook_phase_zig(stage.phase) end
      if stage.path then stage_fields[#stage_fields + 1] = ".path = " .. helpers.zig_string(stage.path) end
      if stage.symbol then stage_fields[#stage_fields + 1] = ".symbol = " .. helpers.zig_string(stage.symbol) end
      if stage.owner then stage_fields[#stage_fields + 1] = ".owner = " .. helpers.zig_string(stage.owner) end
      stage_lines[#stage_lines + 1] = "        .{ " .. table.concat(stage_fields, ", ") .. " },"
    end
    stage_lines[#stage_lines + 1] = "    }"
    pipeline_zig = table.concat(stage_lines, "\n")
  end
  local message = route.message or { name = route.id, pattern = route.id, slash_alias = route.id, source = "inferred" }
  lines[#lines + 1] = "    return .{ .id = " .. helpers.zig_string(route.id) .. ", .canonical_id = " .. helpers.zig_string(route.canonical_id or ("route." .. tostring(message.name))) .. ", .method = ." .. route.method .. ", .raw_path = " .. helpers.zig_string(route.raw_path) .. ", .http = .{ .method = ." .. route.method .. ", .path = " .. helpers.zig_string(route.raw_path) .. " }, .message = .{ .name = " .. helpers.zig_string(message.name) .. ", .pattern = " .. helpers.zig_string(message.pattern or message.name) .. ", .slash_alias = " .. helpers.zig_string(message.slash_alias or tostring(message.name):gsub("%.", "/")) .. ", .source = " .. helpers.zig_string(message.source or "inferred") .. ", .params = &data.message_params }, .path = &data.segments, .params = &data.params, .query = &data.query, .validation = .{ .headers = &data.validation_headers, .cookies = &data.validation_cookies, .json_body = &data.validation_json_body, .form_body = &data.validation_form_body }, .memory = " .. graph_routes.route_memory_zig(route) .. ", .max_body_bytes = " .. route.memory.max_body_bytes .. ", .request_arena_bytes = " .. route.memory.request_arena_bytes .. ", .handler = " .. graph_routes.route_handler_zig(route) .. ", .pipeline = &data.pipeline, .runtime = " .. graph_routes.route_runtime_zig(route) .. ", .execution = " .. graph_routes.route_execution_zig(route) .. ", .capabilities = &data.capabilities, .scope = " .. scope_zig .. " };"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

--- Emit individual route/*.zig modules.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_routes.emit_route_modules(graph, output)
  local dir = output .. "/routes"
  fs.mkdir_p(dir)
  for _, route in ipairs(graph_nodes(graph)) do
    helpers.write_file(dir .. "/" .. graph_routes.route_module_name(route) .. ".zig", graph_routes.route_module_content(route))
  end
end

return graph_routes
