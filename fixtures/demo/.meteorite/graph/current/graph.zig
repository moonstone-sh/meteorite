pub const bindings = @import("graph_bindings.zig");
pub const ctx = @import("meteorite_ctx").ctx;

pub const max_request_arena_bytes = 262144;
pub const max_uri_bytes = 8192;
pub const max_path_bytes = 4096;
pub const max_query_bytes = 4096;
pub const max_query_pairs = 64;
pub const max_path_segments = 32;
pub const Method = enum { GET, POST, PUT, PATCH, DELETE, OTHER };
pub const Segment = union(enum) { literal: []const u8, param: []const u8 };
pub const ZigSymbolHandler = struct { id: bindings.HandlerId, symbol: []const u8 };
pub const ZigFileHandler = struct { id: []const u8, path: []const u8, decl: []const u8 = "handle" };
pub const LuaFileHandler = struct { id: []const u8, path: []const u8 };
pub const InlineLuaHandler = struct { id: []const u8, chunk_path: []const u8, source_file: []const u8, source_line: u32, source_column: u32 };
pub const Handler = union(enum) { zig_symbol: ZigSymbolHandler, zig_file: ZigFileHandler, lua_file: LuaFileHandler, inline_lua: InlineLuaHandler };
pub const ExecutionClass = enum { default, lua, blocking_io, cpu };
pub const RouteRuntime = struct { requires_lua: bool = false, requires_http: bool = false, requires_auth: bool = false, requires_zig_capability: bool = false, execution_class: ExecutionClass = .default };
pub const RouteExecution = struct { class: ExecutionClass = .default, may_block: bool = false, requires_lua: bool = false, requires_worker_pool: bool = false };
pub const CapabilityRef = union(enum) { http: []const u8, auth: []const u8, zig: []const u8, lua: []const u8, worker: []const u8 };
pub const WorkerStrategy = enum { auto, single_thread, io_plus_workers, per_core, pinned_appliance };
pub const LuaStateStrategy = enum { single_locked, per_worker };
pub const ThreadCount = union(enum) { auto, fixed: u16 };
pub const RuntimeWorkers = struct { strategy: WorkerStrategy = .auto, io_threads: ThreadCount = .auto, worker_threads: ThreadCount = .auto, lua_state: LuaStateStrategy = .single_locked };
pub const runtime_workers = RuntimeWorkers{};
pub const RouteMemory = struct { profile_name: []const u8, request_arena_bytes: usize, max_body_bytes: usize, max_uri_bytes: usize, max_path_bytes: usize, max_query_bytes: usize, max_query_pairs: usize, max_path_segments: usize, max_response_bytes: usize, max_capability_response_bytes: usize, lua_heap_bytes: usize, estimated_peak_bytes: usize };
pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, bool, pattern };
pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };
pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, memory: RouteMemory, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{} };

pub const PatternId = enum { none
};

pub const patterns = struct {
    pub fn match(comptime id: PatternId, input: []const u8) bool {
        _ = input;
        return switch (id) {
            .none => true,
        };
    }
};

pub const capabilities = struct {
    pub const http = struct {
        pub const db = .{
            .base_url = "http://localhost:8888",
            .max_response_bytes = 65536,
            .timeout_ms = 1500
        };
    };
    pub const auth = struct {
        pub const db = .{
            .audience = "db",
            .refresh_before_seconds = 30,
            .token_url = "http://localhost:8888/token"
        };
    };
    pub const zig = struct {
        pub const data_cruncher = "native/src/helpers/data_cruncher.zig";
    };
};

