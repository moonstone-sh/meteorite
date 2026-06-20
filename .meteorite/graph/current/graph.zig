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
pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, email, token, bool, pattern };
pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };
pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, memory: RouteMemory, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{} };

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
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 
        6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
    };
    const pattern_1_transitions = [_]u16{
        65, 1, 65, 1, 65, 1, 65, 1, 65, 65,
        65, 2, 65, 2, 65, 2, 65, 2, 65, 65,
        65, 3, 65, 3, 65, 3, 65, 3, 65, 65,
        65, 4, 65, 4, 65, 4, 65, 4, 65, 65,
        65, 5, 65, 5, 65, 5, 65, 5, 65, 65,
        65, 6, 65, 6, 65, 6, 65, 6, 65, 65,
        65, 7, 65, 7, 65, 7, 65, 7, 65, 65,
        65, 8, 65, 8, 65, 8, 65, 8, 65, 65,
        65, 9, 65, 9, 65, 9, 65, 9, 65, 65,
        65, 10, 65, 10, 65, 10, 65, 10, 65, 65,
        65, 11, 65, 11, 65, 11, 65, 11, 65, 65,
        65, 12, 65, 12, 65, 12, 65, 12, 65, 65,
        65, 13, 65, 13, 65, 13, 65, 13, 65, 65,
        65, 14, 65, 14, 65, 14, 65, 14, 65, 65,
        65, 15, 65, 15, 65, 15, 65, 15, 65, 65,
        65, 16, 65, 16, 65, 16, 65, 16, 65, 65,
        65, 17, 65, 17, 65, 17, 65, 17, 65, 65,
        65, 18, 65, 18, 65, 18, 65, 18, 65, 65,
        65, 19, 65, 19, 65, 19, 65, 19, 65, 65,
        65, 20, 65, 20, 65, 20, 65, 20, 65, 65,
        65, 21, 65, 21, 65, 21, 65, 21, 65, 65,
        65, 22, 65, 22, 65, 22, 65, 22, 65, 65,
        65, 23, 65, 23, 65, 23, 65, 23, 65, 65,
        65, 24, 65, 24, 65, 24, 65, 24, 65, 65,
        65, 25, 65, 25, 65, 25, 65, 25, 65, 65,
        65, 26, 65, 26, 65, 26, 65, 26, 65, 65,
        65, 27, 65, 27, 65, 27, 65, 27, 65, 65,
        65, 28, 65, 28, 65, 28, 65, 28, 65, 65,
        65, 29, 65, 29, 65, 29, 65, 29, 65, 65,
        65, 30, 65, 30, 65, 30, 65, 30, 65, 65,
        65, 31, 65, 31, 65, 31, 65, 31, 65, 65,
        65, 32, 65, 32, 65, 32, 65, 32, 65, 65,
        65, 33, 65, 33, 65, 33, 65, 33, 65, 65,
        65, 34, 65, 34, 65, 34, 65, 34, 65, 65,
        65, 35, 65, 35, 65, 35, 65, 35, 65, 65,
        65, 36, 65, 36, 65, 36, 65, 36, 65, 65,
        65, 37, 65, 37, 65, 37, 65, 37, 65, 65,
        65, 38, 65, 38, 65, 38, 65, 38, 65, 65,
        65, 39, 65, 39, 65, 39, 65, 39, 65, 65,
        65, 40, 65, 40, 65, 40, 65, 40, 65, 65,
        65, 41, 65, 41, 65, 41, 65, 41, 65, 65,
        65, 42, 65, 42, 65, 42, 65, 42, 65, 65,
        65, 43, 65, 43, 65, 43, 65, 43, 65, 65,
        65, 44, 65, 44, 65, 44, 65, 44, 65, 65,
        65, 45, 65, 45, 65, 45, 65, 45, 65, 65,
        65, 46, 65, 46, 65, 46, 65, 46, 65, 65,
        65, 47, 65, 47, 65, 47, 65, 47, 65, 65,
        65, 48, 65, 48, 65, 48, 65, 48, 65, 65,
        65, 49, 65, 49, 65, 49, 65, 49, 65, 65,
        65, 50, 65, 50, 65, 50, 65, 50, 65, 65,
        65, 51, 65, 51, 65, 51, 65, 51, 65, 65,
        65, 52, 65, 52, 65, 52, 65, 52, 65, 65,
        65, 53, 65, 53, 65, 53, 65, 53, 65, 65,
        65, 54, 65, 54, 65, 54, 65, 54, 65, 65,
        65, 55, 65, 55, 65, 55, 65, 55, 65, 65,
        65, 56, 65, 56, 65, 56, 65, 56, 65, 65,
        65, 57, 65, 57, 65, 57, 65, 57, 65, 65,
        65, 58, 65, 58, 65, 58, 65, 58, 65, 65,
        65, 59, 65, 59, 65, 59, 65, 59, 65, 65,
        65, 60, 65, 60, 65, 60, 65, 60, 65, 65,
        65, 61, 65, 61, 65, 61, 65, 61, 65, 65,
        65, 62, 65, 62, 65, 62, 65, 62, 65, 65,
        65, 63, 65, 63, 65, 63, 65, 63, 65, 65,
        65, 64, 65, 64, 65, 64, 65, 64, 65, 65,
        65, 65, 65, 65, 65, 65, 65, 65, 65, 65,
        65, 65, 65, 65, 65, 65, 65, 65, 65, 65,
    };
    const pattern_1_accept = [_]bool{
        false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
    };
    pub const pattern_1 = @import("meteorite_pattern").DfaMatcher(.{ .class_map = &pattern_1_class_map, .transition_table = &pattern_1_transitions, .accept_table = &pattern_1_accept, .class_count = 10, .start_state = 0, .dead_state = 65, .max_input_bytes = 64 });

    const pattern_2_class_map = [_]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 
        4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 
        6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 
    };
    const pattern_2_transitions = [_]u16{
        81, 1, 81, 1, 81, 1, 81, 1, 81, 81,
        81, 2, 81, 2, 81, 2, 81, 2, 81, 81,
        81, 3, 81, 3, 81, 3, 81, 3, 81, 81,
        81, 4, 81, 4, 81, 4, 81, 4, 81, 81,
        81, 5, 81, 5, 81, 5, 81, 5, 81, 81,
        81, 6, 81, 6, 81, 6, 81, 6, 81, 81,
        81, 7, 81, 7, 81, 7, 81, 7, 81, 81,
        81, 8, 81, 8, 81, 8, 81, 8, 81, 81,
        81, 9, 81, 9, 81, 9, 81, 9, 81, 81,
        81, 10, 81, 10, 81, 10, 81, 10, 81, 81,
        81, 11, 81, 11, 81, 11, 81, 11, 81, 81,
        81, 12, 81, 12, 81, 12, 81, 12, 81, 81,
        81, 13, 81, 13, 81, 13, 81, 13, 81, 81,
        81, 14, 81, 14, 81, 14, 81, 14, 81, 81,
        81, 15, 81, 15, 81, 15, 81, 15, 81, 81,
        81, 16, 81, 16, 81, 16, 81, 16, 81, 81,
        81, 17, 81, 17, 81, 17, 81, 17, 81, 81,
        81, 18, 81, 18, 81, 18, 81, 18, 81, 81,
        81, 19, 81, 19, 81, 19, 81, 19, 81, 81,
        81, 20, 81, 20, 81, 20, 81, 20, 81, 81,
        81, 21, 81, 21, 81, 21, 81, 21, 81, 81,
        81, 22, 81, 22, 81, 22, 81, 22, 81, 81,
        81, 23, 81, 23, 81, 23, 81, 23, 81, 81,
        81, 24, 81, 24, 81, 24, 81, 24, 81, 81,
        81, 25, 81, 25, 81, 25, 81, 25, 81, 81,
        81, 26, 81, 26, 81, 26, 81, 26, 81, 81,
        81, 27, 81, 27, 81, 27, 81, 27, 81, 81,
        81, 28, 81, 28, 81, 28, 81, 28, 81, 81,
        81, 29, 81, 29, 81, 29, 81, 29, 81, 81,
        81, 30, 81, 30, 81, 30, 81, 30, 81, 81,
        81, 31, 81, 31, 81, 31, 81, 31, 81, 81,
        81, 32, 81, 32, 81, 32, 81, 32, 81, 81,
        81, 33, 81, 33, 81, 33, 81, 33, 81, 81,
        81, 34, 81, 34, 81, 34, 81, 34, 81, 81,
        81, 35, 81, 35, 81, 35, 81, 35, 81, 81,
        81, 36, 81, 36, 81, 36, 81, 36, 81, 81,
        81, 37, 81, 37, 81, 37, 81, 37, 81, 81,
        81, 38, 81, 38, 81, 38, 81, 38, 81, 81,
        81, 39, 81, 39, 81, 39, 81, 39, 81, 81,
        81, 40, 81, 40, 81, 40, 81, 40, 81, 81,
        81, 41, 81, 41, 81, 41, 81, 41, 81, 81,
        81, 42, 81, 42, 81, 42, 81, 42, 81, 81,
        81, 43, 81, 43, 81, 43, 81, 43, 81, 81,
        81, 44, 81, 44, 81, 44, 81, 44, 81, 81,
        81, 45, 81, 45, 81, 45, 81, 45, 81, 81,
        81, 46, 81, 46, 81, 46, 81, 46, 81, 81,
        81, 47, 81, 47, 81, 47, 81, 47, 81, 81,
        81, 48, 81, 48, 81, 48, 81, 48, 81, 81,
        81, 49, 81, 49, 81, 49, 81, 49, 81, 81,
        81, 50, 81, 50, 81, 50, 81, 50, 81, 81,
        81, 51, 81, 51, 81, 51, 81, 51, 81, 81,
        81, 52, 81, 52, 81, 52, 81, 52, 81, 81,
        81, 53, 81, 53, 81, 53, 81, 53, 81, 81,
        81, 54, 81, 54, 81, 54, 81, 54, 81, 81,
        81, 55, 81, 55, 81, 55, 81, 55, 81, 81,
        81, 56, 81, 56, 81, 56, 81, 56, 81, 81,
        81, 57, 81, 57, 81, 57, 81, 57, 81, 81,
        81, 58, 81, 58, 81, 58, 81, 58, 81, 81,
        81, 59, 81, 59, 81, 59, 81, 59, 81, 81,
        81, 60, 81, 60, 81, 60, 81, 60, 81, 81,
        81, 61, 81, 61, 81, 61, 81, 61, 81, 81,
        81, 62, 81, 62, 81, 62, 81, 62, 81, 81,
        81, 63, 81, 63, 81, 63, 81, 63, 81, 81,
        81, 64, 81, 64, 81, 64, 81, 64, 81, 81,
        81, 65, 81, 65, 81, 65, 81, 65, 81, 81,
        81, 66, 81, 66, 81, 66, 81, 66, 81, 81,
        81, 67, 81, 67, 81, 67, 81, 67, 81, 81,
        81, 68, 81, 68, 81, 68, 81, 68, 81, 81,
        81, 69, 81, 69, 81, 69, 81, 69, 81, 81,
        81, 70, 81, 70, 81, 70, 81, 70, 81, 81,
        81, 71, 81, 71, 81, 71, 81, 71, 81, 81,
        81, 72, 81, 72, 81, 72, 81, 72, 81, 81,
        81, 73, 81, 73, 81, 73, 81, 73, 81, 81,
        81, 74, 81, 74, 81, 74, 81, 74, 81, 81,
        81, 75, 81, 75, 81, 75, 81, 75, 81, 81,
        81, 76, 81, 76, 81, 76, 81, 76, 81, 81,
        81, 77, 81, 77, 81, 77, 81, 77, 81, 81,
        81, 78, 81, 78, 81, 78, 81, 78, 81, 81,
        81, 79, 81, 79, 81, 79, 81, 79, 81, 81,
        81, 80, 81, 80, 81, 80, 81, 80, 81, 81,
        81, 81, 81, 81, 81, 81, 81, 81, 81, 81,
        81, 81, 81, 81, 81, 81, 81, 81, 81, 81,
    };
    const pattern_2_accept = [_]bool{
        false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false,
    };
    pub const pattern_2 = @import("meteorite_pattern").DfaMatcher(.{ .class_map = &pattern_2_class_map, .transition_table = &pattern_2_transitions, .accept_table = &pattern_2_accept, .class_count = 10, .start_state = 0, .dead_state = 81, .max_input_bytes = 80 });
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
    };
    pub const zig = struct {
        pub const data_cruncher = "native/src/helpers/data_cruncher.zig";
    };
};

