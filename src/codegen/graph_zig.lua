--- Top-level graph.zig assembly.

local helpers = require("codegen.helpers")
local graph_patterns = require("codegen.graph_patterns")
local graph_capabilities = require("codegen.graph_capabilities")
local graph_routes = require("codegen.graph_routes")

local graph_zig = {}

local function graph_nodes(graph)
  return graph.nodes or graph.routes or {}
end

--- Emit the main graph.zig file.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_zig.emit(graph, output)
  local max_arena = 0
  local max_uri, max_path, max_query, max_query_pairs, max_path_segments = 0, 0, 0, 0, 0
  for _, route in ipairs(graph_nodes(graph)) do
    local memory = route.memory
    if memory.request_arena_bytes > max_arena then max_arena = memory.request_arena_bytes end
    if memory.max_uri_bytes > max_uri then max_uri = memory.max_uri_bytes end
    if memory.max_path_bytes > max_path then max_path = memory.max_path_bytes end
    if memory.max_query_bytes > max_query then max_query = memory.max_query_bytes end
    if memory.max_query_pairs > max_query_pairs then max_query_pairs = memory.max_query_pairs end
    if memory.max_path_segments > max_path_segments then max_path_segments = memory.max_path_segments end
  end
  local lines = {
    "pub const bindings = @import(\"graph_bindings.zig\");",
    "const std = @import(\"std\");",
    "",
    "pub const ctx = @import(\"meteorite_ctx\").ctx;",
    "",
    "pub const max_request_arena_bytes = " .. tostring(max_arena) .. ";",
    "pub const max_uri_bytes = " .. tostring(max_uri) .. ";",
    "pub const max_path_bytes = " .. tostring(max_path) .. ";",
    "pub const max_query_bytes = " .. tostring(max_query) .. ";",
    "pub const max_query_pairs = " .. tostring(max_query_pairs) .. ";",
    "pub const max_path_segments = " .. tostring(max_path_segments) .. ";",
    "pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, OTHER, ALL };",
    "pub const Segment = union(enum) { literal: []const u8, param: []const u8, catch_all_param: []const u8, wildcard };",
    "pub const ZigSymbolHandler = struct { id: bindings.HandlerId, symbol: []const u8 };",
    "pub const ZigFileHandler = struct { id: []const u8, path: []const u8, decl: []const u8 = \"handle\" };",
    "pub const LuaFileHandler = struct { id: []const u8, path: []const u8 };",
    "pub const LuaArgMode = enum { request_table, lazy_context, direct_params, no_args };",
    "pub const InlineLuaHandler = struct { id: []const u8, chunk_path: []const u8, source_file: []const u8, source_line: u32, source_column: u32, nparams: u8 = 1, arg_mode: LuaArgMode = .request_table };",
    "pub const FileHandler = struct { artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, only_accept: ?[]const u8 = null };",
    "pub const StaticAsset = struct { request_path: []const u8, artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, compressed_br_path: ?[]const u8 = null, compressed_br_length: u64 = 0, compressed_br_etag: ?[]const u8 = null, compressed_gzip_path: ?[]const u8 = null, compressed_gzip_length: u64 = 0, compressed_gzip_etag: ?[]const u8 = null };",
    "pub const DirHandler = struct { mount_root: []const u8, param_name: []const u8, manifest: []const StaticAsset, cache_control: []const u8, immutable: bool = false };",
    "pub const Handler = union(enum) { zig_symbol: ZigSymbolHandler, zig_file: ZigFileHandler, lua_file: LuaFileHandler, inline_lua: InlineLuaHandler, file: FileHandler, dir: DirHandler };",
    "pub const StageKind = enum { transform, handle, hook };",
    "pub const HookPhase = enum { pre_tree, post_match, pre_handler, post_handler, observe, @\"error\" };",
    "pub const StageStrat = enum { inline_lua, lua, zig, rust };",
    "pub const PipelineStage = struct { id: []const u8 = \"\", kind: StageKind = .handle, phase: HookPhase = .pre_handler, strat: StageStrat = .inline_lua, path: []const u8 = \"\", symbol: []const u8 = \"\", may_short_circuit: bool = true, owner: []const u8 = \"\" };",
    "pub const ExecutionClass = enum { default, lua, blocking_io, cpu };",
    "pub const RouteRuntime = struct { requires_lua: bool = false, requires_http: bool = false, requires_auth: bool = false, requires_zig_capability: bool = false, execution_class: ExecutionClass = .default };",
    "pub const RouteExecution = struct { class: ExecutionClass = .default, may_block: bool = false, requires_lua: bool = false, requires_worker_pool: bool = false };",
    "pub const CapabilityRef = union(enum) { http: []const u8, auth: []const u8, zig: []const u8, lua: []const u8, worker: []const u8 };",
    "pub const WorkerStrategy = enum { auto, single_thread, io_plus_workers, per_core, pinned_appliance };",
    "pub const LuaStateStrategy = enum { single_locked, per_worker };",
    "pub const ThreadCount = union(enum) { auto, fixed: u16 };",
    "pub const RuntimeWorkers = struct { strategy: WorkerStrategy = .auto, io_threads: ThreadCount = .auto, worker_threads: ThreadCount = .auto, lua_state: LuaStateStrategy = .single_locked };",
    "pub const runtime_workers = RuntimeWorkers{};",
    "pub const RouteMemory = struct { profile_name: []const u8, request_arena_bytes: usize, max_body_bytes: usize, max_uri_bytes: usize, max_path_bytes: usize, max_query_bytes: usize, max_query_pairs: usize, max_path_segments: usize, max_response_bytes: usize, max_capability_response_bytes: usize, lua_heap_bytes: usize, estimated_peak_bytes: usize };",
    "pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, email, token, bool, pattern };",
    "pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };",
    "pub const ValidationSpec = struct { headers: []const ParamSpec = &.{}, cookies: []const ParamSpec = &.{}, json_body: []const ParamSpec = &.{}, form_body: []const ParamSpec = &.{} };",
    "pub const ScopeRef = struct { id: []const u8, path_prefix: []const u8 };",
    "pub const ScopeContextRef = struct { key: []const u8, value: []const u8 };",
    "pub const RouteScope = struct { id: []const u8 = \"root\", parent: []const u8 = \"\", path_prefix: []const u8 = \"\", chain: []const ScopeRef = &.{}, plugins: []const []const u8 = &.{}, context: []const ScopeContextRef = &.{} };",
    "pub const PluginHandler = union(enum) { inline_lua: InlineLuaHandler, lua_file: LuaFileHandler, zig_symbol: ZigSymbolHandler, none };",
    "pub const PluginDescriptor = struct { id: []const u8, kind: []const u8, handler: PluginHandler = .none };",
    "pub const MessageProjection = struct { name: []const u8, pattern: []const u8, slash_alias: []const u8 = \"\", source: []const u8 = \"inferred\", params: []const []const u8 = &.{} };",
    "pub const HttpProjection = struct { method: Method, path: []const u8 };",
    "pub const Route = struct { id: []const u8, canonical_id: []const u8 = \"\", method: Method, raw_path: []const u8, http: HttpProjection, message: MessageProjection, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, validation: ValidationSpec = .{}, memory: RouteMemory, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, pipeline: []const PipelineStage = &.{}, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{}, scope: RouteScope = .{} };",
    "",
  }
  graph_patterns.emit_pattern_tables(graph, lines, output)

  graph_capabilities.emit(graph, lines)

  graph_routes.emit_route_modules(graph, output)
  for _, route in ipairs(graph_nodes(graph)) do
    lines[#lines + 1] = "const " .. graph_routes.route_module_name(route) .. " = @import(\"routes/" .. graph_routes.route_module_name(route) .. ".zig\");"
  end
  lines[#lines + 1] = ""

  -- Embed OpenAPI spec if available
  lines[#lines + 1] = "pub const openapi_spec = @embedFile(\"openapi.json\");"
  lines[#lines + 1] = ""

  if #graph.plugins > 0 then
    lines[#lines + 1] = "pub const plugins = [_]PluginDescriptor{"
    for _, plugin in ipairs(graph.plugins) do
      lines[#lines + 1] = "    .{ .id = " .. helpers.zig_string(plugin.id) .. ", .kind = " .. helpers.zig_string(plugin.kind) .. ", .handler = " .. graph_routes.plugin_handler_zig(plugin) .. " },"
    end
    lines[#lines + 1] = "};"
  else
    lines[#lines + 1] = "pub const plugins = [_]PluginDescriptor{};"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn pluginById(comptime id: []const u8) ?PluginDescriptor {"
  lines[#lines + 1] = "    inline for (plugins) |p| { if (std.mem.eql(u8, p.id, id)) return p; }"
  lines[#lines + 1] = "    return null;"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const routes = [_]Route{"
  for _, route in ipairs(graph.routes) do
    lines[#lines + 1] = "    " .. graph_routes.route_module_name(route) .. ".route(@This()),"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const messages = [_]Route{"
  for _, route in ipairs(graph.messages or {}) do
    lines[#lines + 1] = "    " .. graph_routes.route_module_name(route) .. ".route(@This()),"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  local method_buckets = { GET = {}, HEAD = {}, POST = {}, PUT = {}, PATCH = {}, DELETE = {}, OPTIONS = {}, OTHER = {}, ALL = {} }
  for i, route in ipairs(graph.routes) do method_buckets[route.method][#method_buckets[route.method] + 1] = i - 1 end
  local explicit_head = {}
  for _, route in ipairs(graph.routes) do
    if route.method == "HEAD" then explicit_head[route.raw_path] = true end
  end
  for i, route in ipairs(graph.routes) do
    if route.method == "GET" and not explicit_head[route.raw_path] then
      method_buckets.HEAD[#method_buckets.HEAD + 1] = i - 1
    end
  end
  local method_names = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "OTHER", "ALL" }
  for _, method in ipairs(method_names) do
    lines[#lines + 1] = "pub const " .. method:lower() .. "_routes = [_]Route{"
    for _, route_index in ipairs(method_buckets[method]) do
      lines[#lines + 1] = "    routes[" .. tostring(route_index) .. "],"
    end
    lines[#lines + 1] = "};"
  end
  lines[#lines + 1] = ""
  helpers.write_file(output .. "/graph.zig", table.concat(lines, "\n"))
end

return graph_zig
