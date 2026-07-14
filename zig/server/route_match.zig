const std = @import("std");

pub fn Matcher(comptime graph: anytype, comptime backend: anytype, comptime protocol: anytype, comptime validateParam: anytype) type {
    return struct {
        pub const Method = graph.Method;
        pub const Capture = struct { name: []const u8 = "", value: []const u8 = "" };
        pub const Captures = struct {
            items: [16]Capture = undefined,
            len: usize = 0,

            pub fn add(self: *Captures, name: []const u8, value: []const u8) bool {
                if (self.len >= self.items.len) return false;
                self.items[self.len] = .{ .name = name, .value = value };
                self.len += 1;
                return true;
            }

            pub fn get(self: *const Captures, name: []const u8) ?[]const u8 {
                for (self.items[0..self.len]) |item| {
                    if (std.mem.eql(u8, item.name, name)) return item.value;
                }
                return null;
            }
        };

        pub fn backendMethod(method: backend.Method) Method {
            return switch (method) {
                .GET => .GET,
                .HEAD => .HEAD,
                .POST => .POST,
                .PUT => .PUT,
                .PATCH => .PATCH,
                .DELETE => .DELETE,
                .OPTIONS => .OPTIONS,
                else => .OTHER,
            };
        }

        pub fn backendProtocolMethod(method: backend.Method) protocol.Method {
            return switch (method) {
                .GET => .GET,
                .HEAD => .HEAD,
                .POST => .POST,
                .PUT => .PUT,
                .PATCH => .PATCH,
                .DELETE => .DELETE,
                .OPTIONS => .OPTIONS,
                else => .OTHER,
            };
        }

        pub fn isLiteralRoute(comptime route: graph.Route) bool {
            inline for (route.path) |segment| {
                switch (segment) {
                    .literal => {},
                    .param, .catch_all_param, .wildcard => return false,
                }
            }
            return true;
        }

        pub fn paramSpecFor(comptime params: []const graph.ParamSpec, comptime name: []const u8) graph.ParamSpec {
            inline for (params) |param| {
                if (std.mem.eql(u8, param.name, name)) return param;
            }
            return .{ .name = name };
        }

        pub fn matchPath(comptime route_path: []const graph.Segment, request_path: []const u8, comptime params: []const graph.ParamSpec, captures: *Captures) bool {
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
                    .wildcard => return true,
                }
            }
            return segment_iter.next() == null;
        }

        pub fn matchRoutePathSpecialized(comptime route: graph.Route, request_path: []const u8, captures: *Captures) bool {
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
                    .wildcard => return true,
                }
            }
            return segment_iter.next() == null;
        }
    };
}
