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
    pub const Method = enum { GET, POST, PUT, PATCH, DELETE, OTHER };
};

pub const meteorite_pattern_module = @import("meteorite_pattern");
pub const DfaMatcher = meteorite_pattern_module.DfaMatcher;
pub const patterns = meteorite_pattern_module.patterns;


pub fn compile(comptime spec: anytype) type {
    return struct {
        const Self = @This();
        const graph = spec.graph;
        const backend = spec.backend;
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

            while (true) {
                var request: backend.Request = undefined;
                backend.accept(&server, &request) catch |err| {
                    std.debug.print("accept failed: {s}\n", .{@errorName(err)});
                    continue;
                };
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
                while (depth == 0) available.waitUncancelable(io, &mutex);
                const request = queue[head];
                head = (head + 1) % queue_limit;
                depth -= 1;
                backend.setQueueDepth(@intCast(depth));
                return request;
            }

            fn poolWorker(io: Io) void {
                while (true) {
                    var request = dequeue(io);
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
                serveRequest(arena, io, request) catch |err| {
                    std.debug.print("request failed for {s}: {s}\n", .{ backend.path(request), @errorName(err) });
                    request.close_after_response = true;
                };
                if (request.close_after_response) break;
            }
            request.close(io);
        }

        pub fn countersJson(allocator: std.mem.Allocator) ![]const u8 {
            const c = backend.snapshotCounters();
            return std.fmt.allocPrint(allocator, "{{\"backend\":\"{s}\",\"connection_strategy\":\"{s}\",\"bounded\":{},\"active_connections\":{d},\"total_connections\":{d},\"accepted_connections\":{d},\"threads_spawned\":{d},\"requests_served\":{d},\"requests_per_connection\":{d},\"keepalive_reuse_count\":{d},\"connection_close_count\":{d},\"bytes_read\":{d},\"bytes_written\":{d},\"connection_errors\":{d},\"max_active_connections\":{d},\"queue_depth\":{d},\"max_queue_depth\":{d},\"dropped_connections\":{d}}}", .{ backend.name, backend.connection_strategy, backend.bounded, c.active_connections, c.total_connections, c.accepted_connections, c.threads_spawned, c.requests_served, c.requests_per_connection, c.keepalive_reuse_count, c.connection_close_count, c.bytes_read, c.bytes_written, c.connection_errors, c.max_active_connections, c.queue_depth, c.max_queue_depth, c.dropped_connections });
        }

        pub fn metaJson(allocator: std.mem.Allocator) ![]const u8 {
            const build_info = @import("build_options");
            const c = backend.snapshotCounters();
            return std.fmt.allocPrint(allocator, "{{\"meteorite_mode\":\"{s}\",\"zig_optimize\":\"{s}\",\"target\":\"{s}\",\"backend\":\"{s}\",\"connection_strategy\":\"{s}\",\"bounded\":{},\"fast_http_workers\":{d},\"fast_http_queue\":{d},\"lua_runtime\":{},\"hybrid_profile\":\"{s}\",\"lua_state_strategy\":\"{s}\",\"active_connections\":{d},\"total_connections\":{d},\"accepted_connections\":{d},\"threads_spawned\":{d},\"requests_served\":{d},\"requests_per_connection\":{d},\"bytes_read\":{d},\"bytes_written\":{d},\"connection_errors\":{d},\"max_active_connections\":{d},\"queue_depth\":{d},\"max_queue_depth\":{d},\"dropped_connections\":{d}}}", .{ build_info.meteorite_mode, build_info.zig_optimize, build_info.target, backend.name, backend.connection_strategy, backend.bounded, build_info.fast_http_workers, build_info.fast_http_queue, build_info.lua_runtime, build_info.hybrid_profile, build_info.lua_state_strategy, c.active_connections, c.total_connections, c.accepted_connections, c.threads_spawned, c.requests_served, c.requests_per_connection, c.bytes_read, c.bytes_written, c.connection_errors, c.max_active_connections, c.queue_depth, c.max_queue_depth, c.dropped_connections });
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
            if (!try enforceGlobalTargetLimits(request, req_path)) return;
            var path_matched = false;

            inline for (graph.routes) |route| {
                var captures = Captures{};
                if (matchPath(route.path, req_path, route.params, &captures)) {
                    path_matched = true;
                    if (route.method == req_method) {
                        if (!try enforceRouteTargetLimits(request, req_path, route)) return;
                        if (!matchQuery(route.query, request)) return backend.respondText(request, 404, "not found");
                        if (!try enforceBodyLimit(allocator, request, route)) return;
                        var ctx = Context{ .allocator = allocator, .io = io, .request = request, .captures = captures, .route = route };
                        switch (route.handler) {
                            .zig_symbol => return graph.bindings.callRoute(route.id, &ctx),
                            .zig_file => |handler| return ctx.text(501, handler.path),
                            .inline_lua => |handler| return callLuaHandler(handler, &ctx),
                            .lua_file => |handler| return callLuaHandler(handler, &ctx),
                        }
                    }
                }
            }
            if (path_matched) return backend.respondText(request, 405, "method not allowed");
            return backend.respondText(request, 404, "not found");
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
            if (countQueryPairs(query_value) > graph.max_query_pairs or countPathSegments(req_path) > graph.max_path_segments) {
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
            if (countQueryPairs(query_value) > route.memory.max_query_pairs or countPathSegments(req_path) > route.memory.max_path_segments) {
                try backend.respondText(request, 414, "uri too long");
                return false;
            }
            return true;
        }

        fn countQueryPairs(query_value: []const u8) usize {
            if (query_value.len == 0) return 0;
            var count: usize = 1;
            for (query_value) |byte| {
                if (byte == '&') count += 1;
            }
            return count;
        }

        fn countPathSegments(path_value: []const u8) usize {
            if (std.mem.eql(u8, path_value, "/")) return 0;
            var count: usize = 0;
            var it = std.mem.splitScalar(u8, path_value, '/');
            while (it.next()) |segment| {
                if (segment.len > 0) count += 1;
            }
            return count;
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
            if (@hasField(@TypeOf(spec), "lua_runtime")) {
                return spec.lua_runtime.call(.{
                    .id = handler.id,
                    .path = switch (@TypeOf(handler)) {
                        graph.InlineLuaHandler => handler.chunk_path,
                        graph.LuaFileHandler => handler.path,
                        else => @compileError("unsupported Lua handler type"),
                    },
                }, ctx);
            }
            return ctx.text(501, "handler requires Lua runtime");
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
                }
            }
            return segment_iter.next() == null;
        }

        fn validateParam(comptime param: graph.ParamSpec, value: []const u8) bool {
            if (param.exact_len != 0 and value.len != param.exact_len) return false;
            if (param.max_len != 0 and value.len > param.max_len) return false;
            return switch (param.kind) {
                .string => true,
                .pattern => true,
                .slug => isSlug(value),
                .u64 => isUnsigned(value),
                .i32 => isI32(value),
                .uuid => isUuid(value),
                .hex => isHex(value),
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

        fn isUnsigned(value: []const u8) bool {
            if (value.len == 0) return false;
            for (value) |c| if (c < '0' or c > '9') return false;
            return true;
        }

        fn isI32(value: []const u8) bool {
            if (value.len == 0) return false;
            const start: usize = if (value[0] == '-') 1 else 0;
            if (start == value.len) return false;
            return isUnsigned(value[start..]);
        }

        fn isSlug(value: []const u8) bool {
            if (value.len == 0) return false;
            for (value) |c| {
                const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
                if (!ok) return false;
            }
            return true;
        }

        fn isHex(value: []const u8) bool {
            if (value.len == 0) return false;
            for (value) |c| {
                const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
                if (!ok) return false;
            }
            return true;
        }

        fn isUuid(value: []const u8) bool {
            if (value.len != 36) return false;
            for (value, 0..) |c, i| {
                if (i == 8 or i == 13 or i == 18 or i == 23) {
                    if (c != '-') return false;
                } else {
                    const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
                    if (!ok) return false;
                }
            }
            return true;
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

        };
    };
}
