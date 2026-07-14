const std = @import("std");

pub fn Negotiator(comptime graph: anytype, comptime backend: anytype, comptime routeMatchesRequestPath: anytype) type {
    return struct {
        const AllowedMethods = struct {
            get: bool = false,
            head: bool = false,
            post: bool = false,
            put: bool = false,
            patch: bool = false,
            delete: bool = false,
            options: bool = false,
        };

        pub fn pathMatchedAnyRoute(req_path: []const u8) bool {
            inline for (graph.routes) |route| {
                if (routeMatchesRequestPath(route, req_path)) return true;
            }
            return false;
        }

        fn allowedMethodsForPath(req_path: []const u8) AllowedMethods {
            var allowed = AllowedMethods{};
            inline for (graph.routes) |route| {
                if (routeMatchesRequestPath(route, req_path)) {
                    switch (route.method) {
                        .GET => {
                            allowed.get = true;
                            allowed.head = true;
                        },
                        .HEAD => allowed.head = true,
                        .POST => allowed.post = true,
                        .PUT => allowed.put = true,
                        .PATCH => allowed.patch = true,
                        .DELETE => allowed.delete = true,
                        .OPTIONS => allowed.options = true,
                        .OTHER => {},
                        .ALL => {
                            allowed.get = true;
                            allowed.head = true;
                            allowed.post = true;
                            allowed.put = true;
                            allowed.patch = true;
                            allowed.delete = true;
                            allowed.options = true;
                        },
                    }
                }
            }
            return allowed;
        }

        fn appendAllowMethod(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, enabled: bool, name: []const u8) !void {
            if (!enabled) return;
            if (list.items.len != 0) try list.appendSlice(allocator, ", ");
            try list.appendSlice(allocator, name);
        }

        pub fn allowHeaderValue(allocator: std.mem.Allocator, req_path: []const u8) ![]const u8 {
            const allowed = allowedMethodsForPath(req_path);
            var list: std.ArrayListUnmanaged(u8) = .empty;
            errdefer list.deinit(allocator);
            try appendAllowMethod(&list, allocator, allowed.get, "GET");
            try appendAllowMethod(&list, allocator, allowed.head, "HEAD");
            try appendAllowMethod(&list, allocator, allowed.post, "POST");
            try appendAllowMethod(&list, allocator, allowed.put, "PUT");
            try appendAllowMethod(&list, allocator, allowed.patch, "PATCH");
            try appendAllowMethod(&list, allocator, allowed.delete, "DELETE");
            try appendAllowMethod(&list, allocator, allowed.options, "OPTIONS");
            return list.toOwnedSlice(allocator);
        }

        pub fn respondMethodNotAllowed(allocator: std.mem.Allocator, request: *backend.Request, req_path: []const u8) !void {
            const allow = try allowHeaderValue(allocator, req_path);
            defer allocator.free(allow);
            return backend.respondTextWithHeaders(request, 405, "method not allowed", &.{.{ .name = "Allow", .value = allow }});
        }

        pub fn respondOptionsPreflight(allocator: std.mem.Allocator, request: *backend.Request, req_path: []const u8) !bool {
            if (!pathMatchedAnyRoute(req_path)) return false;
            const allow = try allowHeaderValue(allocator, req_path);
            defer allocator.free(allow);
            var response_headers: [3]backend.Header = undefined;
            response_headers[0] = .{ .name = "Allow", .value = allow };
            response_headers[1] = .{ .name = "Access-Control-Allow-Origin", .value = "*" };
            response_headers[2] = .{ .name = "Access-Control-Allow-Methods", .value = allow };
            try backend.respondBytesWithHeaders(request, 204, "text/plain; charset=utf-8", "", &response_headers);
            return true;
        }
    };
}
