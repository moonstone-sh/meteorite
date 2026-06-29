pub const bindings = @import("graph_bindings.zig");
const std = @import("std");

pub const ctx = @import("meteorite_ctx").ctx;

pub const max_request_arena_bytes = 262144;
pub const max_uri_bytes = 8192;
pub const max_path_bytes = 4096;
pub const max_query_bytes = 4096;
pub const max_query_pairs = 64;
pub const max_path_segments = 32;
pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OTHER };
pub const Segment = union(enum) { literal: []const u8, param: []const u8, catch_all_param: []const u8 };
pub const ZigSymbolHandler = struct { id: bindings.HandlerId, symbol: []const u8 };
pub const ZigFileHandler = struct { id: []const u8, path: []const u8, decl: []const u8 = "handle" };
pub const LuaFileHandler = struct { id: []const u8, path: []const u8 };
pub const InlineLuaHandler = struct { id: []const u8, chunk_path: []const u8, source_file: []const u8, source_line: u32, source_column: u32 };
pub const FileHandler = struct { artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, only_accept: ?[]const u8 = null };
pub const StaticAsset = struct { request_path: []const u8, artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, compressed_br_path: ?[]const u8 = null, compressed_br_length: u64 = 0, compressed_br_etag: ?[]const u8 = null, compressed_gzip_path: ?[]const u8 = null, compressed_gzip_length: u64 = 0, compressed_gzip_etag: ?[]const u8 = null };
pub const DirHandler = struct { mount_root: []const u8, param_name: []const u8, manifest: []const StaticAsset, cache_control: []const u8, immutable: bool = false };
pub const Handler = union(enum) { zig_symbol: ZigSymbolHandler, zig_file: ZigFileHandler, lua_file: LuaFileHandler, inline_lua: InlineLuaHandler, file: FileHandler, dir: DirHandler };
pub const StageKind = enum { transform, handle, hook };
pub const StageStrat = enum { inline_lua, lua, zig, rust };
pub const PipelineStage = struct { id: []const u8 = "", kind: StageKind = .handle, strat: StageStrat = .inline_lua, path: []const u8 = "", symbol: []const u8 = "", may_short_circuit: bool = true, owner: []const u8 = "" };
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
pub const ScopeRef = struct { id: []const u8, path_prefix: []const u8 };
pub const ScopeContextRef = struct { key: []const u8, value: []const u8 };
pub const RouteScope = struct { id: []const u8 = "root", parent: []const u8 = "", path_prefix: []const u8 = "", chain: []const ScopeRef = &.{}, plugins: []const []const u8 = &.{}, context: []const ScopeContextRef = &.{} };
pub const PluginHandler = union(enum) { inline_lua: InlineLuaHandler, lua_file: LuaFileHandler, zig_symbol: ZigSymbolHandler, none };
pub const PluginDescriptor = struct { id: []const u8, kind: []const u8, handler: PluginHandler = .none };
pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, memory: RouteMemory, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, pipeline: []const PipelineStage = &.{}, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{}, scope: RouteScope = .{} };

pub const PatternId = enum { none,
    pattern_1,
    pattern_2,
};

const pattern_pattern_1 = @import("patterns/pattern_pattern_1.zig");
const pattern_pattern_2 = @import("patterns/pattern_pattern_2.zig");

pub const patterns = struct {
    pub fn match(comptime id: PatternId, input: []const u8) bool {
        return switch (id) {
            .none => true,
            .pattern_1 => pattern_pattern_1.matcher.match(input),
            .pattern_2 => pattern_pattern_2.matcher.match(input),
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
    };
    pub const zig = struct {
        pub const data_cruncher = "zig/helpers/data_cruncher.zig";
    };
};

const route_GET__health_health = @import("routes/route_GET__health_health.zig");
const route_GET__users__id_get_user = @import("routes/route_GET__users__id_get_user.zig");
const route_PUT__users__id_put_user = @import("routes/route_PUT__users__id_put_user.zig");
const route_PATCH__users__id_patch_user = @import("routes/route_PATCH__users__id_patch_user.zig");
const route_DELETE__users__id_delete_user = @import("routes/route_DELETE__users__id_delete_user.zig");
const route_POST__echo_echo = @import("routes/route_POST__echo_echo.zig");
const route_GET__devices__device_id_get_device = @import("routes/route_GET__devices__device_id_get_device.zig");
const route_GET__files__name_file = @import("routes/route_GET__files__name_file.zig");
const route_GET__slugs__slug_slug = @import("routes/route_GET__slugs__slug_slug.zig");
const route_GET__uuids__id_uuid = @import("routes/route_GET__uuids__id_uuid.zig");
const route_GET__hex__digest_hex = @import("routes/route_GET__hex__digest_hex.zig");
const route_GET__emails__email_email = @import("routes/route_GET__emails__email_email.zig");
const route_GET__tokens__token_token = @import("routes/route_GET__tokens__token_token.zig");
const route_GET__search_search = @import("routes/route_GET__search_search.zig");
const route_GET__hybrid_inline_route_15 = @import("routes/route_GET__hybrid_inline_route_15.zig");

pub const plugins = [_]PluginDescriptor{};

pub fn pluginById(comptime id: []const u8) ?PluginDescriptor {
    inline for (plugins) |p| { if (std.mem.eql(u8, p.id, id)) return p; }
    return null;
}

pub const routes = [_]Route{
    route_GET__health_health.route(@This()),
    route_GET__users__id_get_user.route(@This()),
    route_PUT__users__id_put_user.route(@This()),
    route_PATCH__users__id_patch_user.route(@This()),
    route_DELETE__users__id_delete_user.route(@This()),
    route_POST__echo_echo.route(@This()),
    route_GET__devices__device_id_get_device.route(@This()),
    route_GET__files__name_file.route(@This()),
    route_GET__slugs__slug_slug.route(@This()),
    route_GET__uuids__id_uuid.route(@This()),
    route_GET__hex__digest_hex.route(@This()),
    route_GET__emails__email_email.route(@This()),
    route_GET__tokens__token_token.route(@This()),
    route_GET__search_search.route(@This()),
    route_GET__hybrid_inline_route_15.route(@This()),
};

pub const get_routes = [_]Route{
    routes[0],
    routes[1],
    routes[6],
    routes[7],
    routes[8],
    routes[9],
    routes[10],
    routes[11],
    routes[12],
    routes[13],
    routes[14],
};
pub const head_routes = [_]Route{
};
pub const post_routes = [_]Route{
    routes[5],
};
pub const put_routes = [_]Route{
    routes[2],
};
pub const patch_routes = [_]Route{
    routes[3],
};
pub const delete_routes = [_]Route{
    routes[4],
};
pub const other_routes = [_]Route{
};
