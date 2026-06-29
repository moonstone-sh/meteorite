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
    pub const Params_health = struct {
        };

    pub const Query_health = struct {
        };

    pub const health = struct {
        pub const method_name = "GET";
        pub const route_path = "/health";
        params: Params_health,
        query: Query_health,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!health {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: health) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: health) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: health, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: health, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: health, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: health) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: health, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: health, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: health, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_get_user = struct {
            id: u64,
        };

    pub const Query_get_user = struct {
        };

    pub const get_user = struct {
        pub const method_name = "GET";
        pub const route_path = "/users/:id";
        params: Params_get_user,
        query: Query_get_user,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!get_user {
            return .{ .params = .{
                .id = try std.fmt.parseInt(u64, raw.param("id") orelse return error.MissingParam, 10)
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: get_user) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: get_user) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: get_user, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: get_user, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: get_user, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: get_user) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: get_user, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: get_user, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: get_user, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_put_user = struct {
            id: u64,
        };

    pub const Query_put_user = struct {
        };

    pub const put_user = struct {
        pub const method_name = "PUT";
        pub const route_path = "/users/:id";
        params: Params_put_user,
        query: Query_put_user,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!put_user {
            return .{ .params = .{
                .id = try std.fmt.parseInt(u64, raw.param("id") orelse return error.MissingParam, 10)
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: put_user) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: put_user) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: put_user, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: put_user, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: put_user, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: put_user) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: put_user, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: put_user, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: put_user, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_patch_user = struct {
            id: u64,
        };

    pub const Query_patch_user = struct {
        };

    pub const patch_user = struct {
        pub const method_name = "PATCH";
        pub const route_path = "/users/:id";
        params: Params_patch_user,
        query: Query_patch_user,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!patch_user {
            return .{ .params = .{
                .id = try std.fmt.parseInt(u64, raw.param("id") orelse return error.MissingParam, 10)
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: patch_user) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: patch_user) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: patch_user, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: patch_user, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: patch_user, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: patch_user) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: patch_user, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: patch_user, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: patch_user, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_delete_user = struct {
            id: u64,
        };

    pub const Query_delete_user = struct {
        };

    pub const delete_user = struct {
        pub const method_name = "DELETE";
        pub const route_path = "/users/:id";
        params: Params_delete_user,
        query: Query_delete_user,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!delete_user {
            return .{ .params = .{
                .id = try std.fmt.parseInt(u64, raw.param("id") orelse return error.MissingParam, 10)
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: delete_user) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: delete_user) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: delete_user, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: delete_user, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: delete_user, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: delete_user) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: delete_user, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: delete_user, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: delete_user, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_echo = struct {
        };

    pub const Query_echo = struct {
        };

    pub const echo = struct {
        pub const method_name = "POST";
        pub const route_path = "/echo";
        params: Params_echo,
        query: Query_echo,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!echo {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: echo) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: echo) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: echo, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: echo, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: echo, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: echo) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: echo, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: echo, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: echo, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_get_device = struct {
            device_id: []const u8,
        };

    pub const Query_get_device = struct {
        };

    pub const get_device = struct {
        pub const method_name = "GET";
        pub const route_path = "/devices/:device_id";
        params: Params_get_device,
        query: Query_get_device,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!get_device {
            return .{ .params = .{
                .device_id = raw.param("device_id") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: get_device) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: get_device) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: get_device, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: get_device, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: get_device, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: get_device) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: get_device, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: get_device, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: get_device, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_file = struct {
            name: []const u8,
        };

    pub const Query_file = struct {
        };

    pub const file = struct {
        pub const method_name = "GET";
        pub const route_path = "/files/:name";
        params: Params_file,
        query: Query_file,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!file {
            return .{ .params = .{
                .name = raw.param("name") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: file) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: file) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: file, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: file, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: file, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: file) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: file, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: file, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: file, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_slug = struct {
            slug: []const u8,
        };

    pub const Query_slug = struct {
        };

    pub const slug = struct {
        pub const method_name = "GET";
        pub const route_path = "/slugs/:slug";
        params: Params_slug,
        query: Query_slug,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!slug {
            return .{ .params = .{
                .slug = raw.param("slug") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: slug) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: slug) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: slug, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: slug, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: slug, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: slug) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: slug, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: slug, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: slug, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_uuid = struct {
            id: []const u8,
        };

    pub const Query_uuid = struct {
        };

    pub const uuid = struct {
        pub const method_name = "GET";
        pub const route_path = "/uuids/:id";
        params: Params_uuid,
        query: Query_uuid,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!uuid {
            return .{ .params = .{
                .id = raw.param("id") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: uuid) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: uuid) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: uuid, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: uuid, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: uuid, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: uuid) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: uuid, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: uuid, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: uuid, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_hex = struct {
            digest: []const u8,
        };

    pub const Query_hex = struct {
        };

    pub const hex = struct {
        pub const method_name = "GET";
        pub const route_path = "/hex/:digest";
        params: Params_hex,
        query: Query_hex,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!hex {
            return .{ .params = .{
                .digest = raw.param("digest") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: hex) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: hex) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: hex, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: hex, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: hex, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: hex) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: hex, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: hex, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: hex, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_email = struct {
            email: []const u8,
        };

    pub const Query_email = struct {
        };

    pub const email = struct {
        pub const method_name = "GET";
        pub const route_path = "/emails/:email";
        params: Params_email,
        query: Query_email,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!email {
            return .{ .params = .{
                .email = raw.param("email") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: email) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: email) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: email, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: email, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: email, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: email) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: email, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: email, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: email, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_token = struct {
            token: []const u8,
        };

    pub const Query_token = struct {
        };

    pub const token = struct {
        pub const method_name = "GET";
        pub const route_path = "/tokens/:token";
        params: Params_token,
        query: Query_token,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!token {
            return .{ .params = .{
                .token = raw.param("token") orelse return error.MissingParam
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: token) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: token) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: token, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: token, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: token, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: token) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: token, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: token, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: token, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_search = struct {
        };

    pub const Query_search = struct {
            exact: ?bool,
            page: ?u64,
            q: []const u8,
        };

    pub const search = struct {
        pub const method_name = "GET";
        pub const route_path = "/search";
        params: Params_search,
        query: Query_search,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!search {
            return .{ .params = .{
            }, .query = .{
                .exact = if (raw.query("exact")) |v| parseBool(v) orelse return error.InvalidParam else null,
                .page = if (raw.query("page")) |v| try std.fmt.parseInt(u64, v, 10) else null,
                .q = raw.query("q") orelse return error.MissingParam
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: search) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: search) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: search, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: search, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: search, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: search) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: search, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: search, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: search, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
    pub const Params_route_15 = struct {
        };

    pub const Query_route_15 = struct {
        };

    pub const route_15 = struct {
        pub const method_name = "GET";
        pub const route_path = "/hybrid-inline";
        params: Params_route_15,
        query: Query_route_15,
        raw: *anyopaque,
        vtable: *const VTable,

        pub fn from(raw: anytype) Error!route_15 {
            return .{ .params = .{
            }, .query = .{
            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };
        }

        pub fn method(self: route_15) []const u8 { return self.vtable.method(self.raw); }
        pub fn path(self: route_15) []const u8 { return self.vtable.path(self.raw); }
        pub fn param(self: route_15, name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }
        pub fn queryValue(self: route_15, name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }
        pub fn header(self: route_15, name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }
        pub fn body(self: route_15) ![]const u8 { return self.vtable.body(self.raw); }
        pub fn text(self: route_15, status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }
        pub fn bytes(self: route_15, status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }
        pub fn json(self: route_15, status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }
    };
};
