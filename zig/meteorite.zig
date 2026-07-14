const std = @import("std");
const Io = std.Io;
const bench_stats = @import("bridge/lua_bench_stats");
const protocol = @import("meteorite_protocol");

pub const backends = struct {
    pub const std_http = @import("backends/std_http.zig");
    pub const fast_http = @import("backends/fast_http.zig");
    pub const unix_socket = @import("backends/unix_socket.zig");
    pub const unix_socket_http = @import("backends/unix_socket_http.zig");
};

pub const ListenConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
};

pub const BackendContract = struct {
    pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, OTHER, ALL };
};

pub const meteorite_pattern_module = @import("meteorite_pattern");
pub const DfaMatcher = meteorite_pattern_module.DfaMatcher;
pub const patterns = meteorite_pattern_module.patterns;

pub fn compile(comptime spec: anytype) type {
    return struct {
        const Self = @This();
        const graph = spec.graph;
        const backend = spec.backend;
        const build_info = @import("build_options");
        const signals = @import("server/signals.zig");
        const http_date = @import("server/http_date.zig");
        const server_static = @import("server/static_files.zig");
        const server_limits = @import("server/request_limits.zig");
        const lua_unavailable = @import("server/lua_runtime_unavailable.zig");
        const request_id = @import("server/request_id.zig");
        const request_validation = @import("server/request_validation.zig").Validator(graph, backend);
        const route_match = @import("server/route_match.zig").Matcher(graph, backend, protocol, request_validation.validateParam);
        const lua_runtime = if (@hasField(@TypeOf(spec), "lua_runtime")) spec.lua_runtime else lua_unavailable.Runtime;
        const dev_reload_enabled = std.mem.eql(u8, build_info.meteorite_mode, "dev") or std.mem.eql(u8, build_info.meteorite_mode, "hybrid_dev");
        const startup_log = @import("server/startup_log.zig").StartupLog(graph, backend, build_info);
        const graph_requires_lua = graphRequiresLua();
        const inline_lua_handlers = countHandlers(.inline_lua);
        const zig_handlers = countZigHandlers();
        const hybrid_profile = if (@hasField(@TypeOf(spec), "hybrid_profile")) spec.hybrid_profile else "default";

        pub fn run(io: Io) !void {
            try serve(io, .{});
        }

        var global_cached_time_started = std.atomic.Value(bool).init(false);
        var global_cached_time = std.atomic.Value(i64).init(0);

        fn timerWorker(io: Io) void {
            while (true) {
                global_cached_time.store(Io.Timestamp.now(io, .real).toSeconds(), .release);
                io.sleep(.{ .nanoseconds = std.time.ns_per_s }, .real) catch {};
            }
        }

        pub fn serve(io: Io, config: ListenConfig) !void {
            if (build_info.require_peer_credentials and !build_info.capability_peer_credentials) return error.PeerCredentialsUnsupported;

            if (!global_cached_time_started.swap(true, .acquire)) {
                global_cached_time.store(Io.Timestamp.now(io, .real).toSeconds(), .release);
                const thread = std.Thread.spawn(.{}, timerWorker, .{io}) catch unreachable;
                thread.detach();
            }

            var server = if (@hasField(backend.ListenConfig, "path"))
                try backend.listen(.{ .path = build_info.unix_socket_path, .mode = build_info.unix_socket_mode, .unlink_stale = build_info.unix_socket_unlink_stale, .io = io })
            else
                try backend.listen(.{ .host = config.host, .port = config.port, .io = io });
            defer server.deinit();

            signals.installHandlers();

            startup_log.print(config, graph_requires_lua, inline_lua_handlers, zig_handlers);

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
                        respondReceiveHeadError(request, err);
                    }
                    break;
                };
                var arena_buffer: [graph.max_request_arena_bytes]u8 = undefined;
                var arena_state = std.heap.FixedBufferAllocator.init(&arena_buffer);
                const arena = arena_state.allocator();
                if (!@hasField(@TypeOf(request.*), "frame_buffer")) request.body_cache = null;
                request.close_after_response = !@hasField(@TypeOf(request.*), "frame_buffer");
                // Cache current time for Date header in responses
                if (@hasField(@TypeOf(request.*), "date_seconds")) {
                    request.date_seconds = global_cached_time.load(.acquire);
                }
                backend.requestStarted();
                serveRequest(arena, io, request) catch |err| {
                    std.debug.print("request failed for {s}: {s}\n", .{ backend.path(request), @errorName(err) });
                    request.close_after_response = true;
                    backend.respondText(request, 500, "internal server error") catch |respond_err| {
                        std.debug.print("error response failed for {s}: {s}\n", .{ backend.path(request), @errorName(respond_err) });
                    };
                };
                // Drain unread body before next keep-alive request.
                // If the handler didn't call body(), unread bytes would corrupt the next request.
                if (@hasDecl(backend, "drainBody")) backend.drainBody(request);
                backend.requestCompleted();
                if (request.close_after_response) break;
            }
            request.close(io);
        }

        fn respondReceiveHeadError(request: *backend.Request, err: anyerror) void {
            request.close_after_response = true;
            if (@hasDecl(backend, "respondParseError")) {
                switch (err) {
                    error.HeaderTooLarge => backend.respondParseError(request, 400, "bad request"),
                    error.StreamTooLong => backend.respondParseError(request, 400, "bad request"),
                    error.BadRequest => backend.respondParseError(request, 400, "bad request"),
                    error.PayloadTooLarge => backend.respondParseError(request, 413, "payload too large"),
                    else => {},
                }
            }
        }

        const server_info = @import("server/server_info.zig").Info(backend, lua_runtime, build_info);
        const countersJson = server_info.countersJson;
        const metaJson = server_info.metaJson;
        const buildInfoJson = server_info.buildInfoJson;
        const native_message = @import("server/native_message.zig").NativeMessage(graph, backend, bench_stats, Captures, validateParam, respondValidationError, dispatchMatchedRoute, metaJson, countersJson);
        const dispatchNativeMessage = native_message.dispatch;

        fn serveRequest(allocator: std.mem.Allocator, io: Io, request: *backend.Request) !void {
            const raw_method = backend.method(request);
            const req_method = backendMethod(raw_method);
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
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__meteorite/info")) {
                const json = try buildInfoJson(allocator);
                return backend.respondBytes(request, 200, "application/json", json);
            }
            if (req_method == .POST and std.mem.eql(u8, req_path, "/__bench/stats/reset")) {
                backend.resetAuditCounters();
                bench_stats.reset();
                return backend.respondText(request, 200, "ok");
            }
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__meteorite/graph")) {
                // Output route graph as JSON for dev inspection
                const json = try std.fmt.allocPrint(allocator, "[{{\"routes\":{d}}}]", .{graph.routes.len});
                return backend.respondBytes(request, 200, "application/json", json);
            }
            if (req_method == .GET and std.mem.eql(u8, req_path, "/__meteorite/openapi.json")) {
                return backend.respondBytes(request, 200, "application/json", graph.openapi_spec);
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
            if (comptime @hasField(@TypeOf(request.*), "frame_buffer")) {
                if (try dispatchNativeMessage(allocator, io, request, req_path)) return;
                return backend.respondText(request, 404, "not found");
            }
            if (!try enforceGlobalTargetLimits(request, req_path)) return;
            if (try route_dispatch.dispatch(req_method, allocator, io, request, req_path)) return;
            if (raw_method == .OPTIONS) {
                if (try respondOptionsPreflight(allocator, request, req_path)) return;
            }
            if (pathMatchedAnyRoute(req_path)) return respondMethodNotAllowed(allocator, request, req_path);
            return backend.respondText(request, 404, "not found");
        }

        const route_dispatch = @import("server/route_dispatch.zig").Dispatcher(graph, build_info, backend, Captures, matchPath, matchRoutePathSpecialized, isLiteralRoute, dispatchMatchedRoute);
        const route_execution = @import("server/route_execution.zig").Execution(graph, lua_runtime, build_info, serveFileHandler, serveDirHandler);
        const executeScopePlugins = route_execution.executeScopePlugins;
        const respondRouteError = route_execution.respondRouteError;
        const callLuaHandler = route_execution.callLuaHandler;
        const executeRouteBody = route_execution.executeRouteBody;

        fn dispatchMatchedRoute(comptime route: graph.Route, allocator: std.mem.Allocator, io: Io, request: *backend.Request, req_path: []const u8, captures: Captures) !bool {
            if (!try enforceRouteTargetLimits(request, req_path, route)) return true;
            if (validateQuery(route.query, allocator, request)) |validation_error| {
                try respondValidationError(request, validation_error);
                return true;
            }
            if (validateHeaders(route.validation.headers, request)) |validation_error| {
                try respondValidationError(request, validation_error);
                return true;
            }
            if (validateCookies(route.validation.cookies, request)) |validation_error| {
                try respondValidationError(request, validation_error);
                return true;
            }
            if (!try enforceBodyLimit(allocator, request, route)) return true;
            if (try validateJsonBody(route.validation.json_body, request, allocator)) |validation_error| {
                try respondValidationError(request, validation_error);
                return true;
            }
            if (!jsonContentTypeValid(request)) {
                if (try validateFormBody(route.validation.form_body, request)) |validation_error| {
                    try respondValidationError(request, validation_error);
                    return true;
                }
            }
            var ctx = Context{ .allocator = allocator, .io = io, .request = request, .captures = captures, .route = route };
            if (executeScopePlugins(route, &ctx) catch |err| return respondRouteError(&ctx, err)) {
                try ctx.commitResponse();
                return true;
            }
            if (try executeRouteBody(route, &ctx, allocator, io, request, captures)) return true;
            try ctx.commitResponse();
            return true;
        }

        const static_response = @import("server/static_response.zig").StaticResponse(graph, backend, server_static, Captures, Io);
        const serveFileHandler = static_response.serveFileHandler;
        const serveDirHandler = static_response.serveDirHandler;

        fn routeMatchesRequestPath(comptime route: graph.Route, req_path: []const u8) bool {
            if (comptime (std.mem.eql(u8, build_info.router_dispatch, "static_fast_path") or std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) and isLiteralRoute(route)) {
                return std.mem.eql(u8, req_path, route.raw_path);
            }
            if (comptime std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) {
                var captures = Captures{};
                return matchRoutePathSpecialized(route, req_path, &captures);
            }
            var captures = Captures{};
            return matchPath(route.path, req_path, route.params, &captures);
        }

        const method_negotiation = @import("server/method_negotiation.zig").Negotiator(graph, backend, routeMatchesRequestPath);
        const pathMatchedAnyRoute = method_negotiation.pathMatchedAnyRoute;
        const respondMethodNotAllowed = method_negotiation.respondMethodNotAllowed;
        const respondOptionsPreflight = method_negotiation.respondOptionsPreflight;

        const request_enforcement = @import("server/request_enforcement.zig").Enforcer(graph, backend, server_limits, server_static);
        const enforceGlobalTargetLimits = request_enforcement.enforceGlobalTargetLimits;
        const enforceRouteTargetLimits = request_enforcement.enforceRouteTargetLimits;
        const enforceBodyLimit = request_enforcement.enforceBodyLimit;
        const context_response = @import("server/context_response.zig").Response(backend, protocol, build_info);
        const context_request = @import("server/context_request.zig").RequestContext(backend, protocol, build_info, request_id, backendProtocolMethod, queryValue, queryAllValues);

        fn graphRequiresLua() bool {
            return !std.mem.eql(u8, lua_runtime.lua_state_strategy, "none");
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

        const Method = route_match.Method;
        const Captures = route_match.Captures;
        const isLiteralRoute = route_match.isLiteralRoute;
        const backendMethod = route_match.backendMethod;
        const backendProtocolMethod = route_match.backendProtocolMethod;
        const matchPath = route_match.matchPath;
        const matchRoutePathSpecialized = route_match.matchRoutePathSpecialized;

        const validateParam = request_validation.validateParam;
        const respondValidationError = request_validation.respondError;
        const validateQuery = request_validation.validateQuery;
        const validateHeaders = request_validation.validateHeaders;
        const validateCookies = request_validation.validateCookies;
        const jsonContentTypeValid = request_validation.jsonContentTypeValid;
        const validateJsonBody = request_validation.validateJsonBody;
        const validateFormBody = request_validation.validateFormBody;
        const queryValue = request_validation.queryValue;
        const queryAllValues = request_validation.queryAllValues;

        pub const Context = struct {
            const StateEntry = struct { key: []const u8, value: []const u8 };

            allocator: std.mem.Allocator,
            io: Io,
            request: *backend.Request,
            captures: Captures,
            route: graph.Route,
            cached_body: ?[]const u8 = null,
            responded: bool = false,
            response_staged: bool = false,
            response_committed: bool = false,
            response_status: u16 = 204,
            response_content_type: []const u8 = "text/plain; charset=utf-8",
            response_body: []const u8 = "",
            response_headers: [16]backend.Header = undefined,
            response_header_count: usize = 0,
            request_id_cache: ?[]const u8 = null,
            state: [32]StateEntry = undefined,
            state_len: usize = 0,

            pub fn method(self: *Context) Method {
                return backendMethod(backend.method(self.request));
            }

            fn captureEntries(self: *Context) ![]const protocol.MetadataEntry {
                return context_request.captureEntries(self);
            }

            fn queryEntries(self: *Context) ![]const protocol.MetadataEntry {
                return context_request.queryEntries(self);
            }

            fn requestMetadataEntries(self: *Context) ![]const protocol.MetadataEntry {
                return context_request.requestMetadataEntries(self);
            }

            pub fn meteoriteRequest(self: *Context) !protocol.MeteoriteRequest {
                return context_request.meteoriteRequest(self);
            }

            pub fn path(self: *Context) []const u8 {
                return context_request.path(self);
            }

            pub fn message(self: *Context) []const u8 {
                return context_request.message(self);
            }

            pub fn run(self: *Context, allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
                return context_request.run(self, allocator, argv);
            }

            pub fn param(self: *Context, name: []const u8) ?[]const u8 {
                return context_request.param(self, name);
            }

            pub fn paramAt(self: *Context, index: usize) ?[]const u8 {
                return context_request.paramAt(self, index);
            }

            pub fn query(self: *Context, name: []const u8) ?[]const u8 {
                return context_request.query(self, name);
            }

            pub fn queryAll(self: *Context, name: []const u8) ?[][]const u8 {
                return context_request.queryAll(self, name);
            }

            pub fn metadata(self: *Context, name: []const u8) ?[]const u8 {
                return context_request.metadata(self, name);
            }

            pub fn header(self: *Context, name: []const u8) ?[]const u8 {
                return context_request.header(self, name);
            }

            pub fn requestId(self: *Context) ![]const u8 {
                return context_request.requestId(self);
            }

            pub fn stateGet(self: *Context, key: []const u8) ?[]const u8 {
                return context_request.stateGet(self, key);
            }

            pub fn stateSet(self: *Context, key: []const u8, value: []const u8) !void {
                try context_request.stateSet(self, key, value);
            }

            pub fn body(self: *Context) ![]const u8 {
                return context_request.body(self);
            }

            pub fn text(self: *Context, status: u16, response_body: []const u8) !void {
                try context_response.text(self, status, response_body);
            }

            pub fn textWithHeaders(self: *Context, status: u16, response_body: []const u8, headers: []const backend.Header) !void {
                try context_response.textWithHeaders(self, status, response_body, headers);
            }

            pub fn bytes(self: *Context, status: u16, content_type: []const u8, response_body: []const u8) !void {
                try context_response.bytes(self, status, content_type, response_body);
            }

            pub fn bytesWithHeaders(self: *Context, status: u16, content_type: []const u8, response_body: []const u8, headers: []const backend.Header) !void {
                try context_response.bytesWithHeaders(self, status, content_type, response_body, headers);
            }

            pub fn responseHeader(self: *Context, name: []const u8, value: []const u8) !void {
                try context_response.responseHeader(self, name, value);
            }

            fn stageBytes(self: *Context, status: u16, content_type: []const u8, response_body: []const u8, headers: []const backend.Header) !void {
                try context_response.stageBytes(self, status, content_type, response_body, headers);
            }

            pub fn commitResponse(self: *Context) !void {
                try context_response.commitResponse(self);
            }

            pub fn meteoriteResponse(self: *Context) protocol.MeteoriteResponse {
                return context_response.meteoriteResponse(self);
            }

            pub fn json(self: *Context, status: u16, response_body: []const u8) !void {
                try context_response.json(self, status, response_body);
            }

            pub fn jsonWithHeaders(self: *Context, status: u16, response_body: []const u8, headers: []const backend.Header) !void {
                try context_response.jsonWithHeaders(self, status, response_body, headers);
            }

            pub fn empty(self: *Context, status: u16) !void {
                try context_response.empty(self, status);
            }

            pub fn emptyWithHeaders(self: *Context, status: u16, headers: []const backend.Header) !void {
                try context_response.emptyWithHeaders(self, status, headers);
            }

            pub fn redirect(self: *Context, status: u16, location: []const u8) !void {
                try context_response.redirect(self, status, location);
            }

            pub fn setCookie(self: *Context, buffer: []u8, name: []const u8, value: []const u8, options: protocol.CookieOptions) !backend.Header {
                _ = self;
                return context_response.setCookie(buffer, name, value, options);
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
