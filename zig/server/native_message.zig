const std = @import("std");

pub fn NativeMessage(comptime graph: anytype, comptime backend: anytype, comptime bench_stats: anytype, comptime Captures: type, comptime validateParam: anytype, comptime respondValidationError: anytype, comptime dispatchMatchedRoute: anytype, comptime metaJson: anytype, comptime countersJson: anytype) type {
    return struct {
        pub fn dispatch(allocator: std.mem.Allocator, io: anytype, request: *backend.Request, message_name: []const u8) !bool {
            if (std.mem.eql(u8, message_name, "meteorite.bench.meta")) {
                const json = try metaJson(allocator);
                try backend.respondBytes(request, 200, "application/json", json);
                return true;
            }
            if (std.mem.eql(u8, message_name, "meteorite.bench.stats")) {
                const json = try countersJson(allocator);
                try backend.respondBytes(request, 200, "application/json", json);
                return true;
            }
            if (std.mem.eql(u8, message_name, "meteorite.bench.stats.reset")) {
                backend.resetAuditCounters();
                bench_stats.reset();
                try backend.respondText(request, 200, "ok");
                return true;
            }
            inline for (graph.messages) |route| {
                if (try dispatchRoute(route, allocator, io, request, message_name)) return true;
            }
            return false;
        }

        fn dispatchRoute(comptime route: graph.Route, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, message_name: []const u8) !bool {
            const matches_name = std.mem.eql(u8, message_name, route.message.name);
            if (!matches_name) return false;
            var captures = Captures{};
            inline for (route.params) |param| {
                const value = backend.header(request, param.name) orelse {
                    try respondValidationError(request, .{ .domain = "metadata", .field = param.name, .reason = "missing" });
                    return true;
                };
                if (!validateParam(param, value)) {
                    try respondValidationError(request, .{ .domain = "metadata", .field = param.name, .reason = "invalid" });
                    return true;
                }
                if (param.pattern) |pattern| {
                    if (!graph.patterns.match(pattern, value)) {
                        try respondValidationError(request, .{ .domain = "metadata", .field = param.name, .reason = "invalid" });
                        return true;
                    }
                }
                if (!captures.add(param.name, value)) {
                    try backend.respondText(request, 500, "internal server error");
                    return true;
                }
            }
            return dispatchMatchedRoute(route, allocator, io, request, route.raw_path, captures);
        }
    };
}