const route_1_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "plain" },
};
const route_1_query = [_]ParamSpec{
};
const route_1_params = [_]ParamSpec{
};
const route_1_capabilities = [_]CapabilityRef{
};
pub const Route1Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/plain";
    pub const params = route_1_params;
};
const route_2_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "plain-static" },
};
const route_2_query = [_]ParamSpec{
};
const route_2_params = [_]ParamSpec{
};
const route_2_capabilities = [_]CapabilityRef{
};
pub const Route2Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/plain-static";
    pub const params = route_2_params;
};
const route_3_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "hybrid-zig" },
};
const route_3_query = [_]ParamSpec{
};
const route_3_params = [_]ParamSpec{
};
const route_3_capabilities = [_]CapabilityRef{
};
pub const Route3Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/hybrid-zig";
    pub const params = route_3_params;
};
const route_4_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "meta" },
};
const route_4_query = [_]ParamSpec{
};
const route_4_params = [_]ParamSpec{
};
const route_4_capabilities = [_]CapabilityRef{
};
pub const Route4Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/meta";
    pub const params = route_4_params;
};
const route_5_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "raw" },
};
const route_5_query = [_]ParamSpec{
};
const route_5_params = [_]ParamSpec{
};
const route_5_capabilities = [_]CapabilityRef{
};
pub const Route5Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/raw";
    pub const params = route_5_params;
};
const route_6_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "counters" },
};
const route_6_query = [_]ParamSpec{
};
const route_6_params = [_]ParamSpec{
};
const route_6_capabilities = [_]CapabilityRef{
};
pub const Route6Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/counters";
    pub const params = route_6_params;
};
const route_7_segments = [_]Segment{
    .{ .literal = "health" },
};
const route_7_query = [_]ParamSpec{
};
const route_7_params = [_]ParamSpec{
};
const route_7_capabilities = [_]CapabilityRef{
};
pub const Route7Context = struct {
    pub const method = Method.GET;
    pub const path = "/health";
    pub const params = route_7_params;
};
const route_8_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_8_query = [_]ParamSpec{
};
const route_8_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_8_capabilities = [_]CapabilityRef{
};
pub const Route8Context = struct {
    pub const method = Method.GET;
    pub const path = "/users/:id";
    pub const params = route_8_params;
};
const route_9_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_9_query = [_]ParamSpec{
};
const route_9_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_9_capabilities = [_]CapabilityRef{
};
pub const Route9Context = struct {
    pub const method = Method.PUT;
    pub const path = "/users/:id";
    pub const params = route_9_params;
};
const route_10_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_10_query = [_]ParamSpec{
};
const route_10_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_10_capabilities = [_]CapabilityRef{
};
pub const Route10Context = struct {
    pub const method = Method.PATCH;
    pub const path = "/users/:id";
    pub const params = route_10_params;
};
const route_11_segments = [_]Segment{
    .{ .literal = "users" },
    .{ .param = "id" },
};
const route_11_query = [_]ParamSpec{
};
const route_11_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_11_capabilities = [_]CapabilityRef{
};
pub const Route11Context = struct {
    pub const method = Method.DELETE;
    pub const path = "/users/:id";
    pub const params = route_11_params;
};
const route_12_segments = [_]Segment{
    .{ .literal = "echo" },
};
const route_12_query = [_]ParamSpec{
};
const route_12_params = [_]ParamSpec{
};
const route_12_capabilities = [_]CapabilityRef{
};
pub const Route12Context = struct {
    pub const method = Method.POST;
    pub const path = "/echo";
    pub const params = route_12_params;
};
const route_13_segments = [_]Segment{
    .{ .literal = "devices" },
    .{ .param = "device_id" },
};
const route_13_query = [_]ParamSpec{
};
const route_13_params = [_]ParamSpec{
    .{ .name = "device_id", .kind = .string, .max_len = 64, .exact_len = 0, .optional = false, .pattern = .pattern_1 },
};
const route_13_capabilities = [_]CapabilityRef{
};
pub const Route13Context = struct {
    pub const method = Method.GET;
    pub const path = "/devices/:device_id";
    pub const params = route_13_params;
};
const route_14_segments = [_]Segment{
    .{ .literal = "files" },
    .{ .param = "name" },
};
const route_14_query = [_]ParamSpec{
};
const route_14_params = [_]ParamSpec{
    .{ .name = "name", .kind = .string, .max_len = 80, .exact_len = 0, .optional = false, .pattern = .pattern_2 },
};
const route_14_capabilities = [_]CapabilityRef{
};
pub const Route14Context = struct {
    pub const method = Method.GET;
    pub const path = "/files/:name";
    pub const params = route_14_params;
};
const route_15_segments = [_]Segment{
    .{ .literal = "slugs" },
    .{ .param = "slug" },
};
const route_15_query = [_]ParamSpec{
};
const route_15_params = [_]ParamSpec{
    .{ .name = "slug", .kind = .slug, .max_len = 64, .exact_len = 0, .optional = false, .pattern = null },
};
const route_15_capabilities = [_]CapabilityRef{
};
pub const Route15Context = struct {
    pub const method = Method.GET;
    pub const path = "/slugs/:slug";
    pub const params = route_15_params;
};
const route_16_segments = [_]Segment{
    .{ .literal = "uuids" },
    .{ .param = "id" },
};
const route_16_query = [_]ParamSpec{
};
const route_16_params = [_]ParamSpec{
    .{ .name = "id", .kind = .uuid, .max_len = 0, .exact_len = 36, .optional = false, .pattern = null },
};
const route_16_capabilities = [_]CapabilityRef{
};
pub const Route16Context = struct {
    pub const method = Method.GET;
    pub const path = "/uuids/:id";
    pub const params = route_16_params;
};
const route_17_segments = [_]Segment{
    .{ .literal = "hex" },
    .{ .param = "digest" },
};
const route_17_query = [_]ParamSpec{
};
const route_17_params = [_]ParamSpec{
    .{ .name = "digest", .kind = .hex, .max_len = 0, .exact_len = 32, .optional = false, .pattern = null },
};
const route_17_capabilities = [_]CapabilityRef{
};
pub const Route17Context = struct {
    pub const method = Method.GET;
    pub const path = "/hex/:digest";
    pub const params = route_17_params;
};
const route_18_segments = [_]Segment{
    .{ .literal = "emails" },
    .{ .param = "email" },
};
const route_18_query = [_]ParamSpec{
};
const route_18_params = [_]ParamSpec{
    .{ .name = "email", .kind = .email, .max_len = 254, .exact_len = 0, .optional = false, .pattern = null },
};
const route_18_capabilities = [_]CapabilityRef{
};
pub const Route18Context = struct {
    pub const method = Method.GET;
    pub const path = "/emails/:email";
    pub const params = route_18_params;
};
const route_19_segments = [_]Segment{
    .{ .literal = "tokens" },
    .{ .param = "token" },
};
const route_19_query = [_]ParamSpec{
};
const route_19_params = [_]ParamSpec{
    .{ .name = "token", .kind = .token, .max_len = 64, .exact_len = 0, .optional = false, .pattern = null },
};
const route_19_capabilities = [_]CapabilityRef{
};
pub const Route19Context = struct {
    pub const method = Method.GET;
    pub const path = "/tokens/:token";
    pub const params = route_19_params;
};
const route_20_segments = [_]Segment{
    .{ .literal = "search" },
};
const route_20_query = [_]ParamSpec{
    .{ .name = "exact", .kind = .bool, .max_len = 0, .exact_len = 0, .optional = true, .pattern = null },
    .{ .name = "page", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = true, .pattern = null },
    .{ .name = "q", .kind = .string, .max_len = 80, .exact_len = 0, .optional = false, .pattern = null },
};
const route_20_params = [_]ParamSpec{
};
const route_20_capabilities = [_]CapabilityRef{
};
pub const Route20Context = struct {
    pub const method = Method.GET;
    pub const path = "/search";
    pub const params = route_20_params;
};
const route_21_segments = [_]Segment{
    .{ .literal = "hybrid-inline" },
};
const route_21_query = [_]ParamSpec{
};
const route_21_params = [_]ParamSpec{
};
const route_21_capabilities = [_]CapabilityRef{
};
pub const Route21Context = struct {
    pub const method = Method.GET;
    pub const path = "/hybrid-inline";
    pub const params = route_21_params;
};
const route_22_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "hybrid-inline" },
};
const route_22_query = [_]ParamSpec{
};
const route_22_params = [_]ParamSpec{
};
const route_22_capabilities = [_]CapabilityRef{
};
pub const Route22Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/hybrid-inline";
    pub const params = route_22_params;
};
const route_23_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "hybrid-inline-text-literal" },
};
const route_23_query = [_]ParamSpec{
};
const route_23_params = [_]ParamSpec{
};
const route_23_capabilities = [_]CapabilityRef{
};
pub const Route23Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/hybrid-inline-text-literal";
    pub const params = route_23_params;
};
const route_24_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "hybrid-inline-params" },
    .{ .param = "id" },
};
const route_24_query = [_]ParamSpec{
};
const route_24_params = [_]ParamSpec{
    .{ .name = "id", .kind = .u64, .max_len = 0, .exact_len = 0, .optional = false, .pattern = null },
};
const route_24_capabilities = [_]CapabilityRef{
};
pub const Route24Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/hybrid-inline-params/:id";
    pub const params = route_24_params;
};
const route_25_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "hybrid-inline-echo" },
};
const route_25_query = [_]ParamSpec{
};
const route_25_params = [_]ParamSpec{
};
const route_25_capabilities = [_]CapabilityRef{
};
pub const Route25Context = struct {
    pub const method = Method.POST;
    pub const path = "/__bench/hybrid-inline-echo";
    pub const params = route_25_params;
};
const route_26_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-debug-state" },
};
const route_26_query = [_]ParamSpec{
};
const route_26_params = [_]ParamSpec{
};
const route_26_capabilities = [_]CapabilityRef{
};
pub const Route26Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-debug-state";
    pub const params = route_26_params;
};
const route_27_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-global-counter" },
};
const route_27_query = [_]ParamSpec{
};
const route_27_params = [_]ParamSpec{
};
const route_27_capabilities = [_]CapabilityRef{
};
pub const Route27Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-global-counter";
    pub const params = route_27_params;
};
const route_28_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-state-leak" },
};
const route_28_query = [_]ParamSpec{
};
const route_28_params = [_]ParamSpec{
};
const route_28_capabilities = [_]CapabilityRef{
};
pub const Route28Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-state-leak";
    pub const params = route_28_params;
};
const route_29_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-shared-store" },
};
const route_29_query = [_]ParamSpec{
};
const route_29_params = [_]ParamSpec{
};
const route_29_capabilities = [_]CapabilityRef{
};
pub const Route29Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-shared-store";
    pub const params = route_29_params;
};
const route_30_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-worker-store" },
};
const route_30_query = [_]ParamSpec{
};
const route_30_params = [_]ParamSpec{
};
const route_30_capabilities = [_]CapabilityRef{
};
pub const Route30Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-worker-store";
    pub const params = route_30_params;
};
const route_31_segments = [_]Segment{
    .{ .literal = "__bench" },
    .{ .literal = "lua-require-cache" },
};
const route_31_query = [_]ParamSpec{
};
const route_31_params = [_]ParamSpec{
};
const route_31_capabilities = [_]CapabilityRef{
};
pub const Route31Context = struct {
    pub const method = Method.GET;
    pub const path = "/__bench/lua-require-cache";
    pub const params = route_31_params;
};