const route_1_segments = [_]Segment{
};
const route_1_query = [_]ParamSpec{
};
const route_1_params = [_]ParamSpec{
};
const route_1_capabilities = [_]CapabilityRef{
};
pub const Route1Context = struct {
    pub const method = Method.GET;
    pub const path = "/";
    pub const params = route_1_params;
};
const route_2_segments = [_]Segment{
    .{ .literal = "health" },
};
const route_2_query = [_]ParamSpec{
};
const route_2_params = [_]ParamSpec{
};
const route_2_capabilities = [_]CapabilityRef{
};
pub const Route2Context = struct {
    pub const method = Method.GET;
    pub const path = "/health";
    pub const params = route_2_params;
};
const route_3_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_3_query = [_]ParamSpec{
};
const route_3_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_3_capabilities = [_]CapabilityRef{
    .{ .auth = "db" },
    .{ .http = "db" },
};
pub const Route3Context = struct {
    pub const method = Method.GET;
    pub const path = "/users/:id";
    pub const params = route_3_params;
};
const route_4_segments = [_]Segment{
    .{ .literal = "echo" },
};
const route_4_query = [_]ParamSpec{
};
const route_4_params = [_]ParamSpec{
};
const route_4_capabilities = [_]CapabilityRef{
};
pub const Route4Context = struct {
    pub const method = Method.POST;
    pub const path = "/echo";
    pub const params = route_4_params;
};
const route_5_segments = [_]Segment{
    .{ .literal = "devices" },
    .{ .param = "device_id" },
};
const route_5_query = [_]ParamSpec{
};
const route_5_params = [_]ParamSpec{
    .{ .name = "device_id", .kind = .string, .max_len = 64, .exact_len = 0, .optional = false, .pattern = null },
};
const route_5_capabilities = [_]CapabilityRef{
    .{ .zig = "data_cruncher" },
};
pub const Route5Context = struct {
    pub const method = Method.GET;
    pub const path = "/devices/:device_id";
    pub const params = route_5_params;
};

pub const routes = [_]Route{
    .{ .id = "route_1", .method = .GET, .raw_path = "/", .path = &route_1_segments, .params = &route_1_params, .query = &route_1_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .inline_lua = .{ .id = "route_1", .chunk_path = "fixtures/demo/.meteorite/graph/current/../../lua/inline/route_1.lua", .source_file = "fixtures/demo/src/app.lua", .source_line = 25, .source_column = 1 } }, .runtime = .{ .requires_lua = true, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .lua }, .execution = .{ .class = .lua, .may_block = false, .requires_lua = true, .requires_worker_pool = false }, .capabilities = &route_1_capabilities },
    .{ .id = "route_2", .method = .GET, .raw_path = "/health", .path = &route_2_segments, .params = &route_2_params, .query = &route_2_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .inline_lua = .{ .id = "route_2", .chunk_path = "fixtures/demo/.meteorite/graph/current/../../lua/inline/route_2.lua", .source_file = "fixtures/demo/src/app.lua", .source_line = 29, .source_column = 1 } }, .runtime = .{ .requires_lua = true, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .lua }, .execution = .{ .class = .lua, .may_block = false, .requires_lua = true, .requires_worker_pool = false }, .capabilities = &route_2_capabilities },
    .{ .id = "route_3", .method = .GET, .raw_path = "/users/:id", .path = &route_3_segments, .params = &route_3_params, .query = &route_3_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .inline_lua = .{ .id = "route_3", .chunk_path = "fixtures/demo/.meteorite/graph/current/../../lua/inline/route_3.lua", .source_file = "fixtures/demo/src/app.lua", .source_line = 40, .source_column = 1 } }, .runtime = .{ .requires_lua = true, .requires_http = true, .requires_auth = true, .requires_zig_capability = false, .execution_class = .lua }, .execution = .{ .class = .lua, .may_block = false, .requires_lua = true, .requires_worker_pool = false }, .capabilities = &route_3_capabilities },
    .{ .id = "route_4", .method = .POST, .raw_path = "/echo", .path = &route_4_segments, .params = &route_4_params, .query = &route_4_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 8192, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1392640 }, .max_body_bytes = 8192, .request_arena_bytes = 262144, .handler = .{ .inline_lua = .{ .id = "route_4", .chunk_path = "fixtures/demo/.meteorite/graph/current/../../lua/inline/route_4.lua", .source_file = "fixtures/demo/src/app.lua", .source_line = 59, .source_column = 1 } }, .runtime = .{ .requires_lua = true, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .lua }, .execution = .{ .class = .lua, .may_block = false, .requires_lua = true, .requires_worker_pool = false }, .capabilities = &route_4_capabilities },
    .{ .id = "route_5", .method = .GET, .raw_path = "/devices/:device_id", .path = &route_5_segments, .params = &route_5_params, .query = &route_5_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .inline_lua = .{ .id = "route_5", .chunk_path = "fixtures/demo/.meteorite/graph/current/../../lua/inline/route_5.lua", .source_file = "fixtures/demo/src/app.lua", .source_line = 67, .source_column = 1 } }, .runtime = .{ .requires_lua = true, .requires_http = false, .requires_auth = false, .requires_zig_capability = true, .execution_class = .lua }, .execution = .{ .class = .lua, .may_block = false, .requires_lua = true, .requires_worker_pool = false }, .capabilities = &route_5_capabilities },
};
