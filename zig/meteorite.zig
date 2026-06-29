const std = @import("std");
const Io = std.Io;
const process = std.process;

pub const backends = struct {
    pub const std_http = @import("backends/std_http.zig");
    pub const fast_http = @import("backends/fast_http.zig");
};

pub const ListenConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
};

pub const BackendContract = struct {
    pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OTHER };
};

pub const meteorite_pattern_module = @import("meteorite_pattern");
pub const DfaMatcher = meteorite_pattern_module.DfaMatcher;
pub const patterns = meteorite_pattern_module.patterns;

const LuaStats = struct {
    lua_states_created: u64 = 0,
    lua_handler_refs_loaded: u64 = 0,
    lua_handler_calls: u64 = 0,
    lua_errors: u64 = 0,
    lua_state_reuse_hits: u64 = 0,
    lua_state_reuse_misses: u64 = 0,
    per_thread_state_count: u64 = 0,
};

const LuaRuntimeUnavailable = struct {
    pub const lua_state_strategy = "none";
    pub const lua_handler_ref_strategy = "none";
    pub const capability_store_strategy = "none";
    pub const require_cache_strategy = "none";

    pub fn snapshotStats() LuaStats {
        return .{};
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        _ = handler;
        try ctx.text(501, "handler requires Lua runtime");
    }
};