pub const routes = [_]Route{
    .{ .id = "plain", .method = .GET, .raw_path = "/__bench/plain", .path = &route_1_segments, .params = &route_1_params, .query = &route_1_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .plain, .symbol = "handlers.plain" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_1_capabilities },
    .{ .id = "plain_static", .method = .GET, .raw_path = "/__bench/plain-static", .path = &route_2_segments, .params = &route_2_params, .query = &route_2_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .plain_static, .symbol = "handlers.plain_static" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_2_capabilities },
    .{ .id = "hybrid_zig", .method = .GET, .raw_path = "/__bench/hybrid-zig", .path = &route_3_segments, .params = &route_3_params, .query = &route_3_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .hybrid_zig, .symbol = "handlers.hybrid_zig" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_3_capabilities },
    .{ .id = "bench_meta", .method = .GET, .raw_path = "/__bench/meta", .path = &route_4_segments, .params = &route_4_params, .query = &route_4_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_meta, .symbol = "handlers.bench_meta" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_4_capabilities },
    .{ .id = "bench_raw", .method = .GET, .raw_path = "/__bench/raw", .path = &route_5_segments, .params = &route_5_params, .query = &route_5_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_raw, .symbol = "handlers.bench_raw" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_5_capabilities },
    .{ .id = "bench_counters", .method = .GET, .raw_path = "/__bench/counters", .path = &route_6_segments, .params = &route_6_params, .query = &route_6_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_counters, .symbol = "handlers.bench_counters" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_6_capabilities },
    .{ .id = "health", .method = .GET, .raw_path = "/health", .path = &route_7_segments, .params = &route_7_params, .query = &route_7_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .health, .symbol = "handlers.health" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_7_capabilities },
    .{ .id = "get_user", .method = .GET, .raw_path = "/users/:id", .path = &route_8_segments, .params = &route_8_params, .query = &route_8_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .get_user, .symbol = "handlers.get_user" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_8_capabilities },
    .{ .id = "put_user", .method = .PUT, .raw_path = "/users/:id", .path = &route_9_segments, .params = &route_9_params, .query = &route_9_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 1048576, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 2433024 }, .max_body_bytes = 1048576, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .put_user, .symbol = "handlers.put_user" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_9_capabilities },
    .{ .id = "patch_user", .method = .PATCH, .raw_path = "/users/:id", .path = &route_10_segments, .params = &route_10_params, .query = &route_10_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 1048576, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 2433024 }, .max_body_bytes = 1048576, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .patch_user, .symbol = "handlers.patch_user" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_10_capabilities },
    .{ .id = "delete_user", .method = .DELETE, .raw_path = "/users/:id", .path = &route_11_segments, .params = &route_11_params, .query = &route_11_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .delete_user, .symbol = "handlers.delete_user" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_11_capabilities },
    .{ .id = "echo", .method = .POST, .raw_path = "/echo", .path = &route_12_segments, .params = &route_12_params, .query = &route_12_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 16384, .max_body_bytes = 8192, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1146880 }, .max_body_bytes = 8192, .request_arena_bytes = 16384, .handler = .{ .zig_symbol = .{ .id = .echo, .symbol = "handlers.echo" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_12_capabilities },
    .{ .id = "get_device", .method = .GET, .raw_path = "/devices/:device_id", .path = &route_13_segments, .params = &route_13_params, .query = &route_13_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .get_device, .symbol = "handlers.get_device" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_13_capabilities },
    .{ .id = "file", .method = .GET, .raw_path = "/files/:name", .path = &route_14_segments, .params = &route_14_params, .query = &route_14_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .file, .symbol = "handlers.file" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_14_capabilities },
    .{ .id = "slug", .method = .GET, .raw_path = "/slugs/:slug", .path = &route_15_segments, .params = &route_15_params, .query = &route_15_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .slug, .symbol = "handlers.slug" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_15_capabilities },
    .{ .id = "uuid", .method = .GET, .raw_path = "/uuids/:id", .path = &route_16_segments, .params = &route_16_params, .query = &route_16_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .uuid, .symbol = "handlers.uuid" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_16_capabilities },
    .{ .id = "hex", .method = .GET, .raw_path = "/hex/:digest", .path = &route_17_segments, .params = &route_17_params, .query = &route_17_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .hex, .symbol = "handlers.hex" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_17_capabilities },
    .{ .id = "email", .method = .GET, .raw_path = "/emails/:email", .path = &route_18_segments, .params = &route_18_params, .query = &route_18_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .email, .symbol = "handlers.email" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_18_capabilities },
    .{ .id = "token", .method = .GET, .raw_path = "/tokens/:token", .path = &route_19_segments, .params = &route_19_params, .query = &route_19_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .token, .symbol = "handlers.token" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_19_capabilities },
    .{ .id = "search", .method = .GET, .raw_path = "/search", .path = &route_20_segments, .params = &route_20_params, .query = &route_20_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .search, .symbol = "handlers.search" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_20_capabilities },
    .{ .id = "hybrid_inline", .method = .GET, .raw_path = "/hybrid-inline", .path = &route_21_segments, .params = &route_21_params, .query = &route_21_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .hybrid_inline, .symbol = "handlers.hybrid_inline" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_21_capabilities },
    .{ .id = "bench_hybrid_inline", .method = .GET, .raw_path = "/__bench/hybrid-inline", .path = &route_22_segments, .params = &route_22_params, .query = &route_22_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_hybrid_inline, .symbol = "handlers.bench_hybrid_inline" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_22_capabilities },
    .{ .id = "bench_hybrid_inline_text_literal", .method = .GET, .raw_path = "/__bench/hybrid-inline-text-literal", .path = &route_23_segments, .params = &route_23_params, .query = &route_23_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_hybrid_inline_text_literal, .symbol = "handlers.bench_hybrid_inline_text_literal" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_23_capabilities },
    .{ .id = "hybrid_inline_params", .method = .GET, .raw_path = "/__bench/hybrid-inline-params/:id", .path = &route_24_segments, .params = &route_24_params, .query = &route_24_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .hybrid_inline_params, .symbol = "handlers.hybrid_inline_params" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_24_capabilities },
    .{ .id = "hybrid_inline_echo", .method = .POST, .raw_path = "/__bench/hybrid-inline-echo", .path = &route_25_segments, .params = &route_25_params, .query = &route_25_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 16384, .max_body_bytes = 8192, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1146880 }, .max_body_bytes = 8192, .request_arena_bytes = 16384, .handler = .{ .zig_symbol = .{ .id = .hybrid_inline_echo, .symbol = "handlers.hybrid_inline_echo" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_25_capabilities },
    .{ .id = "bench_unavailable_state", .method = .GET, .raw_path = "/__bench/lua-debug-state", .path = &route_26_segments, .params = &route_26_params, .query = &route_26_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_state, .symbol = "handlers.bench_unavailable_state" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_26_capabilities },
    .{ .id = "bench_unavailable_global", .method = .GET, .raw_path = "/__bench/lua-global-counter", .path = &route_27_segments, .params = &route_27_params, .query = &route_27_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_global, .symbol = "handlers.bench_unavailable_global" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_27_capabilities },
    .{ .id = "bench_unavailable_leak", .method = .GET, .raw_path = "/__bench/lua-state-leak", .path = &route_28_segments, .params = &route_28_params, .query = &route_28_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_leak, .symbol = "handlers.bench_unavailable_leak" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_28_capabilities },
    .{ .id = "bench_unavailable_shared", .method = .GET, .raw_path = "/__bench/lua-shared-store", .path = &route_29_segments, .params = &route_29_params, .query = &route_29_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_shared, .symbol = "handlers.bench_unavailable_shared" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_29_capabilities },
    .{ .id = "bench_unavailable_worker", .method = .GET, .raw_path = "/__bench/lua-worker-store", .path = &route_30_segments, .params = &route_30_params, .query = &route_30_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_worker, .symbol = "handlers.bench_unavailable_worker" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_30_capabilities },
    .{ .id = "bench_unavailable_require", .method = .GET, .raw_path = "/__bench/lua-require-cache", .path = &route_31_segments, .params = &route_31_params, .query = &route_31_query, .memory = .{ .profile_name = "default", .request_arena_bytes = 262144, .max_body_bytes = 0, .max_uri_bytes = 8192, .max_path_bytes = 4096, .max_query_bytes = 4096, .max_query_pairs = 64, .max_path_segments = 32, .max_response_bytes = 1048576, .max_capability_response_bytes = 65536, .lua_heap_bytes = 0, .estimated_peak_bytes = 1384448 }, .max_body_bytes = 0, .request_arena_bytes = 262144, .handler = .{ .zig_symbol = .{ .id = .bench_unavailable_require, .symbol = "handlers.bench_unavailable_require" } }, .runtime = .{ .requires_lua = false, .requires_http = false, .requires_auth = false, .requires_zig_capability = false, .execution_class = .default }, .execution = .{ .class = .default, .may_block = false, .requires_lua = false, .requires_worker_pool = false }, .capabilities = &route_31_capabilities },
};
