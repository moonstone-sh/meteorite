const std = @import("std");

pub fn Enforcer(comptime graph: anytype, comptime backend: anytype, comptime server_limits: anytype, comptime server_static: anytype) type {
    return struct {
        fn requestTarget(request: *backend.Request) []const u8 {
            if (@hasDecl(backend, "target")) return backend.target(request);
            return backend.path(request);
        }

        pub fn enforceGlobalTargetLimits(request: *backend.Request, req_path: []const u8) !bool {
            const target_value = requestTarget(request);
            const query_value = backend.query(request);
            if (!server_limits.queryEncodingValid(query_value)) {
                try backend.respondText(request, 400, "bad request");
                return false;
            }
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

        pub fn enforceRouteTargetLimits(request: *backend.Request, req_path: []const u8, route: graph.Route) !bool {
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

        pub fn enforceBodyLimit(allocator: std.mem.Allocator, request: *backend.Request, route: graph.Route) !bool {
            if (requestHasChunkedBody(request)) {
                request.close_after_response = true;
                try backend.respondText(request, 501, "chunked request bodies unsupported");
                return false;
            }
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

        fn requestHasChunkedBody(request: *backend.Request) bool {
            const transfer_encoding = backend.header(request, "transfer-encoding") orelse return false;
            return server_static.tokenListContains(transfer_encoding, "chunked");
        }
    };
}