pub fn compile(comptime spec: anytype) type {
    return struct {
        const Self = @This();
        const graph = spec.graph;
        const backend = spec.backend;
        const build_info = @import("build_options");
const signals = @import("server/signals.zig");
const http_date = @import("server/http_date.zig");
const server_validators = @import("server/validators.zig");
const server_static = @import("server/static_files.zig");
const server_limits = @import("server/request_limits.zig");
        const lua_runtime = if (@hasField(@TypeOf(spec), "lua_runtime")) spec.lua_runtime else LuaRuntimeUnavailable;
        const dev_reload_enabled = std.mem.eql(u8, build_info.meteorite_mode, "dev") or std.mem.eql(u8, build_info.meteorite_mode, "hybrid_dev");
        const graph_requires_lua = graphRequiresLua();
        const inline_lua_handlers = countHandlers(.inline_lua);
        const zig_handlers = countZigHandlers();
        const hybrid_profile = if (@hasField(@TypeOf(spec), "hybrid_profile")) spec.hybrid_profile else "default";

        pub fn run(io: Io) !void {
            try serve(io, .{});
        }

        pub fn serve(io: Io, config: ListenConfig) !void {
            var server = try backend.listen(.{ .host = config.host, .port = config.port, .io = io });
            defer server.deinit();

            signals.installHandlers();

            std.debug.print("Meteorite build\n  mode: {s}\n  backend: {s}\n  Lua runtime: {s}\n  Lua state: single_locked\n  workers: auto\n  inline Lua handlers: {d}\n  Zig handlers: {d}\n  routes: {d}\n  artifact: dist/server\nListening: http://{s}:{d}\n", .{
                if (graph_requires_lua) "hybrid" else "static",
                backend.name,
                if (graph_requires_lua) "included" else "removed",
                inline_lua_handlers,
                zig_handlers,
                graph.routes.len,
                config.host,
                config.port,
            });

            var accept_failures: u32 = 0;
            while (true) {
                if (signals.isShutdownRequested()) {
                    std.debug.print("Shutting down...\n", .{});
                    Pool.shutdown(io);
                    break;
                }
                var request: backend.Request = undefined;
                backend.accept(&server, &request) catch |err| {
                    accept_failures += 1;
                    std.debug.print("accept failed: {s}\n", .{@errorName(err)});
                    // Exponential backoff on persistent accept errors (capped at 1s)
                    if (accept_failures <= 10) {
                        const backoff_ms: u64 = @min(@as(u64, accept_failures) * 10, 1000);
                        io.sleep(.{ .nanoseconds = @intCast(backoff_ms * std.time.ns_per_ms) }, .real) catch {};
                    } else {
                        io.sleep(.{ .nanoseconds = std.time.ns_per_s }, .real) catch {};
                    }
                    continue;
                };
                accept_failures = 0;
                if (comptime backend.pooled_connections) {
                    try Pool.start(io);
                    if (!Pool.enqueue(io, request)) {
                        backend.droppedConnection();
                        request.close(io);
                    }
                    continue;
                }
                if (comptime backend.threaded_connections) {
                    const boxed_request = try std.heap.smp_allocator.create(backend.Request);
                    boxed_request.* = request;
                    backend.rebind(boxed_request, io);
                    const thread = std.Thread.spawn(.{}, connectionThread, .{ io, boxed_request }) catch |err| {
                        std.debug.print("thread spawn failed: {s}\n", .{@errorName(err)});
                        boxed_request.close(io);
                        std.heap.smp_allocator.destroy(boxed_request);
                        continue;
                    };
                    backend.threadSpawned();
                    thread.detach();
                    continue;
                }
                try serveConnection(io, &request);
            }
        }

        fn connectionThread(io: Io, request: *backend.Request) void {
            serveConnection(io, request) catch |err| {
                std.debug.print("connection failed: {s}\n", .{@errorName(err)});
                backend.connectionError();
                request.close(io);
            };
            std.heap.smp_allocator.destroy(request);
        }

        const Pool = struct {
            const queue_limit = backend.queue_limit;
            var mutex: Io.Mutex = .init;
            var available: Io.Condition = .init;
            var queue: [queue_limit]backend.Request = undefined;
            var head: usize = 0;
            var tail: usize = 0;
            var depth: usize = 0;
            var started = std.atomic.Value(bool).init(false);
            var shutting_down = std.atomic.Value(bool).init(false);

            pub fn shutdown(io: Io) void {
                shutting_down.store(true, .release);
                mutex.lockUncancelable(io);
                available.broadcast(io);
                mutex.unlock(io);
            }

            fn workerCount() usize {
                if (backend.configured_workers > 0) return @intCast(backend.configured_workers);
                return std.Thread.getCpuCount() catch 1;
            }

            fn start(io: Io) !void {
                if (comptime !backend.pooled_connections) return;
                if (started.swap(true, .acquire)) return;
                const count = workerCount();
                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const thread = try std.Thread.spawn(.{}, poolWorker, .{io});
                    backend.threadSpawned();
                    thread.detach();
                }
            }

            fn enqueue(io: Io, request: backend.Request) bool {
                if (queue_limit == 0) return false;
                mutex.lockUncancelable(io);
                defer mutex.unlock(io);
                if (depth == queue_limit) return false;
                queue[tail] = request;
                tail = (tail + 1) % queue_limit;
                depth += 1;
                backend.setQueueDepth(@intCast(depth));
                available.signal(io);
                return true;
            }

            fn dequeue(io: Io) backend.Request {
                mutex.lockUncancelable(io);
                defer mutex.unlock(io);
                while (depth == 0 and !shutting_down.load(.acquire)) {
                    available.waitUncancelable(io, &mutex);
                }
                if (depth == 0) {
                    // Shutdown signaled with empty queue — return a dummy that will be closed
                    return backend.Request{ .stream = undefined };
                }
                const request = queue[head];
                head = (head + 1) % queue_limit;
                depth -= 1;
                backend.setQueueDepth(@intCast(depth));
                return request;
            }

            fn poolWorker(io: Io) void {
                while (true) {
                    if (shutting_down.load(.acquire)) return;
                    var request = dequeue(io);
                    if (shutting_down.load(.acquire)) {
                        request.close(io);
                        return;
                    }
                    backend.rebind(&request, io);
                    serveConnection(io, &request) catch |err| {
                        std.debug.print("pooled connection failed: {s}\n", .{@errorName(err)});
                        backend.connectionError();
                        request.close(io);
                    };
                }
            }
        };

        fn serveConnection(io: Io, request: *backend.Request) !void {
            backend.connectionStarted();
            defer backend.connectionEnded();
            while (true) {
                backend.receiveHead(request) catch |err| {
                    if (err != error.HttpConnectionClosing and err != error.ReadFailed and err != error.EndOfStream) {
                        std.debug.print("receive head failed: {s}\n", .{@errorName(err)});
                    }
                    break;
                };
                var arena_buffer: [graph.max_request_arena_bytes]u8 = undefined;
                var arena_state = std.heap.FixedBufferAllocator.init(&arena_buffer);
                const arena = arena_state.allocator();
                request.body_cache = null;
                request.close_after_response = true;
                // Cache current time for Date header in responses
                if (@hasField(@TypeOf(request.*), "date_seconds")) {
                    request.date_seconds = Io.Timestamp.now(io, .real).toSeconds();
                }
                serveRequest(arena, io, request) catch |err| {
                    std.debug.print("request failed for {s}: {s}\n", .{ backend.path(request), @errorName(err) });
                    request.close_after_response = true;
                };
                // Drain unread body before next keep-alive request.
                // If the handler didn't call body(), unread bytes would corrupt the next request.
                if (@hasDecl(backend, "drainBody")) backend.drainBody(request);
                if (request.close_after_response) break;
            }
            request.close(io);
        }

        pub fn countersJson(allocator: std.mem.Allocator) ![]const u8 {
            const c = backend.snapshotCounters();
            const lua = lua_runtime.snapshotStats();
            return std.fmt.allocPrint(allocator, "{{\"backend\":\"{s}\",\"connection_strategy\":\"{s}\",\"bounded\":{},\"active_connections\":{d},\"total_connections\":{d},\"accepted_connections\":{d},\"threads_spawned\":{d},\"requests_served\":{d},\"requests_per_connection\":{d},\"keepalive_reuse_count\":{d},\"connection_close_count\":{d},\"bytes_read\":{d},\"bytes_written\":{d},\"connection_errors\":{d},\"max_active_connections\":{d},\"queue_depth\":{d},\"max_queue_depth\":{d},\"dropped_connections\":{d},\"lua_states_created\":{d},\"lua_handler_refs_loaded\":{d},\"lua_handler_calls\":{d},\"lua_errors\":{d},\"lua_state_reuse_hits\":{d},\"lua_state_reuse_misses\":{d},\"per_thread_state_count\":{d}}}", .{ backend.name, backend.connection_strategy, backend.bounded, c.active_connections, c.total_connections, c.accepted_connections, c.threads_spawned, c.requests_served, c.requests_per_connection, c.keepalive_reuse_count, c.connection_close_count, c.bytes_read, c.bytes_written, c.connection_errors, c.max_active_connections, c.queue_depth, c.max_queue_depth, c.dropped_connections, lua.lua_states_created, lua.lua_handler_refs_loaded, lua.lua_handler_calls, lua.lua_errors, lua.lua_state_reuse_hits, lua.lua_state_reuse_misses, lua.per_thread_state_count });
        }

        pub fn metaJson(allocator: std.mem.Allocator) ![]const u8 {
            const c = backend.snapshotCounters();
            const lua = lua_runtime.snapshotStats();
            const prefix = try std.fmt.allocPrint(allocator, "{{\"meteorite_mode\":\"{s}\",\"zig_optimize\":\"{s}\",\"target\":\"{s}\",\"backend\":\"{s}\",\"connection_strategy\":\"{s}\",\"backend_strategy\":\"{s}\",\"worker_strategy\":\"{s}\",\"bounded\":{},\"fast_http_workers\":{d},\"fast_http_queue\":{d},\"router_dispatch\":\"{s}\",\"worker_count\":{d},\"lua_runtime\":{},\"hybrid_profile\":\"{s}\",\"lua_state_strategy\":\"{s}\",\"lua_handler_ref_strategy\":\"{s}\",\"capability_store_strategy\":\"{s}\",\"require_cache_strategy\":\"{s}\"", .{ build_info.meteorite_mode, build_info.zig_optimize, build_info.target, backend.name, backend.connection_strategy, backend.connection_strategy, backend.connection_strategy, backend.bounded, build_info.fast_http_workers, build_info.fast_http_queue, build_info.router_dispatch, c.threads_spawned, build_info.lua_runtime, build_info.hybrid_profile, lua_runtime.lua_state_strategy, lua_runtime.lua_handler_ref_strategy, lua_runtime.capability_store_strategy, lua_runtime.require_cache_strategy });
            defer allocator.free(prefix);
            const suffix = try std.fmt.allocPrint(allocator, ",\"active_connections\":{d},\"total_connections\":{d},\"accepted_connections\":{d},\"threads_spawned\":{d},\"requests_served\":{d},\"requests_per_connection\":{d},\"bytes_read\":{d},\"bytes_written\":{d},\"connection_errors\":{d},\"max_active_connections\":{d},\"queue_depth\":{d},\"max_queue_depth\":{d},\"dropped_connections\":{d},\"lua_states_created\":{d},\"lua_handler_refs_loaded\":{d},\"lua_handler_calls\":{d},\"lua_errors\":{d},\"lua_state_reuse_hits\":{d},\"lua_state_reuse_misses\":{d},\"per_thread_state_count\":{d}}}", .{ c.active_connections, c.total_connections, c.accepted_connections, c.threads_spawned, c.requests_served, c.requests_per_connection, c.bytes_read, c.bytes_written, c.connection_errors, c.max_active_connections, c.queue_depth, c.max_queue_depth, c.dropped_connections, lua.lua_states_created, lua.lua_handler_refs_loaded, lua.lua_handler_calls, lua.lua_errors, lua.lua_state_reuse_hits, lua.lua_state_reuse_misses, lua.per_thread_state_count });
            defer allocator.free(suffix);
            return std.mem.concat(allocator, u8, &.{ prefix, suffix });
        }

        fn serveRequest(allocator: std.mem.Allocator, io: Io, request: *backend.Request) !void {
            const req_method = backendMethod(backend.method(request));
            const req_path = backend.path(request);
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__bench/raw")) return backend.respondRawOk(request);
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__bench/meta")) {
                const json = try metaJson(allocator);
                return backend.respondBytes(request, 200, "application/json", json);
            }
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__bench/counters")) {
                const json = try countersJson(allocator);
                return backend.respondBytes(request, 200, "application/json", json);
            }
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__meteorite/graph")) {
                // Output route graph as JSON for dev inspection
                const json = try std.fmt.allocPrint(allocator,
                    "[{{\"routes\":{d}}}]", .{graph.routes.len});
                return backend.respondBytes(request, 200, "application/json", json);
            }
            if (comptime dev_reload_enabled) {
                if ((req_method == .GET or req_method == .POST) and std.mem.eql(u8, req_path, "/__meteorite/reload-lua")) {
                    if (@hasDecl(lua_runtime, "reloadAll")) {
                        try lua_runtime.reloadAll();
                        return backend.respondText(request, 200, "reloaded");
                    }
                    return backend.respondText(request, 501, "lua reload unavailable");
                }
            }
            if (!try enforceGlobalTargetLimits(request, req_path)) return;

            if (comptime std.mem.eql(u8, build_info.router_dispatch, "legacy_scan")) {
                if (try dispatchLegacyScan(req_method, allocator, io, request, req_path)) return;
            } else {
                switch (req_method) {
                    .GET => if (try dispatchRoutes(graph.get_routes, allocator, io, request, req_path)) return,
                    .HEAD => if (try dispatchRoutes(graph.head_routes, allocator, io, request, req_path)) return,
                    .POST => if (try dispatchRoutes(graph.post_routes, allocator, io, request, req_path)) return,
                    .PUT => if (try dispatchRoutes(graph.put_routes, allocator, io, request, req_path)) return,
                    .PATCH => if (try dispatchRoutes(graph.patch_routes, allocator, io, request, req_path)) return,
                    .DELETE => if (try dispatchRoutes(graph.delete_routes, allocator, io, request, req_path)) return,
                    .OTHER => if (try dispatchRoutes(graph.other_routes, allocator, io, request, req_path)) return,
                }
            }
            if (pathMatchedAnyRoute(req_path)) return backend.respondText(request, 405, "method not allowed");
            return backend.respondText(request, 404, "not found");
        }

        fn dispatchLegacyScan(req_method: graph.Method, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8) !bool {
            inline for (graph.routes) |route| {
                if (route.method == req_method and try dispatchRouteGeneric(route, allocator, io, request, req_path)) return true;
            }
            return false;
        }

        fn dispatchRoutes(comptime routes: anytype, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8) !bool {
            inline for (routes) |route| {
                if (try dispatchRoute(route, allocator, io, request, req_path)) return true;
            }
            return false;
        }

        fn dispatchRoute(comptime route: graph.Route, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8) !bool {
            if (comptime std.mem.eql(u8, build_info.router_dispatch, "static_fast_path") or std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) {
                return dispatchRouteStaticFast(route, allocator, io, request, req_path);
            }
            return dispatchRouteGeneric(route, allocator, io, request, req_path);
        }

        fn dispatchRouteGeneric(comptime route: graph.Route, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8) !bool {
            var captures = Captures{};
            if (!matchPath(route.path, req_path, route.params, &captures)) return false;
            return dispatchMatchedRoute(route, allocator, io, request, req_path, captures);
        }

        fn dispatchRouteStaticFast(comptime route: graph.Route, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8) !bool {
            var captures = Captures{};
            if (comptime isLiteralRoute(route)) {
                if (!std.mem.eql(u8, req_path, route.raw_path)) return false;
            } else if (comptime std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) {
                if (!matchRoutePathSpecialized(route, req_path, &captures)) return false;
            } else {
                if (!matchPath(route.path, req_path, route.params, &captures)) return false;
            }
            return dispatchMatchedRoute(route, allocator, io, request, req_path, captures);
        }

        fn executeScopePlugins(comptime route: graph.Route, ctx: *Context) !bool {
            inline for (route.scope.plugins) |plugin_id| {
                if (comptime graph.pluginById(plugin_id)) |plugin| {
                    const short_circuit = try executePlugin(plugin, ctx);
                    if (short_circuit) return true;
                }
            }
            return false;
        }

        fn executePlugin(comptime plugin: graph.PluginDescriptor, ctx: *Context) !bool {
            switch (plugin.handler) {
                .none => return false,
                .inline_lua => |handler| {
                    const short_circuit = try lua_runtime.callPlugin(handler, ctx);
                    if (short_circuit) return true;
                },
                .lua_file => |handler| {
                    const short_circuit = try lua_runtime.callPlugin(handler, ctx);
                    if (short_circuit) return true;
                },
                .zig_symbol => |handler| {
                    _ = handler;
                    // Zig plugin symbols are not executed in v0.1
                },
            }
            return false;
        }

        fn dispatchMatchedRoute(comptime route: graph.Route, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8, captures: Captures) !bool {
            if (!try enforceRouteTargetLimits(request, req_path, route)) return true;
            if (!matchQuery(route.query, request)) {
                try backend.respondText(request, 404, "not found");
                return true;
            }
            if (!try enforceBodyLimit(allocator, request, route)) return true;
            var ctx = Context{ .allocator = allocator, .io = io, .request = request, .captures = captures, .route = route };
            if (try executeScopePlugins(route, &ctx)) return true;
            // If route has a pipeline, execute stages in order.
            // For v0.1, pipeline stages use the same handler infrastructure.
            // The last handle stage is the primary response producer.
            if (route.pipeline.len > 0) {
                for (route.pipeline) |stage| {
                    switch (stage.strat) {
                        .inline_lua => {
                            // Inline Lua stages use the same bridge as handlers
                            // For transforms, we need a separate call path — but
                            // for v0.1, all inline_lua stages use the handler's fn_ref
                            // which is stored in the route's handler field.
                            // Transforms that don't produce a response continue;
                            // handle stages produce the response.
                            if (stage.kind == .handle) {
                                switch (route.handler) {
                                    .inline_lua => |handler| try callLuaHandler(handler, &ctx),
                                    .lua_file => |handler| try callLuaHandler(handler, &ctx),
                                    else => {},
                                }
                            }
                            // Transform stages are a no-op in v0.1 runtime —
                            // they're graph-visible but execution is stubbed
                            // until the full pipeline executor is implemented.
                        },
                        .lua => {
                            // External Lua stages — same as inline_lua for now
                            if (stage.kind == .handle) {
                                switch (route.handler) {
                                    .inline_lua => |handler| try callLuaHandler(handler, &ctx),
                                    .lua_file => |handler| try callLuaHandler(handler, &ctx),
                                    else => {},
                                }
                            }
                        },
                        .zig => {
                            // Zig stages call graph bindings
                            if (stage.kind == .handle) {
                                try graph.bindings.callRoute(route.id, &ctx);
                            }
                            // Zig transform stages are stubbed in v0.1
                        },
                        .rust => {
                            // Rust stages are not supported
                        },
                    }
                }
            } else {
                switch (route.handler) {
                    .zig_symbol, .zig_file => try graph.bindings.callRoute(route.id, &ctx),
                    .inline_lua => |handler| try callLuaHandler(handler, &ctx),
                    .lua_file => |handler| try callLuaHandler(handler, &ctx),
                    .file => |handler| try serveFileHandler(handler, allocator, io, request),
                    .dir => |handler| try serveDirHandler(handler, allocator, io, request, captures),
                }
            }
            return true;
        }

        fn accepts(request: *backend.Request, expected: []const u8) bool {
            const header_value = backend.header(request, "accept") orelse return true;
            return mediaListAccepts(header_value, expected);
        }

        fn mediaListAccepts(header_value: []const u8, expected: []const u8) bool {
            const slash = std.mem.indexOfScalar(u8, expected, '/') orelse return server_static.tokenListContains(header_value, expected);
            const expected_type = expected[0..slash];
            const expected_subtype_end = std.mem.indexOfScalarPos(u8, expected, slash + 1, ';') orelse expected.len;
            const expected_subtype = std.mem.trim(u8, expected[slash + 1 .. expected_subtype_end], " \t");
            var it = std.mem.splitScalar(u8, header_value, ',');
            while (it.next()) |raw_item| {
                const media_range = std.mem.trim(u8, raw_item, " \t");
                if (media_range.len == 0 or server_static.qualityIsZero(media_range)) continue;
                const token_end = std.mem.indexOfScalar(u8, media_range, ';') orelse media_range.len;
                const token = std.mem.trim(u8, media_range[0..token_end], " \t");
                if (std.mem.eql(u8, token, "*/*")) return true;
                const token_slash = std.mem.indexOfScalar(u8, token, '/') orelse continue;
                const token_type = token[0..token_slash];
                const token_subtype = token[token_slash + 1 ..];
                if (!std.ascii.eqlIgnoreCase(token_type, expected_type)) continue;
                if (std.mem.eql(u8, token_subtype, "*")) return true;
                if (std.ascii.eqlIgnoreCase(token_subtype, expected_subtype)) return true;
            }
            return false;
        }

        fn serveFileHandler(comptime handler: graph.FileHandler, allocator: std.mem.Allocator, io: Io, request: *backend.Request) !void {
            if (handler.only_accept) |expected| {
                if (!accepts(request, expected)) return backend.respondText(request, 404, "not found");
            }
            try respondStaticFile(allocator, io, request, handler.artifact_path, handler.content_type, handler.content_length, handler.cache_control, handler.etag, null);
        }

        fn serveDirHandler(comptime handler: graph.DirHandler, allocator: std.mem.Allocator, io: Io, request: *backend.Request, captures: Captures) !void {
            const raw_path = captures.get(handler.param_name) orelse return backend.respondText(request, 404, "not found");
            const normalized = server_static.normalizeStaticPath(allocator, raw_path) catch return backend.respondText(request, 404, "not found");
            defer allocator.free(normalized);
            inline for (handler.manifest) |asset| {
                if (std.mem.eql(u8, asset.request_path, normalized)) {
                    if (selectCompressedAsset(request, asset)) |selected| {
                        return respondStaticFile(allocator, io, request, selected.path, asset.content_type, selected.length, asset.cache_control, selected.etag, selected.encoding);
                    }
                    return respondStaticFile(allocator, io, request, asset.artifact_path, asset.content_type, asset.content_length, asset.cache_control, asset.etag, null);
                }
            }
            return backend.respondText(request, 404, "not found");
        }

        const SelectedAsset = struct { path: []const u8, length: u64, etag: []const u8, encoding: []const u8 };

        fn selectCompressedAsset(request: *backend.Request, comptime asset: graph.StaticAsset) ?SelectedAsset {
            const accept_encoding = backend.header(request, "accept-encoding") orelse return null;
            if (asset.compressed_br_path) |path| {
                if (server_static.tokenListContains(accept_encoding, "br")) return .{ .path = path, .length = asset.compressed_br_length, .etag = asset.compressed_br_etag orelse asset.etag, .encoding = "br" };
            }
            if (asset.compressed_gzip_path) |path| {
                if (server_static.tokenListContains(accept_encoding, "gzip")) return .{ .path = path, .length = asset.compressed_gzip_length, .etag = asset.compressed_gzip_etag orelse asset.etag, .encoding = "gzip" };
            }
            return null;
        }

        fn respondStaticFile(allocator: std.mem.Allocator, io: Io, request: *backend.Request, artifact_path: []const u8, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8) !void {
            const head_only = backend.method(request) == .HEAD;
            if (backend.header(request, "if-none-match")) |value| {
                if (server_static.ifNoneMatch(value, etag)) {
                    return backend.respondStatic(request, 304, content_type, 0, cache_control, etag, content_encoding, "", head_only);
                }
            }
            if (head_only) return backend.respondStatic(request, 200, content_type, content_length, cache_control, etag, content_encoding, "", true);
            const body = try server_static.readArtifactFile(allocator, io, artifact_path, content_length);
            defer allocator.free(body);
            return backend.respondStatic(request, 200, content_type, content_length, cache_control, etag, content_encoding, body, head_only);
        }

        fn pathMatchedAnyRoute(req_path: []const u8) bool {
            inline for (graph.routes) |route| {
                if (comptime (std.mem.eql(u8, build_info.router_dispatch, "static_fast_path") or std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) and isLiteralRoute(route)) {
                    if (std.mem.eql(u8, req_path, route.raw_path)) return true;
                    continue;
                }
                if (comptime std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) {
                    var captures = Captures{};
                    if (matchRoutePathSpecialized(route, req_path, &captures)) return true;
                    continue;
                }
                var captures = Captures{};
                if (matchPath(route.path, req_path, route.params, &captures)) return true;
            }
            return false;
        }

        fn isLiteralRoute(comptime route: graph.Route) bool {
            inline for (route.path) |segment| {
                switch (segment) {
                    .literal => {},
                    .param, .catch_all_param => return false,
                }
            }
            return true;
        }

        fn requestTarget(request: *backend.Request) []const u8 {
            if (@hasDecl(backend, "target")) return backend.target(request);
            return backend.path(request);
        }

        fn enforceGlobalTargetLimits(request: *backend.Request, req_path: []const u8) !bool {
            const target_value = requestTarget(request);
            const query_value = backend.query(request);
            if (target_value.len > graph.max_uri_bytes or req_path.len > graph.max_path_bytes or query_value.len > graph.max_query_bytes) {
                try backend.respondText(request, 414, "uri too long");
                return false;
            }
            if (server_limits.countQueryPairs(query_value) > graph.max_query_pairs or server_limits.countPathSegments(req_path) > graph.max_path_segments) {
                try backend.respondText(request, 414, "uri too long");
                return false;
            }
            return true;
        }

        fn enforceRouteTargetLimits(request: *backend.Request, req_path: []const u8, route: graph.Route) !bool {
            const target_value = requestTarget(request);
            const query_value = backend.query(request);
            if (target_value.len > route.memory.max_uri_bytes or req_path.len > route.memory.max_path_bytes or query_value.len > route.memory.max_query_bytes) {
                try backend.respondText(request, 414, "uri too long");
                return false;
            }
            if (server_limits.countQueryPairs(query_value) > route.memory.max_query_pairs or server_limits.countPathSegments(req_path) > route.memory.max_path_segments) {
                try backend.respondText(request, 414, "uri too long");
                return false;
            }
            return true;
        }



        fn enforceBodyLimit(allocator: std.mem.Allocator, request: *backend.Request, route: graph.Route) !bool {
            _ = backend.readBody(request, allocator, route.max_body_bytes) catch |err| switch (err) {
                error.PayloadTooLarge => {
                    std.debug.print("request body exceeded route limit\n\nroute: {s} {s}\nmax_body_bytes: {d}\n", .{ @tagName(route.method), route.raw_path, route.max_body_bytes });
                    try backend.respondText(request, 413, "payload too large");
                    return false;
                },
                else => return err,
            };
            return true;
        }

        fn callLuaHandler(comptime handler: anytype, ctx: anytype) !void {
            return lua_runtime.call(.{
                .id = handler.id,
                .path = switch (@TypeOf(handler)) {
                    graph.InlineLuaHandler => handler.chunk_path,
                    graph.LuaFileHandler => handler.path,
                    else => @compileError("unsupported Lua handler type"),
                },
            }, ctx);
        }

        fn graphRequiresLua() bool {
            inline for (graph.routes) |route| {
                if (route.runtime.requires_lua) return true;
            }
            return false;
        }

        fn countHandlers(comptime tag: std.meta.Tag(graph.Handler)) usize {
            comptime var count: usize = 0;
            inline for (graph.routes) |route| {
                if (std.meta.activeTag(route.handler) == tag) count += 1;
            }
            return count;
        }

        fn countZigHandlers() usize {
            comptime var count: usize = 0;
            inline for (graph.routes) |route| {
                switch (route.handler) {
                    .zig_symbol, .zig_file => count += 1,
                    else => {},
                }
            }
            return count;
        }

        const Method = graph.Method;

        fn backendMethod(method: backend.Method) Method {
            return switch (method) {
                .GET => .GET,
                .HEAD => .HEAD,
                .POST => .POST,
                .PUT => .PUT,
                .PATCH => .PATCH,
                .DELETE => .DELETE,
                else => .OTHER,
            };
        }

        const Capture = struct { name: []const u8 = "", value: []const u8 = "" };
        const Captures = struct {
            items: [16]Capture = undefined,
            len: usize = 0,

            fn add(self: *Captures, name: []const u8, value: []const u8) bool {
                if (self.len >= self.items.len) return false;
                self.items[self.len] = .{ .name = name, .value = value };
                self.len += 1;
                return true;
            }

            fn get(self: *const Captures, name: []const u8) ?[]const u8 {
                for (self.items[0..self.len]) |item| {
                    if (std.mem.eql(u8, item.name, name)) return item.value;
                }
                return null;
            }
        };

        fn matchPath(comptime route_path: []const graph.Segment, request_path: []const u8, comptime params: []const graph.ParamSpec, captures: *Captures) bool {
            if (route_path.len == 0) return std.mem.eql(u8, request_path, "/");
            var segment_iter = std.mem.splitScalar(u8, std.mem.trim(u8, request_path, "/"), '/');
            inline for (route_path) |segment| {
                const actual = segment_iter.next() orelse return false;
                switch (segment) {
                    .literal => |literal| if (!std.mem.eql(u8, literal, actual)) return false,
                    .param => |name| {
                        inline for (params) |param| {
                            if (std.mem.eql(u8, param.name, name)) {
                                if (!validateParam(param, actual)) return false;
                                if (param.pattern) |pattern| {
                                    if (!graph.patterns.match(pattern, actual)) return false;
                                }
                            }
                        }
                        if (!captures.add(name, actual)) return false;
                    },
                    .catch_all_param => |name| {
                        const rest = segment_iter.rest();
                        const value = if (rest.len == 0) actual else request_path[@intFromPtr(actual.ptr) - @intFromPtr(request_path.ptr) ..];
                        if (!captures.add(name, value)) return false;
                        return true;
                    },
                }
            }
            return segment_iter.next() == null;
        }

        fn matchRoutePathSpecialized(comptime route: graph.Route, request_path: []const u8, captures: *Captures) bool {
            if (route.path.len == 0) return std.mem.eql(u8, request_path, "/");
            var segment_iter = std.mem.splitScalar(u8, std.mem.trim(u8, request_path, "/"), '/');
            inline for (route.path) |segment| {
                const actual = segment_iter.next() orelse return false;
                switch (segment) {
                    .literal => |literal| if (!std.mem.eql(u8, literal, actual)) return false,
                    .param => |name| {
                        const param = comptime paramSpecFor(route.params, name);
                        if (!validateParam(param, actual)) return false;
                        if (param.pattern) |pattern| {
                            if (!graph.patterns.match(pattern, actual)) return false;
                        }
                        if (!captures.add(name, actual)) return false;
                    },
                    .catch_all_param => |name| {
                        const rest = segment_iter.rest();
                        const value = if (rest.len == 0) actual else request_path[@intFromPtr(actual.ptr) - @intFromPtr(request_path.ptr) ..];
                        if (!captures.add(name, value)) return false;
                        return true;
                    },
                }
            }
            return segment_iter.next() == null;
        }

        fn paramSpecFor(comptime params: []const graph.ParamSpec, comptime name: []const u8) graph.ParamSpec {
            inline for (params) |param| {
                if (std.mem.eql(u8, param.name, name)) return param;
            }
            return .{ .name = name };
        }

        fn validateParam(comptime param: graph.ParamSpec, value: []const u8) bool {
            if (param.exact_len != 0 and value.len != param.exact_len) return false;
            if (param.max_len != 0 and value.len > param.max_len) return false;
            return switch (param.kind) {
                .string => true,
                .pattern => true,
                .slug => server_validators.isSlug(value),
                .u64 => server_validators.isUnsigned(value),
                .i32 => server_validators.isI32(value),
                .uuid => server_validators.isUuid(value),
                .hex => server_validators.isHex(value),
                .email => server_validators.isEmail(value),
                .token => server_validators.isToken(value),
                .bool => std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "0"),
            };
        }

        fn matchQuery(comptime specs: []const graph.ParamSpec, request: *backend.Request) bool {
            inline for (specs) |query_spec| {
                if (queryValue(request, query_spec.name)) |value| {
                    if (query_spec.pattern) |pattern| {
                        if (!graph.patterns.match(pattern, value)) return false;
                    }
                    if (!validateParam(query_spec, value)) return false;
                } else if (!query_spec.optional) {
                    return false;
                }
            }
            return true;
        }

        fn queryValue(request: *backend.Request, name: []const u8) ?[]const u8 {
            const raw_query = backend.query(request);
            if (raw_query.len == 0) return null;
            var parts = std.mem.splitScalar(u8, raw_query, '&');
            while (parts.next()) |part| {
                if (part.len == 0) continue;
                const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
                if (std.mem.eql(u8, part[0..eq], name)) {
                    return if (eq < part.len) part[eq + 1 ..] else "";
                }
            }
            return null;
        }

        pub const Context = struct {
            allocator: std.mem.Allocator,
            io: Io,
            request: *backend.Request,
            captures: Captures,
            route: graph.Route,
            cached_body: ?[]const u8 = null,

            pub fn method(self: *Context) Method {
                return backendMethod(backend.method(self.request));
            }

            pub fn path(self: *Context) []const u8 {
                return backend.path(self.request);
            }

            pub fn run(self: *Context, allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
                const result = try process.run(allocator, self.io, .{ .argv = argv });
                defer allocator.free(result.stderr);
                return result.stdout;
            }

            pub fn param(self: *Context, name: []const u8) ?[]const u8 {
                return self.captures.get(name);
            }

            pub fn query(self: *Context, name: []const u8) ?[]const u8 {
                return queryValue(self.request, name);
            }

            pub fn header(self: *Context, name: []const u8) ?[]const u8 {
                return backend.header(self.request, name);
            }

            pub fn body(self: *Context) ![]const u8 {
                if (self.cached_body) |b| return b;
                self.cached_body = backend.readBody(self.request, self.allocator, self.route.max_body_bytes) catch |err| switch (err) {
                    error.PayloadTooLarge => {
                        std.debug.print("request body exceeded route limit\n\nroute: {s} {s}\nmax_body_bytes: {d}\n", .{ @tagName(self.route.method), self.route.raw_path, self.route.max_body_bytes });
                        try backend.respondText(self.request, 413, "payload too large");
                        return err;
                    },
                    else => return err,
                };
                return self.cached_body.?;
            }

            pub fn text(self: *Context, status: u16, response_body: []const u8) !void {
                if (response_body.len > self.route.memory.max_response_bytes) {
                    return backend.respondText(self.request, 500, "response too large");
                }
                try backend.respondText(self.request, status, response_body);
            }

            pub fn bytes(self: *Context, status: u16, content_type: []const u8, response_body: []const u8) !void {
                if (response_body.len > self.route.memory.max_response_bytes) {
                    return backend.respondText(self.request, 500, "response too large");
                }
                try backend.respondBytes(self.request, status, content_type, response_body);
            }

            pub fn json(self: *Context, status: u16, response_body: []const u8) !void {
                try self.bytes(status, "application/json", response_body);
            }

            pub fn scope(self: *Context, name: []const u8) ?[]const u8 {
                for (self.route.scope.context) |ref| {
                    if (std.mem.eql(u8, ref.key, name)) return ref.value;
                }
                return null;
            }

        };
    };
}
