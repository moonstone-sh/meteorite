const std = @import("std");
const graph = @import("meteorite_graph");
const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

pub const LuaRuntimeUnavailable = struct {
    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        _ = handler;
        try ctx.text(501, "handler requires Lua runtime");
    }
};

pub const HybridContract = struct {
    pub const RequestLocalState = struct {
        allocator: std.mem.Allocator,
    };
};

const VTable = struct {
    text: *const fn (ctx: *anyopaque, status: u16, body: []const u8) anyerror!void,
    json: *const fn (ctx: *anyopaque, status: u16, body: []const u8) anyerror!void,
    bytes: *const fn (ctx: *anyopaque, status: u16, content_type: []const u8, body: []const u8) anyerror!void,
    body: *const fn (ctx: *anyopaque) anyerror![]const u8,
    param: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    query: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    header: *const fn (ctx: *anyopaque, name: []const u8) ?[]const u8,
    allocator: *const fn (ctx: *anyopaque) std.mem.Allocator,
    io: *const fn (ctx: *anyopaque) std.Io,
    run: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, argv: []const []const u8) anyerror![]const u8,
};

fn makeVTable(comptime Ctx: type) VTable {
    return .{
        .text = struct {
            fn f(ptr: *anyopaque, status: u16, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.text(status, body);
            }
        }.f,
        .json = struct {
            fn f(ptr: *anyopaque, status: u16, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.json(status, body);
            }
        }.f,
        .bytes = struct {
            fn f(ptr: *anyopaque, status: u16, content_type: []const u8, body: []const u8) !void {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.bytes(status, content_type, body);
            }
        }.f,
        .body = struct {
            fn f(ptr: *anyopaque) ![]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.body();
            }
        }.f,
        .param = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.param(name);
            }
        }.f,
        .query = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.query(name);
            }
        }.f,
        .header = struct {
            fn f(ptr: *anyopaque, name: []const u8) ?[]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.header(name);
            }
        }.f,
        .allocator = struct {
            fn f(ptr: *anyopaque) std.mem.Allocator {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.allocator;
            }
        }.f,
        .io = struct {
            fn f(ptr: *anyopaque) std.Io {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.io;
            }
        }.f,
        .run = struct {
            fn f(ptr: *anyopaque, allocator: std.mem.Allocator, argv: []const []const u8) anyerror![]const u8 {
                const typed: *Ctx = @ptrCast(@alignCast(ptr));
                return typed.run(allocator, argv);
            }
        }.f,
    };
}

fn globalVtable(comptime Ctx: type) *const VTable {
    const static = comptime makeVTable(Ctx);
    return &static;
}

threadlocal var current_ctx: ?*anyopaque = null;
threadlocal var current_vtable: ?*const VTable = null;

fn upvalueIndex(i: c_int) c_int {
    return c.LUA_REGISTRYINDEX - i;
}

