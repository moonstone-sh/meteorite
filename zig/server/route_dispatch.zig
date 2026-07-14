const std = @import("std");

pub fn Dispatcher(comptime graph: anytype, comptime build_info: anytype, comptime backend: anytype, comptime Captures: type, comptime matchPath: anytype, comptime matchRoutePathSpecialized: anytype, comptime isLiteralRoute: anytype, comptime dispatchMatchedRoute: anytype) type {
    return struct {
        pub fn dispatch(req_method: graph.Method, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
            if (comptime std.mem.eql(u8, build_info.router_dispatch, "legacy_scan")) {
                return dispatchLegacyScan(req_method, allocator, io, request, req_path);
            }
            switch (req_method) {
                .GET => if (try dispatchRoutes(graph.get_routes, allocator, io, request, req_path)) return true,
                .HEAD => if (try dispatchRoutes(graph.head_routes, allocator, io, request, req_path)) return true,
                .POST => if (try dispatchRoutes(graph.post_routes, allocator, io, request, req_path)) return true,
                .PUT => if (try dispatchRoutes(graph.put_routes, allocator, io, request, req_path)) return true,
                .PATCH => if (try dispatchRoutes(graph.patch_routes, allocator, io, request, req_path)) return true,
                .DELETE => if (try dispatchRoutes(graph.delete_routes, allocator, io, request, req_path)) return true,
                .OPTIONS => if (try dispatchRoutes(graph.options_routes, allocator, io, request, req_path)) return true,
                .OTHER => if (try dispatchRoutes(graph.other_routes, allocator, io, request, req_path)) return true,
                .ALL => {},
            }
            return dispatchRoutes(graph.all_routes, allocator, io, request, req_path);
        }

        fn dispatchLegacyScan(req_method: graph.Method, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
            inline for (graph.routes) |route| {
                if ((route.method == req_method or route.method == .ALL) and try dispatchRouteGeneric(route, allocator, io, request, req_path)) return true;
            }
            return false;
        }

        fn dispatchRoutes(comptime routes: anytype, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
            inline for (routes) |route| {
                if (try dispatchRoute(route, allocator, io, request, req_path)) return true;
            }
            return false;
        }

        fn dispatchRoute(comptime route: graph.Route, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
            if (comptime std.mem.eql(u8, build_info.router_dispatch, "static_fast_path") or std.mem.eql(u8, build_info.router_dispatch, "param_matchers")) {
                return dispatchRouteStaticFast(route, allocator, io, request, req_path);
            }
            return dispatchRouteGeneric(route, allocator, io, request, req_path);
        }

        fn dispatchRouteGeneric(comptime route: graph.Route, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
            var captures = Captures{};
            if (!matchPath(route.path, req_path, route.params, &captures)) return false;
            return dispatchMatchedRoute(route, allocator, io, request, req_path, captures);
        }

        fn dispatchRouteStaticFast(comptime route: graph.Route, allocator: std.mem.Allocator, io: anytype, request: *backend.Request, req_path: []const u8) !bool {
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
    };
}
