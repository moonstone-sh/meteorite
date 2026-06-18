const std = @import("std");

pub const Error = error{ MissingParam, InvalidParam } || std.fmt.ParseIntError;

const VTable = struct {
    method: *const fn (*anyopaque) []const u8,
    path: *const fn (*anyopaque) []const u8,
    param: *const fn (*anyopaque, []const u8) ?[]const u8,
    query: *const fn (*anyopaque, []const u8) ?[]const u8,
    header: *const fn (*anyopaque, []const u8) ?[]const u8,
    body: *const fn (*anyopaque) anyerror![]const u8,
    text: *const fn (*anyopaque, u16, []const u8) anyerror!void,
    bytes: *const fn (*anyopaque, u16, []const u8, []const u8) anyerror!void,
    json: *const fn (*anyopaque, u16, []const u8) anyerror!void,
};

fn VTableFor(comptime RawPtr: type) type {
    return struct {
        fn cast(ptr: *anyopaque) RawPtr { return @ptrCast(@alignCast(ptr)); }
        fn method(ptr: *anyopaque) []const u8 { return @tagName(cast(ptr).method()); }
        fn path(ptr: *anyopaque) []const u8 { return cast(ptr).path(); }
        fn param(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).param(name); }
        fn query(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).query(name); }
        fn header(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).header(name); }
        fn body(ptr: *anyopaque) anyerror![]const u8 { return cast(ptr).body(); }
        fn text(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).text(status, response_body); }
        fn bytes(ptr: *anyopaque, status: u16, content_type: []const u8, response_body: []const u8) anyerror!void { return cast(ptr).bytes(status, content_type, response_body); }
        fn json(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).json(status, response_body); }
        pub const value = VTable{ .method = method, .path = path, .param = param, .query = query, .header = header, .body = body, .text = text, .bytes = bytes, .json = json };
    };
}

fn parseBool(value: []const u8) ?bool {
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1")) return true;
    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0")) return false;
    return null;
}

pub const ctx = struct {
    pub const Params_route_1 = struct {
        };

    pub const Query_route_1 = struct {
        };

    pub const route_1 = struct {
        pub const method_name = "GET";
        pub const route_path = "/";
        params: Params_route_1,
        query: Query_route_1,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_1 {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_1) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_1) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_1, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_1, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_1, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_1) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_1, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_1, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_1, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_route_2 = struct {
        };

    pub const Query_route_2 = struct {
        };

    pub const route_2 = struct {
        pub const method_name = "GET";
        pub const route_path = "/health";
        params: Params_route_2,
        query: Query_route_2,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_2 {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_2) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_2) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_2, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_2, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_2, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_2) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_2, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_2, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_2, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_route_3 = struct {
            id: u64,
        };

    pub const Query_route_3 = struct {
        };

    pub const route_3 = struct {
        pub const method_name = "GET";
        pub const route_path = "/users/:id";
        params: Params_route_3,
        query: Query_route_3,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_3 {
            return .{ .params = .{
                .id = try std.fmt.parseInt(u64, raw.param("id") orelse return error.MissingParam, 10)
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_3) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_3) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_3, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_3, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_3, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_3) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_3, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_3, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_3, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_route_4 = struct {
        };

    pub const Query_route_4 = struct {
        };

    pub const route_4 = struct {
        pub const method_name = "POST";
        pub const route_path = "/echo";
        params: Params_route_4,
        query: Query_route_4,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_4 {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_4) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_4) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_4, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_4, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_4, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_4) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_4, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_4, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_4, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_route_5 = struct {
            device_id: []const u8,
        };

    pub const Query_route_5 = struct {
        };

    pub const route_5 = struct {
        pub const method_name = "GET";
        pub const route_path = "/devices/:device_id";
        params: Params_route_5,
        query: Query_route_5,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_5 {
            return .{ .params = .{
                .device_id = raw.param("device_id") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_5) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_5) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_5, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_5, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_5, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_5) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_5, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_5, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_5, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
};