const HttpClient = struct {
    base_url: []const u8,
    timeout_ms: u32,
    max_response_bytes: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, base_url: []const u8, timeout_ms: u32, max_response_bytes: usize) HttpClient {
        return .{ .allocator = allocator, .base_url = base_url, .timeout_ms = timeout_ms, .max_response_bytes = max_response_bytes };
    }

    fn request(self: HttpClient, method: []const u8, path: []const u8, body: ?[]const u8, content_type: ?[]const u8, auth_header: ?[]const u8) !HttpResponse {
        const url = try std.fs.path.join(self.allocator, &.{ self.base_url, path });
        defer self.allocator.free(url);

        const ctx = current_ctx.?;
        const vtable = current_vtable.?;

        var args = std.ArrayListUnmanaged([]const u8).empty;
        defer {
            for (args.items) |arg| self.allocator.free(arg);
            args.deinit(self.allocator);
        }
        try args.appendSlice(self.allocator, &.{ "curl", "-s", "-i", "-X", method, "--max-time", "30" });

        var tmp_headers: ?[]const u8 = null;
        var tmp_body: ?[]const u8 = null;
        var tmp_req_body: ?[]const u8 = null;
        defer {
            const io = vtable.io(ctx);
            if (tmp_headers) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
            if (tmp_body) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
            if (tmp_req_body) |p| { std.Io.Dir.cwd().deleteFile(io, p) catch {}; self.allocator.free(p); }
        }

        tmp_headers = try self.tempFile(vtable.io(ctx), "mt-hdr-");
        tmp_body = try self.tempFile(vtable.io(ctx), "mt-body-");
        try args.appendSlice(self.allocator, &.{ "-D", tmp_headers.?, "-o", tmp_body.? });

        if (body) |b| {
            tmp_req_body = try self.tempFile(vtable.io(ctx), "mt-req-");
            const f = try std.Io.Dir.cwd().createFile(vtable.io(ctx), tmp_req_body.?, .{});
            defer f.close(vtable.io(ctx));
            try f.writeStreamingAll(vtable.io(ctx), b);
            try args.appendSlice(self.allocator, &.{
                "-d",
                try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_req_body.?}),
            });
        }

        if (content_type) |ct| {
            try args.appendSlice(self.allocator, &.{
                "-H",
                try std.fmt.allocPrint(self.allocator, "content-type: {s}", .{ct}),
            });
        }
        if (auth_header) |ah| {
            try args.appendSlice(self.allocator, &.{
                "-H",
                try std.fmt.allocPrint(self.allocator, "authorization: {s}", .{ah}),
            });
        }
        try args.append(self.allocator, url);

        const output = try vtable.run(ctx, self.allocator, args.items);
        defer self.allocator.free(output);

        const headers_raw = try self.readFile(vtable.io(ctx), tmp_headers.?);
        defer self.allocator.free(headers_raw);
        const status_line = extractStatus(headers_raw);
        const headers = try self.parseHeaders(headers_raw);
        errdefer self.allocator.free(headers);

        const body_out = try self.readFile(vtable.io(ctx), tmp_body.?);
        errdefer self.allocator.free(body_out);
        if (body_out.len > self.max_response_bytes) {
            self.allocator.free(body_out);
            self.allocator.free(headers);
            return error.ResponseTooLarge;
        }

        return .{
            .allocator = self.allocator,
            .status = status_line,
            .headers = headers,
            .body = body_out,
        };
    }

    fn tempFile(self: HttpClient, io: std.Io, prefix: []const u8) ![]const u8 {
        var buf: [64]u8 = undefined;
        var random_bytes: [8]u8 = undefined;
        io.random(&random_bytes);
        const hex = std.fmt.bytesToHex(random_bytes, .lower);
        const name = try std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, &hex });
        const file = try std.Io.Dir.cwd().createFile(io, name, .{});
        file.close(io);
        return try self.allocator.dupe(u8, name);
    }

    fn readFile(self: HttpClient, io: std.Io, path: []const u8) ![]const u8 {
        return try std.Io.Dir.cwd().readFileAlloc(io, path, self.allocator, std.Io.Limit.limited(self.max_response_bytes + 1));
    }

    fn parseHeaders(self: HttpClient, raw: []const u8) ![]const u8 {
        var lines = std.mem.splitAny(u8, raw, "\r\n");
        var list: std.ArrayListUnmanaged(u8) = .empty;
        defer list.deinit(self.allocator);
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (idx == 0) continue;
            const name = line[0..idx];
            const value = if (idx + 1 < line.len) std.mem.trim(u8, line[idx + 1 ..], " ") else "";
            try list.appendSlice(self.allocator, "\"");
            try encodeJsonString(name, &list, self.allocator);
            try list.appendSlice(self.allocator, "\":\"");
            try encodeJsonString(value, &list, self.allocator);
            try list.appendSlice(self.allocator, "\",");
        }
        return list.toOwnedSlice(self.allocator);
    }
};

const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status: u16,
    headers: []const u8,
    body: []const u8,

    fn pushToLua(self: HttpResponse, L: ?*c.lua_State) void {
        c.lua_newtable(L);
        c.lua_pushinteger(L, self.status);
        c.lua_setfield(L, -2, "status");
        const trimmed = std.mem.trim(u8, self.headers, ",");
        const headers_json = std.fmt.allocPrint(self.allocator, "{{{s}}}", .{trimmed}) catch "{}";
        defer self.allocator.free(headers_json);
        _ = c.lua_pushlstring(L, headers_json.ptr, headers_json.len);
        c.lua_setfield(L, -2, "headers");
        _ = c.lua_pushlstring(L, self.body.ptr, self.body.len);
        c.lua_setfield(L, -2, "body");
    }
};

