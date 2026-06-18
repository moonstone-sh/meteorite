pub const bindings = @import("graph_bindings.zig");
pub const ctx = @import("meteorite_ctx").ctx;

pub const max_request_arena_bytes = 262144;
pub const Method = enum { GET, POST, OTHER };
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
pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, bool, pattern };
pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };
pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{} };

pub const PatternId = enum { none,
    pattern_1,
    pattern_2,
};

pub const patterns = struct {
    pub fn match(comptime id: PatternId, input: []const u8) bool {
        return switch (id) {
            .none => true,
            .pattern_1 => pattern_1.match(input),
            .pattern_2 => pattern_2.match(input),
        };
    }

    const pattern_1_class_map = [_]u8{
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 3, 4, 4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 
        4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 
    };
    const pattern_1_transitions = [_]u16{
        1, 1, 1, 1, 65,
        2, 2, 2, 2, 65,
        3, 3, 3, 3, 65,
        4, 4, 4, 4, 65,
        5, 5, 5, 5, 65,
        6, 6, 6, 6, 65,
        7, 7, 7, 7, 65,
        8, 8, 8, 8, 65,
        9, 9, 9, 9, 65,
        10, 10, 10, 10, 65,
        11, 11, 11, 11, 65,
        12, 12, 12, 12, 65,
        13, 13, 13, 13, 65,
        14, 14, 14, 14, 65,
        15, 15, 15, 15, 65,
        16, 16, 16, 16, 65,
        17, 17, 17, 17, 65,
        18, 18, 18, 18, 65,
        19, 19, 19, 19, 65,
        20, 20, 20, 20, 65,
        21, 21, 21, 21, 65,
        22, 22, 22, 22, 65,
        23, 23, 23, 23, 65,
        24, 24, 24, 24, 65,
        25, 25, 25, 25, 65,
        26, 26, 26, 26, 65,
        27, 27, 27, 27, 65,
        28, 28, 28, 28, 65,
        29, 29, 29, 29, 65,
        30, 30, 30, 30, 65,
        31, 31, 31, 31, 65,
        32, 32, 32, 32, 65,
        33, 33, 33, 33, 65,
        34, 34, 34, 34, 65,
        35, 35, 35, 35, 65,
        36, 36, 36, 36, 65,
        37, 37, 37, 37, 65,
        38, 38, 38, 38, 65,
        39, 39, 39, 39, 65,
        40, 40, 40, 40, 65,
        41, 41, 41, 41, 65,
        42, 42, 42, 42, 65,
        43, 43, 43, 43, 65,
        44, 44, 44, 44, 65,
        45, 45, 45, 45, 65,
        46, 46, 46, 46, 65,
        47, 47, 47, 47, 65,
        48, 48, 48, 48, 65,
        49, 49, 49, 49, 65,
        50, 50, 50, 50, 65,
        51, 51, 51, 51, 65,
        52, 52, 52, 52, 65,
        53, 53, 53, 53, 65,
        54, 54, 54, 54, 65,
        55, 55, 55, 55, 65,
        56, 56, 56, 56, 65,
        57, 57, 57, 57, 65,
        58, 58, 58, 58, 65,
        59, 59, 59, 59, 65,
        60, 60, 60, 60, 65,
        61, 61, 61, 61, 65,
        62, 62, 62, 62, 65,
        63, 63, 63, 63, 65,
        64, 64, 64, 64, 65,
        65, 65, 65, 65, 65,
        65, 65, 65, 65, 65,
    };
    const pattern_1_accept = [_]bool{
        false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
    };
    pub const pattern_1 = @import("meteorite.zig").DfaMatcher(.{ .class_map = &pattern_1_class_map, .transition_table = &pattern_1_transitions, .accept_table = &pattern_1_accept, .class_count = 5, .start_state = 0, .dead_state = 65, .max_input_bytes = 64 });

    const pattern_2_class_map = [_]u8{
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 3, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 5, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 2, 
        5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
    };
    const pattern_2_transitions = [_]u16{
        1, 1, 1, 1, 1, 81,
        2, 2, 2, 2, 2, 81,
        3, 3, 3, 3, 3, 81,
        4, 4, 4, 4, 4, 81,
        5, 5, 5, 5, 5, 81,
        6, 6, 6, 6, 6, 81,
        7, 7, 7, 7, 7, 81,
        8, 8, 8, 8, 8, 81,
        9, 9, 9, 9, 9, 81,
        10, 10, 10, 10, 10, 81,
        11, 11, 11, 11, 11, 81,
        12, 12, 12, 12, 12, 81,
        13, 13, 13, 13, 13, 81,
        14, 14, 14, 14, 14, 81,
        15, 15, 15, 15, 15, 81,
        16, 16, 16, 16, 16, 81,
        17, 17, 17, 17, 17, 81,
        18, 18, 18, 18, 18, 81,
        19, 19, 19, 19, 19, 81,
        20, 20, 20, 20, 20, 81,
        21, 21, 21, 21, 21, 81,
        22, 22, 22, 22, 22, 81,
        23, 23, 23, 23, 23, 81,
        24, 24, 24, 24, 24, 81,
        25, 25, 25, 25, 25, 81,
        26, 26, 26, 26, 26, 81,
        27, 27, 27, 27, 27, 81,
        28, 28, 28, 28, 28, 81,
        29, 29, 29, 29, 29, 81,
        30, 30, 30, 30, 30, 81,
        31, 31, 31, 31, 31, 81,
        32, 32, 32, 32, 32, 81,
        33, 33, 33, 33, 33, 81,
        34, 34, 34, 34, 34, 81,
        35, 35, 35, 35, 35, 81,
        36, 36, 36, 36, 36, 81,
        37, 37, 37, 37, 37, 81,
        38, 38, 38, 38, 38, 81,
        39, 39, 39, 39, 39, 81,
        40, 40, 40, 40, 40, 81,
        41, 41, 41, 41, 41, 81,
        42, 42, 42, 42, 42, 81,
        43, 43, 43, 43, 43, 81,
        44, 44, 44, 44, 44, 81,
        45, 45, 45, 45, 45, 81,
        46, 46, 46, 46, 46, 81,
        47, 47, 47, 47, 47, 81,
        48, 48, 48, 48, 48, 81,
        49, 49, 49, 49, 49, 81,
        50, 50, 50, 50, 50, 81,
        51, 51, 51, 51, 51, 81,
        52, 52, 52, 52, 52, 81,
        53, 53, 53, 53, 53, 81,
        54, 54, 54, 54, 54, 81,
        55, 55, 55, 55, 55, 81,
        56, 56, 56, 56, 56, 81,
        57, 57, 57, 57, 57, 81,
        58, 58, 58, 58, 58, 81,
        59, 59, 59, 59, 59, 81,
        60, 60, 60, 60, 60, 81,
        61, 61, 61, 61, 61, 81,
        62, 62, 62, 62, 62, 81,
        63, 63, 63, 63, 63, 81,
        64, 64, 64, 64, 64, 81,
        65, 65, 65, 65, 65, 81,
        66, 66, 66, 66, 66, 81,
        67, 67, 67, 67, 67, 81,
        68, 68, 68, 68, 68, 81,
        69, 69, 69, 69, 69, 81,
        70, 70, 70, 70, 70, 81,
        71, 71, 71, 71, 71, 81,
        72, 72, 72, 72, 72, 81,
        73, 73, 73, 73, 73, 81,
        74, 74, 74, 74, 74, 81,
        75, 75, 75, 75, 75, 81,
        76, 76, 76, 76, 76, 81,
        77, 77, 77, 77, 77, 81,
        78, 78, 78, 78, 78, 81,
        79, 79, 79, 79, 79, 81,
        80, 80, 80, 80, 80, 81,
        81, 81, 81, 81, 81, 81,
        81, 81, 81, 81, 81, 81,
    };
    const pattern_2_accept = [_]bool{
        false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
    };
    pub const pattern_2 = @import("meteorite.zig").DfaMatcher(.{ .class_map = &pattern_2_class_map, .transition_table = &pattern_2_transitions, .accept_table = &pattern_2_accept, .class_count = 6, .start_state = 0, .dead_state = 81, .max_input_bytes = 80 });
};

