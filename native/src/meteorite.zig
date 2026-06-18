const std = @import("std");
const Io = std.Io;

pub const backends = struct {
    pub const std_http = @import("backends/std_http.zig");
};

pub const ListenConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
};

pub const BackendContract = struct {
    pub const Method = enum { GET, POST, OTHER };
};

pub fn DfaMatcher(comptime spec: anytype) type {
    return struct {
        pub fn match(input: []const u8) bool {
            if (@hasField(@TypeOf(spec), "max_input_bytes") and input.len > spec.max_input_bytes) return false;
            var state: u16 = spec.start_state;
            for (input) |byte| {
                const class = spec.class_map[byte];
                const idx: usize = @as(usize, state) * spec.class_count + class;
                state = spec.transition_table[idx];
                if (state == spec.dead_state) return false;
            }
            return spec.accept_table[state];
        }
    };
}

pub const patterns = struct {
    pub fn Dfa(comptime spec: anytype) type {
        return DfaMatcher(spec);
    }
};

pub fn compile(comptime spec: anytype) type {
    return struct {
        const graph = spec.graph;
        const backend = spec.backend;
        const graph_requires_lua = graphRequiresLua();
        const inline_lua_handlers = countHandlers(.inline_lua);
        const zig_handlers = countZigHandlers();

        pub fn run(io: Io) !void {
            try serve(io, .{});
        }

        pub fn serve(io: Io, config: ListenConfig) !void {
            var server = try backend.listen(.{ .host = config.host, .port = config.port, .io = io });
            defer server.deinit();

            std.debug.print("Meteorite build\n  mode: {s}\n  backend: std.http\n  Lua runtime: {s}\n  Lua state: single_locked\n  workers: auto\n  inline Lua handlers: {d}\n  Zig handlers: {d}\n  routes: {d}\n  artifact: dist/server\nListening: http://{s}:{d}\n", .{
                if (graph_requires_lua) "hybrid" else "static",
                if (graph_requires_lua) "included" else "removed",
                inline_lua_handlers,
                zig_handlers,
                graph.routes.len,
                config.host,
                config.port,
            });

            while (true) {
                var request: backend.Request = undefined;
                backend.accept(&server, &request) catch |err| switch (err) {
                    error.HttpConnectionClosing => continue,
                    else => {
                        std.debug.print("accept failed: {s}\n", .{@errorName(err)});
                        continue;
                    },
                };
                defer request.close(io);
                var arena_buffer: [graph.max_request_arena_bytes]u8 = undefined;
                var arena_state = std.heap.FixedBufferAllocator.init(&arena_buffer);
                const arena = arena_state.allocator();
                serveRequest(arena, &request) catch |err| {
                    std.debug.print("request failed for {s}: {s}\n", .{ backend.path(&request), @errorName(err) });
                };
            }
        }

        fn serveRequest(allocator: std.mem.Allocator, request: *backend.Request) !void {
            const req_method = backendMethod(backend.method(request));
            const req_path = backend.path(request);
            var path_matched = false;

            inline for (graph.routes) |route| {
                var captures = Captures{};
                if (matchPath(route.path, req_path, route.params, &captures)) {
                    path_matched = true;
                    if (route.method == req_method) {
                        if (!matchQuery(route.query, request)) return backend.respondText(request, 404, "not found");
                        var ctx = Context{ .allocator = allocator, .request = request, .captures = captures, .route = route };
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
                try backend.respondText(self.request, status, response_body);
            }

            pub fn bytes(self: *Context, status: u16, content_type: []const u8, response_body: []const u8) !void {
                try backend.respondBytes(self.request, status, content_type, response_body);
            }

            pub fn json(self: *Context, status: u16, response_body: []const u8) !void {
                try self.bytes(status, "application/json", response_body);
            }
        };
    };
}