fn extractStatus(raw: []const u8) u16 {
    var lines = std.mem.splitAny(u8, raw, "\r\n");
    const first = lines.next() orelse return 0;
    if (first.len < 12) return 0;
    const code = std.fmt.parseInt(u16, first[9..12], 10) catch return 0;
    return code;
}

pub const HybridLuaRuntime = struct {
    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state", .{});
            return error.LuaOutOfMemory;
        };
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        const setup = "package.path = '.moonstone/env/share/lua/5.4/?.lua;.moonstone/env/share/lua/5.4/?/init.lua;' .. package.path";
        if (c.luaL_loadstring(L, setup.ptr) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("lua setup load failed: {s}", .{err});
            return error.LuaLoadFailed;
        }
        if (c.lua_pcallk(L, 0, 0, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("lua setup failed: {s}", .{err});
            return error.LuaRuntimeError;
        }

        if (c.luaL_loadfilex(L, @ptrCast(handler.path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("load handler {s}: {s}", .{ handler.path, err });
            return error.LuaLoadFailed;
        }
        if (c.lua_pcallk(L, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("init handler {s}: {s}", .{ handler.path, err });
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("handler {s} did not return a function", .{handler.path});
            return error.LuaHandlerInvalid;
        }

        c.lua_newtable(L);
        pushMethod(L, "text", l_text);
        pushMethod(L, "json", l_json);
        pushMethod(L, "bytes", l_bytes);
        pushMethod(L, "body", l_body);
        pushMethod(L, "param", l_param);
        pushMethod(L, "query", l_query);
        pushMethod(L, "header", l_header);
        pushMethod(L, "http", l_http);
        pushMethod(L, "auth", l_auth);
        pushMethod(L, "zig", l_zig);
        pushMethod(L, "get", l_get);
        pushMethod(L, "set", l_set);

        if (@hasField(@TypeOf(ctx.*), "captures")) {
            c.lua_newtable(L);
            const captures = ctx.captures;
            for (captures.items[0..captures.len]) |item| {
                _ = c.lua_pushlstring(L, @ptrCast(item.value.ptr), item.value.len);
                c.lua_setfield(L, -2, @ptrCast(item.name.ptr));
            }
            c.lua_setfield(L, -2, "params");
        }

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query")) {
            c.lua_newtable(L);
            const query_specs = ctx.route.query;
            for (query_specs) |spec| {
                if (vtable.query(ctx, spec.name)) |value| {
                    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                    c.lua_setfield(L, -2, @ptrCast(spec.name.ptr));
                }
            }
            c.lua_setfield(L, -2, "query");
        }

        c.lua_newtable(L);
        c.lua_setfield(L, -2, "state");

        current_ctx = ctx;
        current_vtable = vtable;
        defer {
            current_ctx = null;
            current_vtable = null;
        }

        if (c.lua_pcallk(L, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("handler {s}: {s}", .{ handler.path, err });
            return error.LuaRuntimeError;
        }

        if (c.lua_istable(L, -1)) {
            _ = c.lua_getfield(L, -1, "status");
            const status: u16 = if (c.lua_isinteger(L, -1) != 0) @intCast(c.lua_tointegerx(L, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L, 1);

            _ = c.lua_getfield(L, -1, "content_type");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L, -1, &content_type_len);
            const is_json = content_type_ptr != null and std.mem.eql(u8, content_type_ptr[0..content_type_len], "application/json");
            c.lua_pop(L, 1);

            _ = c.lua_getfield(L, -1, "body");
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (is_json) {
                try current_vtable.?.json(current_ctx.?, status, body);
            } else {
                try current_vtable.?.text(current_ctx.?, status, body);
            }
            c.lua_pop(L, 2);
        } else if (c.lua_isstring(L, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, -1, &len);
            try current_vtable.?.text(current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L, 1);
        } else {
            try current_vtable.?.text(current_ctx.?, 204, "");
            c.lua_pop(L, 1);
        }
    }
};

pub fn pushMethod(L: ?*c.lua_State, name: [*c]const u8, func: c.lua_CFunction) void {
    c.lua_pushcfunction(L, func);
    c.lua_setfield(L, -2, name);
}

fn l_text(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    var body_arg: c_int = 2;
    if (nargs >= 3 and c.lua_isinteger(L, 2) != 0) {
        status = @intCast(c.lua_tointegerx(L, 2, @as([*c]c_int, null)));
        body_arg = 3;
    } else if (nargs < 2) {
        return pushResponse(L, status, "text/plain; charset=utf-8", "");
    }
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return pushResponse(L, status, "text/plain; charset=utf-8", body_ptr[0..body_len]);
}

fn l_json(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = current_vtable.?;
    const ctx = current_ctx.?;
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    var value_idx: c_int = 2;
    if (nargs >= 3 and c.lua_isinteger(L, 2) != 0) {
        status = @intCast(c.lua_tointegerx(L, 2, @as([*c]c_int, null)));
        value_idx = 3;
    } else if (nargs < 2) {
        return pushResponse(L, status, "application/json", "{}");
    }

    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(rt.allocator(ctx));
    encodeLuaValue(L, value_idx, &list, rt.allocator(ctx)) catch |err| {
        std.log.err("json encode failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "json encode failed");
        unreachable;
    };

    return pushResponse(L, status, "application/json", list.items);
}

fn l_bytes(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    var content_type_arg: c_int = 2;
    var body_arg: c_int = 3;
    if (nargs >= 4 and c.lua_isinteger(L, 2) != 0) {
        status = @intCast(c.lua_tointegerx(L, 2, @as([*c]c_int, null)));
        content_type_arg = 3;
        body_arg = 4;
    } else if (nargs < 3) {
        return pushResponse(L, status, "application/octet-stream", "");
    }
    var ct_len: usize = 0;
    const ct_ptr = c.lua_tolstring(L, content_type_arg, &ct_len);
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return pushResponse(L, status, ct_ptr[0..ct_len], body_ptr[0..body_len]);
}

fn l_body(L: ?*c.lua_State) callconv(.c) c_int {
    const body = current_vtable.?.body(current_ctx.?) catch |err| {
        std.log.err("body read failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "body read failed");
        unreachable;
    };
    _ = c.lua_pushlstring(L, @ptrCast(body.ptr), body.len);
    return 1;
}

fn l_param(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (current_vtable.?.param(current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

fn l_query(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (current_vtable.?.query(current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

fn l_header(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (current_vtable.?.header(current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

fn l_http(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (name == null) {
        _ = c.luaL_error(L, "http capability name required");
        unreachable;
    }
    const cap_name = std.mem.span(name);
    const ctx = current_ctx.?;
    const vtable = current_vtable.?;
    const allocator = vtable.allocator(ctx);

    const base_url = getCapabilityString("http", cap_name, "base_url") orelse {
        _ = c.luaL_error(L, "http capability missing base_url");
        unreachable;
    };
    const timeout_ms = getCapabilityInt("http", cap_name, "timeout_ms") orelse 1500;
    const max_response_bytes = getCapabilityInt("http", cap_name, "max_response_bytes") orelse 65536;

    const client = allocator.create(HttpClient) catch {
        _ = c.luaL_error(L, "out of memory");
        unreachable;
    };
    client.* = HttpClient.init(allocator, base_url, @intCast(timeout_ms), @intCast(max_response_bytes));

    c.lua_newtable(L);
    pushHttpClosure(L, client, "get", "GET");
    pushHttpClosure(L, client, "post", "POST");
    pushHttpClosure(L, client, "put", "PUT");
    pushHttpClosure(L, client, "delete", "DELETE");
    return 1;
}

fn pushHttpClosure(L: ?*c.lua_State, client: *HttpClient, lua_name: []const u8, method: []const u8) void {
    c.lua_pushlightuserdata(L, @ptrCast(client));
    _ = c.lua_pushlstring(L, method.ptr, method.len);
    c.lua_pushcclosure(L, l_http_request, 2);
    _ = c.lua_pushlstring(L, lua_name.ptr, lua_name.len);
    c.lua_rawset(L, -3);
}

fn l_http_request(L: ?*c.lua_State) callconv(.c) c_int {
    const client_ptr = @as(*HttpClient, @ptrCast(@alignCast(c.lua_touserdata(L, upvalueIndex(1)))));
    var method_len: usize = 0;
    const method_ptr = c.lua_tolstring(L, upvalueIndex(2), &method_len);
    const method = method_ptr[0..method_len];

    const vtable = current_vtable.?;
    const ctx = current_ctx.?;
    const allocator = vtable.allocator(ctx);

    const path_ptr = c.lua_tolstring(L, 2, null) orelse {
        _ = c.luaL_error(L, "path required");
        unreachable;
    };
    const path = std.mem.span(path_ptr);

    var body: ?[]const u8 = null;
    var content_type: ?[]const u8 = null;
    var auth_header: ?[]const u8 = null;

    if (c.lua_gettop(L) >= 3 and c.lua_istable(L, 3)) {
        _ = c.lua_getfield(L, 3, "body");
        if (c.lua_istable(L, -1)) {
            var list: std.ArrayListUnmanaged(u8) = .empty;
            defer list.deinit(allocator);
            encodeLuaValue(L, -1, &list, allocator) catch {
                _ = c.luaL_error(L, "body encode failed");
                unreachable;
            };
            body = allocator.dupe(u8, list.items) catch {
                _ = c.luaL_error(L, "out of memory");
                unreachable;
            };
            content_type = "application/json";
        } else if (c.lua_isstring(L, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, -1, &len);
            body = allocator.dupe(u8, ptr[0..len]) catch {
                _ = c.luaL_error(L, "out of memory");
                unreachable;
            };
        }
        c.lua_pop(L, 1);

        _ = c.lua_getfield(L, 3, "headers");
        if (c.lua_istable(L, -1)) {
            _ = c.lua_getfield(L, -1, "authorization");
            if (c.lua_isstring(L, -1) != 0) {
                var len: usize = 0;
                const ptr = c.lua_tolstring(L, -1, &len);
                auth_header = allocator.dupe(u8, ptr[0..len]) catch {
                    _ = c.luaL_error(L, "out of memory");
                    unreachable;
                };
            }
            c.lua_pop(L, 1);
        }
        c.lua_pop(L, 1);
    }
    defer {
        if (body) |b| allocator.free(b);
        if (auth_header) |h| allocator.free(h);
    }

    var response = client_ptr.request(method, path, body, content_type, auth_header) catch |err| {
        std.log.err("http request failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "http request failed");
        unreachable;
    };
    response.pushToLua(L);
    return 1;
}

fn l_auth(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (name == null) {
        _ = c.luaL_error(L, "auth capability name required");
        unreachable;
    }
    const cap_name = std.mem.span(name);

    const audience = getCapabilityString("auth", cap_name, "audience") orelse cap_name;
    const ctx = current_ctx.?;
    const vtable = current_vtable.?;
    const allocator = vtable.allocator(ctx);

    const token = std.fmt.allocPrint(allocator, "Bearer demo-token-for-{s}", .{audience}) catch {
        _ = c.luaL_error(L, "out of memory");
        unreachable;
    };
    defer allocator.free(token);

    c.lua_newtable(L);
    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_setfield(L, -2, "bearer");

    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_pushcclosure(L, l_auth_headers, 1);
    c.lua_setfield(L, -2, "headers");

    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_pushcclosure(L, l_auth_authorization, 1);
    c.lua_setfield(L, -2, "authorization");

    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_pushcclosure(L, l_auth_authorization, 1);
    c.lua_setfield(L, -2, "refresh");

    return 1;
}

fn l_auth_headers(L: ?*c.lua_State) callconv(.c) c_int {
    var len: usize = 0;
    const token_ptr = c.lua_tolstring(L, upvalueIndex(1), &len);
    const token = token_ptr[0..len];
    c.lua_newtable(L);
    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_setfield(L, -2, "authorization");
    return 1;
}

fn l_auth_authorization(L: ?*c.lua_State) callconv(.c) c_int {
    var len: usize = 0;
    const token_ptr = c.lua_tolstring(L, upvalueIndex(1), &len);
    const token = token_ptr[0..len];
    _ = c.lua_pushlstring(L, token.ptr, token.len);
    return 1;
}

fn l_zig(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (name == null) {
        _ = c.luaL_error(L, "zig capability name required");
        unreachable;
    }
    const cap_name = std.mem.span(name);
    _ = getCapabilityString("zig", cap_name, "path") orelse {
        _ = c.luaL_error(L, "zig capability missing path");
        unreachable;
    };

    c.lua_newtable(L);
    c.lua_pushcfunction(L, l_zig_device_name);
    c.lua_setfield(L, -2, "device_name");
    return 1;
}

fn l_zig_device_name(L: ?*c.lua_State) callconv(.c) c_int {
    const device_id_ptr = c.lua_tolstring(L, 2, null);
    const device_id = if (device_id_ptr) |p| std.mem.span(p) else "";
    const vtable = current_vtable.?;
    const ctx = current_ctx.?;
    const allocator = vtable.allocator(ctx);
    const result = std.fmt.allocPrint(allocator, "device:{s}", .{device_id}) catch {
        _ = c.luaL_error(L, "out of memory");
        unreachable;
    };
    defer allocator.free(result);
    _ = c.lua_pushlstring(L, result.ptr, result.len);
    return 1;
}

fn l_get(L: ?*c.lua_State) callconv(.c) c_int {
    const key = c.lua_tolstring(L, 2, null);
    _ = c.lua_getfield(L, 1, "state");
    _ = c.lua_getfield(L, -1, key);
    c.lua_remove(L, -2);
    return 1;
}

fn l_set(L: ?*c.lua_State) callconv(.c) c_int {
    const key = c.lua_tolstring(L, 2, null);
    _ = c.lua_getfield(L, 1, "state");
    c.lua_pushvalue(L, 3);
    c.lua_setfield(L, -2, key);
    c.lua_pop(L, 1);
    return 1;
}

fn setClosure(L: ?*c.lua_State, name: [*c]const u8, func: c.lua_CFunction) void {
    c.lua_pushcfunction(L, func);
    c.lua_setfield(L, -2, name);
}

fn pushResponse(L: ?*c.lua_State, status: u16, content_type: []const u8, body: []const u8) c_int {
    c.lua_newtable(L);
    c.lua_pushinteger(L, status);
    c.lua_setfield(L, -2, "status");
    _ = c.lua_pushlstring(L, @ptrCast(content_type.ptr), content_type.len);
    c.lua_setfield(L, -2, "content_type");
    _ = c.lua_pushlstring(L, @ptrCast(body.ptr), body.len);
    c.lua_setfield(L, -2, "body");
    return 1;
}

fn getCapabilityString(kind: []const u8, name: []const u8, comptime field: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, kind, "http")) return lookupString(graph.capabilities.http, name, field);
    if (std.mem.eql(u8, kind, "auth")) return lookupString(graph.capabilities.auth, name, field);
    if (std.mem.eql(u8, kind, "zig")) {
        const value = lookupZig(graph.capabilities.zig, name) orelse return null;
        if (std.mem.eql(u8, field, "path")) return value;
    }
    return null;
}

fn getCapabilityInt(kind: []const u8, name: []const u8, comptime field: []const u8) ?i64 {
    if (std.mem.eql(u8, kind, "http")) return lookupInt(graph.capabilities.http, name, field);
    if (std.mem.eql(u8, kind, "auth")) return lookupInt(graph.capabilities.auth, name, field);
    return null;
}

fn lookupString(comptime T: type, name: []const u8, comptime field: []const u8) ?[]const u8 {
    const decls = comptime std.meta.declarations(T);
    inline for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) {
            const cap = @field(T, decl.name);
            const CapType = @TypeOf(cap);
            const info = @typeInfo(CapType);
            if (info == .pointer or info == .array) {
                return cap;
            }
            if (@hasField(CapType, field)) {
                return @field(cap, field);
            }
            return null;
        }
    }
    return null;
}

fn lookupInt(comptime T: type, name: []const u8, comptime field: []const u8) ?i64 {
    const decls = comptime std.meta.declarations(T);
    inline for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) {
            const cap = @field(T, decl.name);
            const CapType = @TypeOf(cap);
            if (@hasField(CapType, field)) {
                return @intCast(@field(cap, field));
            }
            return null;
        }
    }
    return null;
}

fn lookupZig(comptime T: type, name: []const u8) ?[]const u8 {
    const decls = comptime std.meta.declarations(T);
    inline for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) {
            const cap = @field(T, decl.name);
            return cap;
        }
    }
    return null;
}

fn encodeLuaValue(L: ?*c.lua_State, idx: c_int, list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    const t = c.lua_type(L, idx);
    switch (t) {
        c.LUA_TNIL => try list.appendSlice(allocator, "null"),
        c.LUA_TBOOLEAN => try list.appendSlice(allocator, if (c.lua_toboolean(L, idx) != 0) "true" else "false"),
        c.LUA_TNUMBER => {
            const buf = if (c.lua_isinteger(L, idx) != 0)
                try std.fmt.allocPrint(allocator, "{d}", .{c.lua_tointegerx(L, idx, @as([*c]c_int, null))})
            else
                try std.fmt.allocPrint(allocator, "{d}", .{c.lua_tonumberx(L, idx, @as([*c]c_int, null))});
            defer allocator.free(buf);
            try list.appendSlice(allocator, buf);
        },
        c.LUA_TSTRING => {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, idx, &len);
            try list.appendSlice(allocator, "\"");
            try encodeJsonString(ptr[0..len], list, allocator);
            try list.appendSlice(allocator, "\"");
        },
        c.LUA_TTABLE => {
            const len = c.lua_rawlen(L, idx);
            if (len > 0) {
                try list.appendSlice(allocator, "[");
                var i: usize = 1;
                while (i <= len) : (i += 1) {
                    if (i > 1) try list.appendSlice(allocator, ",");
                    c.lua_pushinteger(L, @intCast(i));
                    _ = c.lua_gettable(L, idx);
                    try encodeLuaValue(L, -1, list, allocator);
                    c.lua_pop(L, 1);
                }
                try list.appendSlice(allocator, "]");
            } else {
                try list.appendSlice(allocator, "{");
                var first = true;
                c.lua_pushnil(L);
                while (c.lua_next(L, idx) != 0) {
                    if (!first) try list.appendSlice(allocator, ",");
                    first = false;
                    var key_len: usize = 0;
                    const key_ptr = c.lua_tolstring(L, -2, &key_len);
                    try list.appendSlice(allocator, "\"");
                    try encodeJsonString(key_ptr[0..key_len], list, allocator);
                    try list.appendSlice(allocator, "\":");
                    try encodeLuaValue(L, -1, list, allocator);
                    c.lua_pop(L, 1);
                }
                try list.appendSlice(allocator, "}");
            }
        },
        else => try list.appendSlice(allocator, "null"),
    }
}

fn encodeJsonString(s: []const u8, list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    for (s) |ch| {
        switch (ch) {
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '"' => try list.appendSlice(allocator, "\\\""),
            0...31 => {
                const buf = try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{ch});
                defer allocator.free(buf);
                try list.appendSlice(allocator, buf);
            },
            else => try list.append(allocator, ch),
        }
    }
}


// ============================================================
// CachedHybridRuntime: single Lua state, preloaded inline handlers.
// ============================================================
const graph_cached = @import("meteorite_graph");

fn inlineLuaRouteCount() usize {
    comptime var count: usize = 0;
    inline for (graph_cached.routes) |route| {
        if (route.handler == .inline_lua) count += 1;
    }
    return count;
}

fn routeIndexCached(comptime route_id: []const u8) usize {
    comptime var count: usize = 0;
    inline for (graph_cached.routes) |route| {
        if (route.handler == .inline_lua) {
            if (std.mem.eql(u8, route.id, route_id)) {
                return count;
            }
            count += 1;
        }
    }
    @compileError("unknown inline Lua route: " ++ route_id);
}

pub const CachedHybridRuntime = struct {
    threadlocal var L: ?*c.lua_State = null;
    threadlocal var refs: [inlineLuaRouteCount()]c_int = undefined;
    threadlocal var initialized: bool = false;

    fn init() !void {
        if (initialized) return;
        L = c.luaL_newstate() orelse {
            std.log.err("failed to create cached Lua state", .{});
            return error.LuaOutOfMemory;
        };
        c.luaL_openlibs(L.?);

        const setup = "package.path = '.moonstone/env/share/lua/5.4/?.lua;.moonstone/env/share/lua/5.4/?/init.lua;' .. package.path";
        if (c.luaL_loadstring(L.?, setup.ptr) != c.LUA_OK) {
            std.log.err("cached lua setup load failed: {s}", .{c.lua_tolstring(L.?, -1, null)});
            return error.LuaLoadFailed;
        }
        if (c.lua_pcallk(L.?, 0, 0, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("cached lua setup failed: {s}", .{c.lua_tolstring(L.?, -1, null)});
            return error.LuaRuntimeError;
        }

        comptime var idx: usize = 0;
        inline for (graph_cached.routes) |route| {
            if (route.handler == .inline_lua) {
                const handler = route.handler.inline_lua;
                if (c.luaL_loadfilex(L.?, @ptrCast(handler.chunk_path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
                    std.log.err("cached load handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
                    return error.LuaLoadFailed;
                }
                if (c.lua_pcallk(L.?, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
                    std.log.err("cached init handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
                    return error.LuaRuntimeError;
                }
                if (!c.lua_isfunction(L.?, -1)) {
                    std.log.err("cached handler {s} did not return a function", .{handler.chunk_path});
                    return error.LuaHandlerInvalid;
                }
                refs[idx] = c.luaL_ref(L.?, c.LUA_REGISTRYINDEX);
                idx += 1;
            }
        }
        initialized = true;
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        const L2 = L.?;

        const idx = comptime routeIndexCached(handler.id);
        _ = c.lua_rawgeti(L2, c.LUA_REGISTRYINDEX, refs[idx]);

        c.lua_newtable(L2);
        pushMethod(L2, "text", l_text);
        pushMethod(L2, "json", l_json);
        pushMethod(L2, "bytes", l_bytes);
        pushMethod(L2, "body", l_body);
        pushMethod(L2, "param", l_param);
        pushMethod(L2, "query", l_query);
        pushMethod(L2, "header", l_header);
        pushMethod(L2, "http", l_http);
        pushMethod(L2, "auth", l_auth);
        pushMethod(L2, "zig", l_zig);
        pushMethod(L2, "get", l_get);
        pushMethod(L2, "set", l_set);

        if (@hasField(@TypeOf(ctx.*), "captures")) {
            c.lua_newtable(L2);
            const captures = ctx.captures;
            for (captures.items[0..captures.len]) |item| {
                _ = c.lua_pushlstring(L2, @ptrCast(item.value.ptr), item.value.len);
                c.lua_setfield(L2, -2, @ptrCast(item.name.ptr));
            }
            c.lua_setfield(L2, -2, "params");
        }

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query")) {
            c.lua_newtable(L2);
            const query_specs = ctx.route.query;
            for (query_specs) |spec| {
                if (vtable.query(ctx, spec.name)) |value| {
                    _ = c.lua_pushlstring(L2, @ptrCast(value.ptr), value.len);
                    c.lua_setfield(L2, -2, @ptrCast(spec.name.ptr));
                }
            }
            c.lua_setfield(L2, -2, "query");
        }

        c.lua_newtable(L2);
        c.lua_setfield(L2, -2, "state");

        current_ctx = ctx;
        current_vtable = vtable;
        defer {
            current_ctx = null;
            current_vtable = null;
        }

        if (c.lua_pcallk(L2, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L2, -1, null);
            std.log.err("cached handler {s}: {s}", .{ handler.id, err });
            return error.LuaRuntimeError;
        }

        if (c.lua_istable(L2, -1)) {
            _ = c.lua_getfield(L2, -1, "status");
            const status: u16 = if (c.lua_isinteger(L2, -1) != 0) @intCast(c.lua_tointegerx(L2, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L2, 1);

            _ = c.lua_getfield(L2, -1, "content_type");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L2, -1, &content_type_len);
            const is_json = content_type_ptr != null and std.mem.eql(u8, content_type_ptr[0..content_type_len], "application/json");
            c.lua_pop(L2, 1);

            _ = c.lua_getfield(L2, -1, "body");
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L2, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (is_json) {
                try current_vtable.?.json(current_ctx.?, status, body);
            } else {
                try current_vtable.?.text(current_ctx.?, status, body);
            }
            c.lua_pop(L2, 2);
        } else if (c.lua_isstring(L2, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L2, -1, &len);
            try current_vtable.?.text(current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L2, 1);
        } else {
            try current_vtable.?.text(current_ctx.?, 204, "");
            c.lua_pop(L2, 1);
        }
    }
};
