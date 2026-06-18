const std = @import("std");
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
    };
}

fn globalVtable(comptime Ctx: type) *const VTable {
    const static = comptime makeVTable(Ctx);
    return &static;
}

var current_ctx: ?*anyopaque = null;
var current_vtable: ?*const VTable = null;

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

    fn pushMethod(L: ?*c.lua_State, name: [*c]const u8, func: c.lua_CFunction) void {
        c.lua_pushcfunction(L, func);
        c.lua_setfield(L, -2, name);
    }
};

fn l_text(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    var body_arg: c_int = 2;
    if (nargs >= 3 and c.lua_isinteger(L, 2) != 0) {
        status = @intCast(c.lua_tointegerx(L, 2, @as([*c]c_int, null)));
        body_arg = 3;
    } else if (nargs >= 2) {
        body_arg = 2;
    } else {
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

    var list: std.ArrayList(u8) = .empty;
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
    } else if (nargs >= 3) {
        content_type_arg = 2;
        body_arg = 3;
    } else {
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

fn encodeLuaValue(L: ?*c.lua_State, idx: c_int, list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
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

fn encodeJsonString(s: []const u8, list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
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
