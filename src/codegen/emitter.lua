local zon = require("codegen.zon")
local lifter = require("codegen.lifter")
local static_compiler = require("codegen.static")
local partition_diff = require("codegen.partitions")
local helpers = require("codegen.helpers")
local report = require("codegen.report")
local handler_sync = require("codegen.handler_sync")
local graph_emit = require("codegen.graph_emit")
local openapi = require("codegen.openapi")
local fs = require("utils.fs")

local emitter = {}

-- Re-export for convenience
local write_file = helpers.write_file
local mkdir_p = fs.mkdir_p
local hash_zon = helpers.hash_zon
local hash_text = helpers.hash_text
local sorted_keys = helpers.sorted_keys
local method_enum = helpers.method_enum
local mode_enum = helpers.mode_enum
local zig_ident = helpers.zig_ident
local zig_string = helpers.zig_string
local normalized_scope = helpers.normalized_scope
local detect_lua_version = helpers.detect_lua_version
local project_root_from_output = helpers.project_root_from_output
local read_file = helpers.read_file
local file_exists = helpers.file_exists
local dirname = helpers.dirname
local path_join = helpers.path_join

local function json_quote(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local function emit_patterns_report(graph, output)
  local lines = { "[" }
  for i, pattern in ipairs(graph.patterns) do
    local r = pattern.report
    lines[#lines + 1] = "  {"
    lines[#lines + 1] = "    \"id\": " .. json_quote(pattern.id) .. ","
    lines[#lines + 1] = "    \"pattern\": " .. json_quote(r.pattern) .. ","
    lines[#lines + 1] = "    \"strategy\": " .. json_quote(r.strategy) .. ","
    lines[#lines + 1] = "    \"input_bound\": " .. r.input_bound .. ","
    lines[#lines + 1] = "    \"alphabet_classes\": " .. r.alphabet_classes .. ","
    lines[#lines + 1] = "    \"nfa_states\": " .. r.nfa_states .. ","
    lines[#lines + 1] = "    \"dfa_states\": " .. r.dfa_states .. ","
    lines[#lines + 1] = "    \"transition_table_bytes\": " .. r.transition_table_bytes .. ","
    lines[#lines + 1] = "    \"class_map_bytes\": " .. r.class_map_bytes .. ","
    lines[#lines + 1] = "    \"estimated_bytes\": " .. r.estimated_bytes .. ","
    lines[#lines + 1] = "    \"linear_time\": true,"
    lines[#lines + 1] = "    \"backtracking\": false"
    lines[#lines + 1] = "  }" .. (i < #graph.patterns and "," or "")
  end
  lines[#lines + 1] = "]\n"
  helpers.write_file(output .. "/patterns.graph.json", table.concat(lines, "\n"))
end

local function handler_descriptor(route)
  local handler = route.handler or {}
  if handler.kind == "zig" then
    return { kind = "zig", symbol = handler.symbol, import = handler.import or handler.symbol }
  elseif handler.kind == "zig_file" then
    return { kind = "zig_file", symbol = handler.symbol, path = handler.path, decl = handler.decl or "handle", source_hash = helpers.hash_text(read_file(handler.source_path or handler.path) or "") }
  elseif handler.kind == "lua" then
    local path = handler.path or handler.module
    return { kind = "lua", id = route.id, path = path }
  elseif handler.kind == "file" then
    return { kind = "file", id = route.id, source_hash = helpers.hash_text(read_file(handler.source_path or handler.path) or ""), artifact_path = handler.artifact_path, content_type = handler.content_type, content_length = handler.content_length, etag = handler.etag, cache_control = handler.cache_control, only_accept = handler.only_accept }
  elseif handler.kind == "dir" then
    return { kind = "dir", id = route.id, manifest_hash = helpers.hash_zon(handler.manifest or {}), param = handler.param, cache_control = handler.cache_control, immutable = handler.immutable, manifest = handler.manifest or {} }
  end
  local lifted = handler.lifted or {}
  local chunk_path = lifted.runtime_path or lifted.chunk_path or ""
  return {
    kind = "inline_lua",
    id = route.id,
    chunk_path = chunk_path,
    source_file = lifted.source_file or tostring(route.source and route.source.file or ""),
    source_line = lifted.source_line or (route.source and route.source.line) or 0,
    source_column = lifted.source_column or (route.source and route.source.column) or 1,
  }
end

local function route_shape_descriptor(route)
  local segments = {}
  for _, segment in ipairs(route.path.segments or {}) do
    if segment.kind == "literal" then
      segments[#segments + 1] = { kind = "literal", value = segment.value }
    elseif segment.kind == "wildcard" then
      segments[#segments + 1] = { kind = "wildcard" }
    else
      segments[#segments + 1] = { kind = "param", name = segment.name }
    end
  end
  local params = {}
  for _, param in ipairs(route.params or {}) do params[#params + 1] = report.schema_to_zon(param) end
  local query = {}
  for _, item in ipairs(route.query or {}) do query[#query + 1] = report.schema_to_zon(item) end
  local capabilities = {}
  for _, ref in ipairs(route.capabilities or {}) do capabilities[#capabilities + 1] = { kind = ref.kind, name = ref.name } end
  table.sort(capabilities, function(a, b) return (a.kind .. ":" .. a.name) < (b.kind .. ":" .. b.name) end)
  return {
    id = route.id,
    canonical_id = route.canonical_id,
    http = route.http,
    message = route.message,
    method = helpers.method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    params = params,
    query = query,
    memory = route.memory,
    execution = route.execution,
    runtime = route.runtime,
    capabilities = capabilities,
    scope = helpers.normalized_scope(route.scope),
  }
end

local function pattern_descriptor(pattern)
  return {
    id = pattern.id,
    report = pattern.report,
    class_count = pattern.class_count,
    class_map = pattern.class_map,
    dfa_accept = pattern.dfa_accept,
    dfa_transitions = pattern.dfa_transitions,
  }
end

local function capability_descriptor(capabilities)
  local out = {}
  for _, kind in ipairs(helpers.sorted_keys(capabilities or {})) do
    local names = {}
    for name, value in pairs(capabilities[kind] or {}) do names[#names + 1] = { name = name, value = value } end
    table.sort(names, function(a, b) return a.name < b.name end)
    out[#out + 1] = { kind = kind, names = names }
  end
  return out
end

local function plugin_handler_descriptor(plugin)
  local handler = plugin.handler or {}
  if handler.kind == "inline_lua" then
    local lifted = handler.lifted or {}
    return {
      kind = "inline_lua",
      id = plugin.id,
      chunk_path = lifted.runtime_path or lifted.chunk_path,
      source_file = lifted.source_file,
      source_line = lifted.source_line,
      source_column = lifted.source_column,
    }
  elseif handler.kind == "lua" then
    return { kind = "lua", id = plugin.id, path = handler.path or handler.module }
  elseif handler.kind == "zig" then
    return { kind = "zig", id = plugin.id, symbol = handler.symbol, import = handler.import or handler.symbol }
  end
  return { kind = "none", id = plugin.id }
end

local function plugin_descriptor(plugin)
  return {
    id = plugin.id,
    kind = plugin.kind,
    handler = plugin_handler_descriptor(plugin),
  }
end

local function backend_capabilities(backend)
  local is_native_ipc = backend == "ipc_unixsocket"
  return {
    http_headers = not is_native_ipc,
    cookies = not is_native_ipc,
    cors = not is_native_ipc,
    redirects = not is_native_ipc,
    ipc_metadata = is_native_ipc,
    peer_credentials = false,
    static_files = not is_native_ipc,
  }
end

local function backend_transport(backend)
  return (backend == "ipc_unixsocket" or backend == "ipc_unixsocket_http") and "unix" or "tcp"
end

local function backend_protocol(backend)
  return backend == "ipc_unixsocket" and "meteorite.ipc.v0" or "http/1.1"
end

local function build_partitions(graph, routes_text, graph_hash, mode, backend)
  local routes = {}
  local messages = {}
  local handlers = {}
  local lua_chunks = {}
  local static_assets = {}
  for _, route in ipairs(graph.routes or {}) do
    local shape = route_shape_descriptor(route)
    routes[#routes + 1] = { id = route.id, canonical_id = route.canonical_id, message = route.message and route.message.name, method = route.method, path = route.raw_path, hash = helpers.hash_zon(shape) }
  end
  for _, route in ipairs(graph.messages or {}) do
    local shape = route_shape_descriptor(route)
    messages[#messages + 1] = { id = route.id, canonical_id = route.canonical_id, message = route.message and route.message.name, hash = helpers.hash_zon(shape) }
  end
  for _, route in ipairs(graph.nodes or graph.routes or {}) do
    local handler = handler_descriptor(route)
    handlers[#handlers + 1] = { id = route.id, kind = handler.kind, hash = helpers.hash_zon(handler) }
    if handler.kind == "inline_lua" then
      local source_path = (route.handler.lifted or {}).chunk_path or handler.chunk_path
      lua_chunks[#lua_chunks + 1] = { id = route.id, path = handler.chunk_path, hash = helpers.hash_text(read_file(source_path) or "") }
    elseif handler.kind == "lua" then
      lua_chunks[#lua_chunks + 1] = { id = route.id, path = handler.path, hash = helpers.hash_text(read_file(handler.path) or "") }
    elseif handler.kind == "file" then
      static_assets[#static_assets + 1] = { id = route.id, kind = "file", path = handler.artifact_path or handler.path or route.raw_path, hash = helpers.hash_zon(handler) }
    elseif handler.kind == "dir" then
      static_assets[#static_assets + 1] = { id = route.id, kind = "dir", path = route.raw_path, hash = helpers.hash_zon(handler.manifest or {}) }
    end
  end
  local patterns = {}
  for _, pattern in ipairs(graph.patterns or {}) do
    patterns[#patterns + 1] = { id = pattern.id, hash = helpers.hash_zon(pattern_descriptor(pattern)) }
  end
  local runtime = {
    mode = helpers.mode_enum(mode),
    backend = backend,
    transport = backend_transport(backend),
    protocol = backend_protocol(backend),
    capabilities = backend_capabilities(backend),
    listen = graph.listen or { host = "127.0.0.1", port = 8080 },
    memory = graph.memory_report,
  }
  local route_graph = {}
  for _, route in ipairs(graph.routes or {}) do route_graph[#route_graph + 1] = route_shape_descriptor(route) end
  local message_graph = {}
  for _, route in ipairs(graph.messages or {}) do message_graph[#message_graph + 1] = route_shape_descriptor(route) end
  local handler_graph = {}
  for _, route in ipairs(graph.nodes or graph.routes or {}) do handler_graph[#handler_graph + 1] = handler_descriptor(route) end
  local pattern_graph = {}
  for _, pattern in ipairs(graph.patterns or {}) do pattern_graph[#pattern_graph + 1] = pattern_descriptor(pattern) end
  local lua_chunk_graph = {}
  for _, chunk in ipairs(lua_chunks) do lua_chunk_graph[#lua_chunk_graph + 1] = chunk end
  local plugin_graph = {}
  local plugin_list = {}
  for _, plugin in ipairs(graph.plugins or {}) do
    plugin_graph[#plugin_graph + 1] = plugin_descriptor(plugin)
    plugin_list[#plugin_list + 1] = { id = plugin.id, kind = plugin.kind, hash = helpers.hash_zon(plugin_descriptor(plugin)) }
    if plugin.handler and plugin.handler.kind == "inline_lua" then
      local lifted = plugin.handler.lifted
      lua_chunks[#lua_chunks + 1] = { id = plugin.id, path = lifted.runtime_path or lifted.chunk_path, hash = helpers.hash_text(read_file(lifted.chunk_path) or "") }
    end
  end
  return {
    format = "codegen.partitions.v0",
    graph_hash = graph_hash,
    route_graph_hash = helpers.hash_zon(route_graph),
    message_graph_hash = helpers.hash_zon(message_graph),
    handler_hash = helpers.hash_zon(handler_graph),
    pattern_hash = helpers.hash_zon(pattern_graph),
    lua_chunk_hash = helpers.hash_zon(lua_chunk_graph),
    plugin_hash = helpers.hash_zon(plugin_graph),
    capability_hash = helpers.hash_zon(capability_descriptor(graph.capabilities or {})),
    runtime_hash = helpers.hash_zon(runtime),
    routes_zon_hash = helpers.hash_text(routes_text),
    routes = routes,
    messages = messages,
    handlers = handlers,
    patterns = patterns,
    lua_chunks = lua_chunks,
    static_assets = static_assets,
    plugins = plugin_list,
    runtime = runtime,
  }
end

local function emit_partition_json(changed, output)
  local lines = { "[" }
  for i, item in ipairs(changed) do
    local has_hash = item.hash ~= nil
    local has_old_hash = item.old_hash ~= nil
    lines[#lines + 1] = "  {"
    lines[#lines + 1] = "    \"status\": " .. json_quote(item.status) .. ","
    lines[#lines + 1] = "    \"kind\": " .. json_quote(item.kind) .. ","
    lines[#lines + 1] = "    \"id\": " .. json_quote(item.id) .. ((has_old_hash or has_hash) and "," or "")
    if has_old_hash then lines[#lines + 1] = "    \"old_hash\": " .. json_quote(item.old_hash) .. (has_hash and "," or "") end
    if has_hash then lines[#lines + 1] = "    \"hash\": " .. json_quote(item.hash) end
    lines[#lines + 1] = "  }" .. (i < #changed and "," or "")
  end
  lines[#lines + 1] = "]\n"
  helpers.write_file(output .. "/partition-changes.json", table.concat(lines, "\n"))
end

function emitter.emit(app, opts)
  opts = opts or {}
  local output = opts.output or ".meteorite/graph/current"
  local mode = opts.mode or "dev"
  local backend = opts.backend or "fast_http"
  fs.mkdir_p(output)
  local graph = app:normalize({ mode = mode })
  graph = graph_emit.prepare_graph(graph, output, mode)
  local routes_zon = {}
  for _, route in ipairs(graph.routes) do routes_zon[#routes_zon + 1] = report.route_to_zon(route) end
  local messages_zon = {}
  for _, route in ipairs(graph.messages or {}) do messages_zon[#messages_zon + 1] = report.route_to_zon(route) end
  local routes_text = zon.encode(routes_zon)
  local messages_text = zon.encode(messages_zon)
  local schemas_text = zon.encode(report.schema_ir(graph))
  local openapi_plan_text = zon.encode(report.openapi_plan(graph))
  graph.memory_report = report.memory_report(graph, routes_text)
  local graph_hash = helpers.hash_text(routes_text .. "\n" .. messages_text)
  local partitions = build_partitions(graph, routes_text, graph_hash, mode, backend)
  local previous_partitions = read_file(output .. "/partition-hashes.tsv")
  local partition_changes = partition_diff.diagnostics(previous_partitions, partitions)
  helpers.write_file(output .. "/routes.zon", routes_text)
  helpers.write_file(output .. "/messages.zon", messages_text)
  helpers.write_file(output .. "/schemas.zon", schemas_text)
  helpers.write_file(output .. "/openapi-plan.zon", openapi_plan_text)
  local openapi_json = openapi.emit_json(graph, { title = graph.app and graph.app.name or "meteorite-app", version = "0.1.0" })
  helpers.write_file(output .. "/openapi.json", openapi_json)
  helpers.write_file(output .. "/manifest.zon", zon.encode({ format = "meteorite.graph.v0", meteorite_version = "0.1.0", graph_hash = graph_hash, mode = helpers.mode_enum(mode), partitions = { route_graph = partitions.route_graph_hash, message_graph = partitions.message_graph_hash, handlers = partitions.handler_hash, patterns = partitions.pattern_hash, lua_chunks = partitions.lua_chunk_hash, capabilities = partitions.capability_hash, runtime = partitions.runtime_hash } }))
  helpers.write_file(output .. "/partitions.zon", zon.encode(partitions))
  helpers.write_file(output .. "/partition-hashes.tsv", partition_diff.encode_tsv(partitions))
  emit_partition_json(partition_changes, output)
  helpers.write_file(output .. "/runtime.zon", zon.encode({ mode = helpers.mode_enum(mode), lua_runtime = mode ~= "release-static", backend = { __meteorite_enum = true, value = backend }, transport = backend_transport(backend), protocol = backend_protocol(backend), capabilities = backend_capabilities(backend), workers = { strategy = { __meteorite_enum = true, value = "auto" }, lua_state = { __meteorite_enum = true, value = "single_locked" } }, memory = graph.memory_report }))
  helpers.write_file(output .. "/capabilities.zon", zon.encode({ backend = backend, transport = backend_transport(backend), protocol = backend_protocol(backend), backend_capabilities = backend_capabilities(backend), methods = { "GET", "POST", "PUT", "PATCH", "DELETE" }, declared = graph.capabilities or {} }))
  helpers.write_file(output .. "/listen.zon", zon.encode(graph.listen or { host = "127.0.0.1", port = 8080 }))
    helpers.write_file(output .. "/listen_config.zig", "pub const listen_zon = @embedFile(\"listen.zon\");\n")
  helpers.write_file(output .. "/graph_hash.txt", graph_hash .. "\n")
  emit_patterns_report(graph, output)
  report.emit_build_report(graph, output, mode, backend)
  report.emit_luals_aids(graph, output)
  handler_sync.emit_ctx_zig(graph, output)
  handler_sync.emit_zig_aids(graph, output)
  if mode == "release-static" then handler_sync.assert_release_static_handlers(graph, output) end
  graph_emit.emit_bindings(graph, output)
  graph_emit.emit_graph_zig(graph, output)
  return { graph = graph, graph_hash = graph_hash, partitions = partitions, partition_changes = partition_changes, output = output }
end

return emitter