const route_1_segments = [_]Segment{
    .{ .literal = "health" },
};
const route_1_query = [_]ParamSpec{
};
const route_1_params = [_]ParamSpec{
};
const route_1_capabilities = [_]CapabilityRef{
};
pub const Route1Context = struct {
    pub const method = Method.GET;
    pub const path = "/health";
    pub const params = route_1_params;
};
const route_2_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_2_query = [_]ParamSpec{
};
const route_2_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_2_capabilities = [_]CapabilityRef{
};
pub const Route2Context = struct {
    pub const method = Method.GET;
    pub const path = "/users/:id";
    pub const params = route_2_params;
};
const route_3_segments = [_]Segment{
    .{ .literal = "echo" },
};
const route_3_query = [_]ParamSpec{
};
const route_3_params = [_]ParamSpec{
};
const route_3_capabilities = [_]CapabilityRef{
};
pub const Route3Context = struct {
    pub const method = Method.POST;
    pub const path = "/echo";
    pub const params = route_3_params;
};
const route_4_segments = [_]Segment{
    .{ .literal = "devices" },
    .{ .param = "device_id" },
};
const route_4_query = [_]ParamSpec{
};
const route_4_params = [_]ParamSpec{
    .{ .name = "device_id", .kind = .string, .max_len = 64, .exact_len = 0, .optional = false, .pattern = .pattern_1 },
};
const route_4_capabilities = [_]CapabilityRef{
};
pub const Route4Context = struct {
    pub const method = Method.GET;
    pub const path = "/devices/:device_id";
    pub const params = route_4_params;
};
const route_5_segments = [_]Segment{
    .{ .literal = "files" },
    .{ .param = "name" },
};
const route_5_query = [_]ParamSpec{
};
const route_5_params = [_]ParamSpec{
    .{ .name = "name", .kind = .string, .max_len = 80, .exact_len = 0, .optional = false, .pattern = .pattern_2 },
};
const route_5_capabilities = [_]CapabilityRef{
};
pub const Route5Context = struct {
    pub const method = Method.GET;
    pub const path = "/files/:name";
    pub const params = route_5_params;
};
const route_6_segments = [_]Segment{
    .{ .literal = "slugs" },
    .{ .param = "slug" },
};
const route_6_query = [_]ParamSpec{
};
const route_6_params = [_]ParamSpec{
    .{ .name = "slug", .kind = .slug, .max_len = 64, .exact_len = 0, .optional = false, .pattern = null },
};
const route_6_capabilities = [_]CapabilityRef{
};
pub const Route6Context = struct {
    pub const method = Method.GET;
    pub const path = "/slugs/:slug";
    pub const params = route_6_params;
};
const route_7_segments = [_]Segment{
    .{ .literal = "uuids" },
    .{ .param = "id" },
};
const route_7_query = [_]ParamSpec{
};
const route_7_params = [_]ParamSpec{
    .{ .name = "id", .kind = .uuid, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_7_capabilities = [_]CapabilityRef{
};
pub const Route7Context = struct {
    pub const method = Method.GET;
    pub const path = "/uuids/:id";
    pub const params = route_7_params;
};
const route_8_segments = [_]Segment{
    .{ .literal = "hex" },
    .{ .param = "digest" },
};
const route_8_query = [_]ParamSpec{
};
const route_8_params = [_]ParamSpec{
    .{ .name = "digest", .kind = .hex, .max_len = 0, .exact_len = 32, .optional = false, .pattern = null },
};
const route_8_capabilities = [_]CapabilityRef{
};
pub const Route8Context = struct {
    pub const method = Method.GET;
    pub const path = "/hex/:digest";
    pub const params = route_8_params;
};
const route_9_segments = [_]Segment{
    .{ .literal = "search" },
};
const route_9_query = [_]ParamSpec{
    .{ .name = "exact", .kind = .bool, .max_len = 0, .exact_len = 0, .optional = true, .pattern = null },
    .{ .name = "page", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = true, .pattern = null },
    .{ .name = "q", .kind = .string, .max_len = 80, .exact_len = 0, .optional = false, .pattern = null },
};
const route_9_params = [_]ParamSpec{
};
const route_9_capabilities = [_]CapabilityRef{
};
pub const Route9Context = struct {
    pub const method = Method.GET;
    pub const path = "/search";
    pub const params = route_9_params;
};

pub const routes = [_]Route{
    .{ .id = "health", .method = .GET, .raw_path = "/health", .path = &route_1_segments, .params = &route_1_params, .query = &route_1_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .health, .symbol = "handlers.health" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_1_capabilities },
    .{ .id = "get_user", .method = .GET, .raw_path = "/users/:id", .path = &route_2_segments, .params = &route_2_params, .query = &route_2_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .get_user, .symbol = "handlers.get_user" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_2_capabilities },
    .{ .id = "echo", .method = .POST, .raw_path = "/echo", .path = &route_3_segments, .params = &route_3_params, .query = &route_3_query, .max_body_bytes = 8192, .request_arena_bytes = 16384, .handler = .{ .zig_symbol = .{ .id = .echo, .symbol = "handlers.echo" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_3_capabilities },
    .{ .id = "get_device", .method = .GET, .raw_path = "/devices/:device_id", .path = &route_4_segments, .params = &route_4_params, .query = &route_4_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .get_device, .symbol = "handlers.get_device" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_4_capabilities },
    .{ .id = "file", .method = .GET, .raw_path = "/files/:name", .path = &route_5_segments, .params = &route_5_params, .query = &route_5_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .file, .symbol = "handlers.file" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_5_capabilities },
    .{ .id = "slug", .method = .GET, .raw_path = "/slugs/:slug", .path = &route_6_segments, .params = &route_6_params, .query = &route_6_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .slug, .symbol = "handlers.slug" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_6_capabilities },
    .{ .id = "uuid", .method = .GET, .raw_path = "/uuids/:id", .path = &route_7_segments, .params = &route_7_params, .query = &route_7_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .uuid, .symbol = "handlers.uuid" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_7_capabilities },
    .{ .id = "hex", .method = .GET, .raw_path = "/hex/:digest", .path = &route_8_segments, .params = &route_8_params, .query = &route_8_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .hex, .symbol = "handlers.hex" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_8_capabilities },
    .{ .id = "search", .method = .GET, .raw_path = "/search", .path = &route_9_segments, .params = &route_9_params, .query = &route_9_query, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .search, .symbol = "handlers.search" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_9_capabilities },
};
