const std = @import("std");
const graph = @import("meteorite_graph");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const lua_stats = @import("lua_stats.zig");
const lua_vtable = @import("lua_vtable.zig");
const lua_json = @import("lua_json.zig");
const lua_http = @import("lua_http.zig");
const lua_abi = @import("lua_abi.zig");
const protocol = @import("meteorite_protocol");
const Header = protocol.Header;

const incLua = lua_stats.inc;
const snapshotLuaStats = lua_stats.snapshot;
const LuaStats = lua_stats.Stats;
const globalVtable = lua_vtable.globalVtable;
const VTable = lua_vtable.VTable;
const encodeLuaValue = lua_json.encodeLuaValue;
const encodeJsonString = lua_json.encodeJsonString;
const HttpClient = lua_http.HttpClient;
const HttpResponse = lua_http.HttpResponse;
const RequestHeader = lua_http.RequestHeader;

const ResponseHeaders = struct {
    items: [16]Header = undefined,
    len: usize = 0,

    fn append(self: *ResponseHeaders, name: []const u8, value: []const u8) !void {
        if (self.len >= self.items.len) return error.TooManyResponseHeaders;
        self.items[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }

    fn slice(self: *const ResponseHeaders) []const Header {
        return self.items[0..self.len];
    }
};

fn absoluteIndex(L: ?*c.lua_State, index: c_int) c_int {
    return if (index < 0) c.lua_gettop(L) + index + 1 else index;
}

fn parseHeadersTable(L: ?*c.lua_State, table_index: c_int) !ResponseHeaders {
    var headers: ResponseHeaders = .{};
    c.lua_pushnil(L);
    while (c.lua_next(L, table_index) != 0) {
        defer c.lua_pop(L, 1);
        if (c.lua_type(L, -2) != c.LUA_TSTRING or c.lua_isstring(L, -1) == 0) return error.InvalidResponseHeaders;
        var name_len: usize = 0;
        const name_ptr = c.lua_tolstring(L, -2, &name_len);
        var value_len: usize = 0;
        const value_ptr = c.lua_tolstring(L, -1, &value_len);
        const name = name_ptr[0..name_len];
        const value = value_ptr[0..value_len];
        try protocol.validateResponseHeader(name, value);
        try headers.append(name, value);
    }
    return headers;
}

fn optionalStringField(L: ?*c.lua_State, table_index: c_int, field: [:0]const u8) ?[]const u8 {
    _ = c.lua_getfield(L, table_index, field.ptr);
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return null;
    var len: usize = 0;
    const ptr = c.lua_tolstring(L, -1, &len) orelse return null;
    return ptr[0..len];
}

fn boolField(L: ?*c.lua_State, table_index: c_int, field: [:0]const u8, default_value: bool) bool {
    _ = c.lua_getfield(L, table_index, field.ptr);
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return default_value;
    return c.lua_toboolean(L, -1) != 0;
}

fn intField(L: ?*c.lua_State, table_index: c_int, field: [:0]const u8) ?i64 {
    _ = c.lua_getfield(L, table_index, field.ptr);
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return null;
    if (!lua_abi.isInteger(L, -1)) return null;
    return @intCast(lua_abi.toInteger(L, -1));
}

fn parseSameSite(value: []const u8) ?protocol.SameSite {
    if (std.ascii.eqlIgnoreCase(value, "lax")) return .lax;
    if (std.ascii.eqlIgnoreCase(value, "strict")) return .strict;
    if (std.ascii.eqlIgnoreCase(value, "none")) return .none;
    return null;
}

fn parseCookieOptions(L: ?*c.lua_State, options_index: c_int) !protocol.CookieOptions {
    if (options_index == 0 or !c.lua_istable(L, options_index)) return .{};
    const opts_index = absoluteIndex(L, options_index);
    var options: protocol.CookieOptions = .{
        .path = optionalStringField(L, opts_index, "path") orelse "/",
        .domain = optionalStringField(L, opts_index, "domain"),
        .max_age = intField(L, opts_index, "max_age"),
        .expires = optionalStringField(L, opts_index, "expires"),
        .secure = boolField(L, opts_index, "secure", true),
        .http_only = boolField(L, opts_index, "http_only", true),
        .same_site = .lax,
    };
    if (optionalStringField(L, opts_index, "same_site")) |same_site| {
        options.same_site = parseSameSite(same_site) orelse return error.InvalidCookieAttribute;
    }
    return options;
}

fn parseResponseOptionsHeaders(L: ?*c.lua_State, options_index: c_int) !ResponseHeaders {
    if (options_index == 0 or !c.lua_istable(L, options_index)) return .{};
    const opts_index = absoluteIndex(L, options_index);
    _ = c.lua_getfield(L, opts_index, "headers");
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return .{};
    if (!c.lua_istable(L, -1)) return error.InvalidResponseHeaders;
    return parseHeadersTable(L, absoluteIndex(L, -1));
}

pub fn upvalueIndex(i: c_int) c_int {
    return lua_abi.upvalueIndex(i);
}

pub fn setupLuaPackagePaths(L: ?*c.lua_State) !void {
    const setup =
        \\package.path = 'src/?.lua;src/?/init.lua;.moonstone/env/share/lua/5.4/?.lua;.moonstone/env/share/lua/5.4/?/init.lua;.moonstone/env/share/lua/5.3/?.lua;.moonstone/env/share/lua/5.3/?/init.lua;.moonstone/env/share/lua/5.2/?.lua;.moonstone/env/share/lua/5.2/?/init.lua;.moonstone/env/share/lua/5.1/?.lua;.moonstone/env/share/lua/5.1/?/init.lua;lua/?.lua;lua/?/init.lua;lua/5.4/?.lua;lua/5.4/?/init.lua;lua/5.3/?.lua;lua/5.3/?/init.lua;lua/5.2/?.lua;lua/5.2/?/init.lua;lua/5.1/?.lua;lua/5.1/?/init.lua;' .. package.path
        \\package.cpath = '.moonstone/env/lib/lua/5.4/?.so;.moonstone/env/lib/lua/5.4/?.dylib;.moonstone/env/lib/lua/5.4/?.dll;.moonstone/env/lib/lua/5.3/?.so;.moonstone/env/lib/lua/5.3/?.dylib;.moonstone/env/lib/lua/5.3/?.dll;.moonstone/env/lib/lua/5.2/?.so;.moonstone/env/lib/lua/5.2/?.dylib;.moonstone/env/lib/lua/5.2/?.dll;.moonstone/env/lib/lua/5.1/?.so;.moonstone/env/lib/lua/5.1/?.dylib;.moonstone/env/lib/lua/5.1/?.dll;lib/?.so;lib/?.dylib;lib/?.dll;lib/5.4/?.so;lib/5.4/?.dylib;lib/5.4/?.dll;lib/5.3/?.so;lib/5.3/?.dylib;lib/5.3/?.dll;lib/5.2/?.so;lib/5.2/?.dylib;lib/5.2/?.dll;lib/5.1/?.so;lib/5.1/?.dylib;lib/5.1/?.dll;' .. package.cpath
    ;
    if (c.luaL_loadstring(L, setup.ptr) != c.LUA_OK) {
        const err = c.lua_tolstring(L, -1, null);
        std.log.err("lua package setup load failed: {s}", .{err});
        incLua(&lua_stats.stats.lua_errors);
        return error.LuaLoadFailed;
    }
    if (lua_abi.pcall(L.?, 0, 0, 0) != lua_abi.LUA_OK) {
        const err = c.lua_tolstring(L, -1, null);
        std.log.err("lua package setup failed: {s}", .{err});
        incLua(&lua_stats.stats.lua_errors);
        return error.LuaRuntimeError;
    }
}

pub fn pushMethod(L: ?*c.lua_State, name: [*c]const u8, func: c.lua_CFunction) void {
    c.lua_pushcfunction(L, func);
    c.lua_setfield(L, -2, name);
}

pub fn installGlobalResponseHelpers(L: ?*c.lua_State) void {
    c.lua_pushcfunction(L, l_text);
    c.lua_setglobal(L, "text");
    c.lua_pushcfunction(L, l_json);
    c.lua_setglobal(L, "json");
    c.lua_pushcfunction(L, l_bytes);
    c.lua_setglobal(L, "bytes");
    c.lua_pushcfunction(L, l_set_cookie);
    c.lua_setglobal(L, "set_cookie");
    c.lua_pushcfunction(L, l_stream_begin);
    c.lua_setglobal(L, "stream_begin");
    c.lua_pushcfunction(L, l_stream_write);
    c.lua_setglobal(L, "stream_write");
    c.lua_pushcfunction(L, l_stream_end);
    c.lua_setglobal(L, "stream_end");
    c.lua_pushcfunction(L, l_meteorite_sleep);
    c.lua_setglobal(L, "meteorite_sleep");
}

// --- Minimal streaming Lua bindings ------------------------------------
// Deliberately plain positional args (no self-call/table-options
// convention like l_text/l_json/l_bytes have) -- this is a bounded proof
// of the underlying primitive, not the final public API surface.
//   stream_begin(status, content_type)
//   stream_write(chunk)  -- may be called any number of times
//   stream_end()
pub fn l_stream_begin(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable orelse return luaError(L, "stream_begin: no active context", .{});
    const ctx = lua_vtable.current_ctx orelse return luaError(L, "stream_begin: no active context", .{});
    const status: u16 = @intCast(c.lua_tointegerx(L, 1, @as([*c]c_int, null)));
    var ct_len: usize = 0;
    const ct_ptr = c.lua_tolstring(L, 2, &ct_len);
    const content_type = if (ct_ptr != null) ct_ptr[0..ct_len] else "text/plain; charset=utf-8";
    rt.begin_stream(ctx, status, content_type) catch |err| return luaError(L, "stream_begin failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

pub fn l_stream_write(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable orelse return luaError(L, "stream_write: no active context", .{});
    const ctx = lua_vtable.current_ctx orelse return luaError(L, "stream_write: no active context", .{});
    var chunk_len: usize = 0;
    const chunk_ptr = c.lua_tolstring(L, 1, &chunk_len);
    if (chunk_ptr == null) return luaError(L, "stream_write: expected a string chunk", .{});
    rt.write_chunk(ctx, chunk_ptr[0..chunk_len]) catch |err| return luaError(L, "stream_write failed: {s}", .{@errorName(err)});
    return 0;
}

pub fn l_stream_end(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable orelse return luaError(L, "stream_end: no active context", .{});
    const ctx = lua_vtable.current_ctx orelse return luaError(L, "stream_end: no active context", .{});
    rt.end_stream(ctx) catch |err| return luaError(L, "stream_end failed: {s}", .{@errorName(err)});
    return 0;
}

/// Suspends the current request without spawning a subprocess. This is kept
/// explicit to Meteorite rather than replacing Lua's general timing APIs: it
/// uses the server's Io implementation and is safe inside threaded handlers.
pub fn l_meteorite_sleep(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable orelse return luaError(L, "meteorite_sleep: no active context", .{});
    const ctx = lua_vtable.current_ctx orelse return luaError(L, "meteorite_sleep: no active context", .{});
    var is_number: c_int = 0;
    const seconds = c.lua_tonumberx(L, 1, &is_number);
    if (is_number == 0 or !std.math.isFinite(seconds) or seconds < 0 or seconds > 60) {
        return luaError(L, "meteorite_sleep: expected seconds between 0 and 60", .{});
    }
    if (seconds == 0) return 0;
    const nanoseconds: u64 = @intFromFloat(seconds * @as(c.lua_Number, std.time.ns_per_s));
    rt.io(ctx).sleep(.{ .nanoseconds = nanoseconds }, .real) catch |err| {
        return luaError(L, "meteorite_sleep failed: {s}", .{@errorName(err)});
    };
    return 0;
}

pub fn l_text(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 2 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var body_arg: c_int = offset + 1;
    var options_arg: c_int = 0;
    if (nargs >= offset + 2 and lua_abi.isInteger(L, offset + 1)) {
        status = @intCast(lua_abi.toInteger(L, offset + 1));
        body_arg = offset + 2;
        if (nargs >= offset + 3) options_arg = offset + 3;
    } else if (nargs < offset + 1) {
        return directText(L, status, "", options_arg);
    } else if (nargs >= offset + 2) {
        options_arg = offset + 2;
    }
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return directText(L, status, body_ptr[0..body_len], options_arg);
}

pub fn l_json(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable.?;
    const ctx = lua_vtable.current_ctx.?;
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 2 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var value_idx: c_int = offset + 1;
    var options_arg: c_int = 0;
    if (nargs >= offset + 2 and lua_abi.isInteger(L, offset + 1)) {
        status = @intCast(lua_abi.toInteger(L, offset + 1));
        value_idx = offset + 2;
        if (nargs >= offset + 3) options_arg = offset + 3;
    } else if (nargs < offset + 1) {
        return directJson(L, status, "{}", options_arg);
    } else if (nargs >= offset + 2) {
        options_arg = offset + 2;
    }

    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(rt.allocator(ctx));
    encodeLuaValue(L, value_idx, &list, rt.allocator(ctx)) catch |err| {
        std.log.err("json encode failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "json encode failed");
        unreachable;
    };

    return directJson(L, status, list.items, options_arg);
}

pub fn l_bytes(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 3 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var content_type_arg: c_int = offset + 1;
    var body_arg: c_int = offset + 2;
    var options_arg: c_int = 0;
    if (nargs >= offset + 3 and lua_abi.isInteger(L, offset + 1)) {
        status = @intCast(lua_abi.toInteger(L, offset + 1));
        content_type_arg = offset + 2;
        body_arg = offset + 3;
        if (nargs >= offset + 4) options_arg = offset + 4;
    } else if (nargs < offset + 2) {
        return directBytes(L, status, "application/octet-stream", "", options_arg);
    } else if (nargs >= offset + 3) {
        options_arg = offset + 3;
    }
    var ct_len: usize = 0;
    const ct_ptr = c.lua_tolstring(L, content_type_arg, &ct_len);
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return directBytes(L, status, ct_ptr[0..ct_len], body_ptr[0..body_len], options_arg);
}

pub fn l_set_cookie(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    const offset: c_int = if (nargs >= 3 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    if (nargs < offset + 2) return luaError(L, "set_cookie requires name and value", .{});
    var name_len: usize = 0;
    const name_ptr = c.lua_tolstring(L, offset + 1, &name_len) orelse return luaError(L, "set_cookie name must be string", .{});
    var value_len: usize = 0;
    const value_ptr = c.lua_tolstring(L, offset + 2, &value_len) orelse return luaError(L, "set_cookie value must be string", .{});
    const options_arg: c_int = if (nargs >= offset + 3) offset + 3 else 0;
    const options = parseCookieOptions(L, options_arg) catch |err| return luaError(L, "set_cookie options invalid: {s}", .{@errorName(err)});
    var buffer: [4096]u8 = undefined;
    if (offset == 1) {
        if (lua_vtable.current_vtable) |rt| {
            if (lua_vtable.current_ctx) |ctx| {
                const header = rt.set_cookie(ctx, &buffer, name_ptr[0..name_len], value_ptr[0..value_len], options) catch |err| return luaError(L, "set_cookie failed: {s}", .{@errorName(err)});
                _ = c.lua_pushlstring(L, @ptrCast(header.value.ptr), header.value.len);
                return 1;
            }
        }
    }
    const value = protocol.buildSetCookie(&buffer, name_ptr[0..name_len], value_ptr[0..value_len], options) catch |err| return luaError(L, "set_cookie invalid: {s}", .{@errorName(err)});
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    return 1;
}

fn directText(L: ?*c.lua_State, status: u16, body: []const u8, options_arg: c_int) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, "text/plain; charset=utf-8", body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, "text/plain; charset=utf-8", body);
    const headers = parseResponseOptionsHeaders(L, options_arg) catch |err| return luaError(L, "response headers invalid: {s}", .{@errorName(err)});
    rt.bytes_with_headers(ctx, status, "text/plain; charset=utf-8", body, headers.slice()) catch |err| return luaError(L, "text response failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

fn directJson(L: ?*c.lua_State, status: u16, body: []const u8, options_arg: c_int) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, "application/json", body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, "application/json", body);
    const headers = parseResponseOptionsHeaders(L, options_arg) catch |err| return luaError(L, "response headers invalid: {s}", .{@errorName(err)});
    rt.bytes_with_headers(ctx, status, "application/json", body, headers.slice()) catch |err| return luaError(L, "json response failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

fn directBytes(L: ?*c.lua_State, status: u16, content_type: []const u8, body: []const u8, options_arg: c_int) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, content_type, body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, content_type, body);
    const headers = parseResponseOptionsHeaders(L, options_arg) catch |err| return luaError(L, "response headers invalid: {s}", .{@errorName(err)});
    rt.bytes_with_headers(ctx, status, content_type, body, headers.slice()) catch |err| return luaError(L, "bytes response failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

fn luaError(L: ?*c.lua_State, comptime fmt: []const u8, args: anytype) c_int {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "lua bridge error";
    _ = c.luaL_error(L, msg.ptr);
    unreachable;
}

pub fn l_body(L: ?*c.lua_State) callconv(.c) c_int {
    const body = lua_vtable.current_vtable.?.body(lua_vtable.current_ctx.?) catch |err| {
        std.log.err("body read failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "body read failed");
        unreachable;
    };
    _ = c.lua_pushlstring(L, @ptrCast(body.ptr), body.len);
    return 1;
}

pub fn l_target(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_vtable.current_vtable.?.target(lua_vtable.current_ctx.?);
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    return 1;
}

pub fn l_path(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_vtable.current_vtable.?.path(lua_vtable.current_ctx.?);
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    return 1;
}

pub fn l_route_id(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_vtable.current_vtable.?.route_id(lua_vtable.current_ctx.?);
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    return 1;
}

pub fn l_redirect(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    const offset: c_int = if (nargs >= 3 and c.lua_istable(L, 1)) 1 else 0;
    if (nargs < offset + 2 or !lua_abi.isInteger(L, offset + 1)) {
        return luaError(L, "redirect: expected status and location", .{});
    }
    const status_value = lua_abi.toInteger(L, offset + 1);
    if (status_value < 0 or status_value > std.math.maxInt(u16)) {
        return luaError(L, "redirect: invalid status", .{});
    }
    var location_len: usize = 0;
    const location_ptr = c.lua_tolstring(L, offset + 2, &location_len) orelse {
        return luaError(L, "redirect: location must be a string", .{});
    };
    lua_vtable.current_vtable.?.redirect(
        lua_vtable.current_ctx.?,
        @intCast(status_value),
        location_ptr[0..location_len],
    ) catch |err| return luaError(L, "redirect failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

pub fn l_param(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (lua_vtable.current_vtable.?.param(lua_vtable.current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_query(L: ?*c.lua_State) callconv(.c) c_int {
    const top = c.lua_gettop(L);
    const name = if (top >= 1 and c.lua_isstring(L, top) != 0)
        c.lua_tolstring(L, top, null)
    else
        null;
    if (name) |n| {
        if (lua_vtable.current_vtable) |vt| {
            if (lua_vtable.current_ctx) |ctx| {
                if (vt.query(ctx, std.mem.span(n))) |value| {
                    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                    return 1;
                }
            }
        }
    }
    c.lua_pushnil(L);
    return 1;
}

pub fn l_message(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_vtable.current_vtable.?.message(lua_vtable.current_ctx.?);
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    return 1;
}

pub fn l_metadata(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (lua_vtable.current_vtable.?.metadata(lua_vtable.current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_peer(L: ?*c.lua_State) callconv(.c) c_int {
    if (lua_vtable.current_vtable.?.peer(lua_vtable.current_ctx.?)) |identity| {
        c.lua_createtable(L, 0, 3);
        if (identity.uid) |uid| {
            c.lua_pushinteger(L, @intCast(uid));
            c.lua_setfield(L, -2, "uid");
        }
        if (identity.gid) |gid| {
            c.lua_pushinteger(L, @intCast(gid));
            c.lua_setfield(L, -2, "gid");
        }
        if (identity.pid) |pid| {
            c.lua_pushinteger(L, @intCast(pid));
            c.lua_setfield(L, -2, "pid");
        }
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_query_all(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (lua_vtable.current_vtable.?.query_all(lua_vtable.current_ctx.?, std.mem.span(name))) |values| {
        c.lua_createtable(L, @intCast(values.len), 0);
        for (values, 0..) |value, i| {
            _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
            c.lua_rawseti(L, -2, @intCast(i + 1));
        }
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_header(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (lua_vtable.current_vtable.?.header(lua_vtable.current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_request_id(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_vtable.current_vtable.?.request_id(lua_vtable.current_ctx.?) catch |err| return luaError(L, "request_id failed: {s}", .{@errorName(err)});
    _ = c.lua_pushlstring(L, value.ptr, value.len);
    return 1;
}

fn trimCookieSpace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t");
}

fn validCookieValueByte(byte: u8) bool {
    return byte >= 0x20 and byte != 0x7f and byte != ';' and byte != '\r' and byte != '\n';
}

fn decodeCookieValue(allocator: std.mem.Allocator, raw_value: []const u8) !?[]u8 {
    var value = trimCookieSpace(raw_value);
    if (value.len >= 2 and value[0] == '"') {
        if (value[value.len - 1] != '"') return null;
        value = value[1 .. value.len - 1];
    } else if (value.len > 0 and std.mem.indexOfScalar(u8, value, '"') != null) {
        return null;
    }

    var decoded = try allocator.alloc(u8, value.len);
    errdefer allocator.free(decoded);
    var out: usize = 0;
    var index: usize = 0;
    while (index < value.len) {
        var byte = value[index];
        if (byte == '%') {
            if (index + 2 >= value.len) {
                allocator.free(decoded);
                return null;
            }
            const hi = std.fmt.charToDigit(value[index + 1], 16) catch {
                allocator.free(decoded);
                return null;
            };
            const lo = std.fmt.charToDigit(value[index + 2], 16) catch {
                allocator.free(decoded);
                return null;
            };
            byte = @intCast((hi << 4) | lo);
            index += 3;
        } else {
            index += 1;
        }
        if (!validCookieValueByte(byte)) {
            allocator.free(decoded);
            return null;
        }
        decoded[out] = byte;
        out += 1;
    }
    return try allocator.realloc(decoded, out);
}

fn cookieValue(allocator: std.mem.Allocator, header_value: []const u8, wanted: []const u8) !?[]u8 {
    var found: ?[]u8 = null;
    var fields = std.mem.splitScalar(u8, header_value, ';');
    while (fields.next()) |field| {
        const pair = trimCookieSpace(field);
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
            const name = trimCookieSpace(pair[0..eq]);
            if (std.mem.eql(u8, name, wanted)) {
                if (found) |value| {
                    allocator.free(value);
                    return null;
                }
                found = try decodeCookieValue(allocator, pair[eq + 1 ..]) orelse return null;
            }
        }
    }
    return found;
}

pub fn l_cookie(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null) orelse {
        c.lua_pushnil(L);
        return 1;
    };
    const wanted = std.mem.span(name);
    const header_value = lua_vtable.current_vtable.?.header(lua_vtable.current_ctx.?, "cookie") orelse {
        c.lua_pushnil(L);
        return 1;
    };
    const allocator = std.heap.page_allocator;
    if (cookieValue(allocator, header_value, wanted) catch null) |value| {
        defer allocator.free(value);
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
    } else {
        c.lua_pushnil(L);
    }
    return 1;
}

pub fn l_http(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (name == null) {
        _ = c.luaL_error(L, "http capability name required");
        unreachable;
    }
    const cap_name = std.mem.span(name);
    const ctx = lua_vtable.current_ctx.?;
    const vtable = lua_vtable.current_vtable.?;
    const allocator = vtable.allocator(ctx);

    const base_url = getCapabilityString("http", cap_name, "base_url") orelse {
        _ = c.luaL_error(L, "http capability missing base_url");
        unreachable;
    };
    const timeout_ms = getCapabilityInt("http", cap_name, "timeout_ms") orelse 1500;
    const max_response_bytes = getCapabilityInt("http", cap_name, "max_response_bytes") orelse 65536;
    if (timeout_ms < 1 or timeout_ms > std.math.maxInt(u32) or max_response_bytes < 1) {
        _ = c.luaL_error(L, "http capability has invalid timeout_ms or max_response_bytes");
        unreachable;
    }

    const client = @as(?*HttpClient, @ptrCast(@alignCast(lua_abi.newUserdata(L.?, @sizeOf(HttpClient))))) orelse {
        _ = c.luaL_error(L, "out of memory");
        unreachable;
    };
    client.* = HttpClient.init(allocator, base_url, @intCast(timeout_ms), @intCast(max_response_bytes));
    const client_index = absoluteIndex(L, -1);

    c.lua_newtable(L);
    pushHttpClosure(L, client_index, "get", "GET");
    pushHttpClosure(L, client_index, "post", "POST");
    pushHttpClosure(L, client_index, "put", "PUT");
    pushHttpClosure(L, client_index, "patch", "PATCH");
    pushHttpClosure(L, client_index, "delete", "DELETE");
    return 1;
}

pub fn pushHttpClosure(L: ?*c.lua_State, client_index: c_int, lua_name: []const u8, method: []const u8) void {
    _ = c.lua_pushlstring(L, lua_name.ptr, lua_name.len);
    c.lua_pushvalue(L, client_index);
    _ = c.lua_pushlstring(L, method.ptr, method.len);
    c.lua_pushcclosure(L, l_http_request, 2);
    c.lua_rawset(L, -3);
}

pub fn l_http_request(L: ?*c.lua_State) callconv(.c) c_int {
    const client_ptr = @as(*HttpClient, @ptrCast(@alignCast(c.lua_touserdata(L, upvalueIndex(1)))));
    var method_len: usize = 0;
    const method_ptr = c.lua_tolstring(L, upvalueIndex(2), &method_len);
    const method = method_ptr[0..method_len];

    const vtable = lua_vtable.current_vtable.?;
    const ctx = lua_vtable.current_ctx.?;
    const allocator = vtable.allocator(ctx);

    const path_ptr = c.lua_tolstring(L, 2, null) orelse {
        _ = c.luaL_error(L, "path required");
        unreachable;
    };
    const path = std.mem.span(path_ptr);

    var body: ?[]const u8 = null;
    var request_headers: [33]RequestHeader = undefined;
    var request_header_count: usize = 0;

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
            request_headers[request_header_count] = .{ .name = "content-type", .value = "application/json" };
            request_header_count += 1;
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
            const headers_index = absoluteIndex(L, -1);
            c.lua_pushnil(L);
            while (c.lua_next(L, headers_index) != 0) {
                if (request_header_count >= request_headers.len) {
                    _ = c.luaL_error(L, "too many http request headers");
                    unreachable;
                }
                if (c.lua_type(L, -2) != c.LUA_TSTRING or c.lua_isstring(L, -1) == 0) {
                    _ = c.luaL_error(L, "http request headers must be string pairs");
                    unreachable;
                }
                var name_len: usize = 0;
                const name_ptr = c.lua_tolstring(L, -2, &name_len);
                var value_len: usize = 0;
                const value_ptr = c.lua_tolstring(L, -1, &value_len);
                const name = name_ptr[0..name_len];
                var replaced = false;
                for (request_headers[0..request_header_count]) |*header| {
                    if (std.ascii.eqlIgnoreCase(header.name, name)) {
                        header.value = value_ptr[0..value_len];
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) {
                    request_headers[request_header_count] = .{ .name = name, .value = value_ptr[0..value_len] };
                    request_header_count += 1;
                }
                c.lua_pop(L, 1);
            }
        }
        c.lua_pop(L, 1);
    }
    defer {
        if (body) |b| allocator.free(b);
    }

    const response = client_ptr.request(method, path, body, request_headers[0..request_header_count]) catch |err| {
        std.log.err("http request failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "http request failed");
        unreachable;
    };
    defer response.deinit();
    pushHttpClientResponse(L, response);
    return 1;
}

fn responseContentType(raw_headers: []const u8) ?[]const u8 {
    var lines = std.mem.splitAny(u8, raw_headers, "\r\n");
    var result: ?[]const u8 = null;
    while (lines.next()) |line| {
        const idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..idx], " \t"), "content-type")) {
            result = std.mem.trim(u8, line[idx + 1 ..], " \t");
        }
    }
    return result;
}

fn pushHttpClientResponse(L: ?*c.lua_State, response: HttpResponse) void {
    c.lua_newtable(L);
    c.lua_pushinteger(L, response.status);
    c.lua_setfield(L, -2, "status");

    c.lua_newtable(L);
    var lines = std.mem.splitAny(u8, response.headers, "\r\n");
    while (lines.next()) |line| {
        const idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..idx], " \t");
        const value = std.mem.trim(u8, line[idx + 1 ..], " \t");
        if (name.len == 0) continue;
        const lower_name = response.allocator.alloc(u8, name.len) catch continue;
        defer response.allocator.free(lower_name);
        _ = std.ascii.lowerString(lower_name, name);
        _ = c.lua_pushlstring(L, lower_name.ptr, lower_name.len);
        _ = c.lua_pushlstring(L, value.ptr, value.len);
        c.lua_rawset(L, -3);
    }
    c.lua_setfield(L, -2, "headers");

    const content_type = responseContentType(response.headers) orelse "";
    const is_json = std.mem.indexOf(u8, content_type, "application/json") != null or std.mem.indexOf(u8, content_type, "+json") != null;
    if (is_json) {
        if (std.json.parseFromSlice(std.json.Value, response.allocator, response.body, .{ .allocate = .alloc_always })) |parsed| {
            defer parsed.deinit();
            pushJsonValue(L, parsed.value);
            c.lua_setfield(L, -2, "body");
            return;
        } else |_| {
            // A malformed JSON response remains inspectable as raw text.
        }
    }
    _ = c.lua_pushlstring(L, response.body.ptr, response.body.len);
    c.lua_setfield(L, -2, "body");
}

fn pushJsonValue(L: ?*c.lua_State, value: std.json.Value) void {
    switch (value) {
        .null => c.lua_pushnil(L),
        .bool => |v| c.lua_pushboolean(L, @intFromBool(v)),
        .integer => |v| c.lua_pushinteger(L, @intCast(v)),
        .float => |v| c.lua_pushnumber(L, v),
        .number_string => |v| {
            _ = c.lua_pushlstring(L, v.ptr, v.len);
        },
        .string => |v| {
            _ = c.lua_pushlstring(L, v.ptr, v.len);
        },
        .array => |v| {
            c.lua_newtable(L);
            for (v.items, 0..) |item, i| {
                pushJsonValue(L, item);
                c.lua_rawseti(L, -2, @intCast(i + 1));
            }
        },
        .object => |v| {
            c.lua_newtable(L);
            var it = v.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                _ = c.lua_pushlstring(L, key.ptr, key.len);
                pushJsonValue(L, entry.value_ptr.*);
                c.lua_rawset(L, -3);
            }
        },
    }
}

pub fn l_auth(L: ?*c.lua_State) callconv(.c) c_int {
    const name = c.lua_tolstring(L, 2, null);
    if (name == null) {
        _ = c.luaL_error(L, "auth capability name required");
        unreachable;
    }
    const cap_name = std.mem.span(name);

    const audience = getCapabilityString("auth", cap_name, "audience") orelse cap_name;
    const ctx = lua_vtable.current_ctx.?;
    const vtable = lua_vtable.current_vtable.?;
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

pub fn l_auth_headers(L: ?*c.lua_State) callconv(.c) c_int {
    var len: usize = 0;
    const token_ptr = c.lua_tolstring(L, upvalueIndex(1), &len);
    const token = token_ptr[0..len];
    c.lua_newtable(L);
    _ = c.lua_pushlstring(L, token.ptr, token.len);
    c.lua_setfield(L, -2, "authorization");
    return 1;
}

pub fn l_auth_authorization(L: ?*c.lua_State) callconv(.c) c_int {
    var len: usize = 0;
    const token_ptr = c.lua_tolstring(L, upvalueIndex(1), &len);
    const token = token_ptr[0..len];
    _ = c.lua_pushlstring(L, token.ptr, token.len);
    return 1;
}

pub fn l_zig(L: ?*c.lua_State) callconv(.c) c_int {
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

pub fn l_zig_device_name(L: ?*c.lua_State) callconv(.c) c_int {
    const device_id_ptr = c.lua_tolstring(L, 2, null);
    const device_id = if (device_id_ptr) |p| std.mem.span(p) else "";
    const vtable = lua_vtable.current_vtable.?;
    const ctx = lua_vtable.current_ctx.?;
    const allocator = vtable.allocator(ctx);
    const result = std.fmt.allocPrint(allocator, "device:{s}", .{device_id}) catch {
        _ = c.luaL_error(L, "out of memory");
        unreachable;
    };
    defer allocator.free(result);
    _ = c.lua_pushlstring(L, result.ptr, result.len);
    return 1;
}

pub fn l_get(L: ?*c.lua_State) callconv(.c) c_int {
    var key_len: usize = 0;
    const key_ptr = c.lua_tolstring(L, 2, &key_len) orelse {
        c.lua_pushnil(L);
        return 1;
    };
    const key = key_ptr[0..key_len];
    if (lua_vtable.current_vtable) |vtable| if (lua_vtable.current_ctx) |ctx| {
        if (vtable.state_get(ctx, key)) |value| {
            _ = c.lua_pushlstring(L, value.ptr, value.len);
            return 1;
        }
    };
    _ = c.lua_getfield(L, 1, "state");
    _ = c.lua_getfield(L, -1, @ptrCast(key_ptr));
    c.lua_remove(L, -2);
    return 1;
}

pub fn l_set(L: ?*c.lua_State) callconv(.c) c_int {
    var key_len: usize = 0;
    const key_ptr = c.lua_tolstring(L, 2, &key_len) orelse return 1;
    const key = key_ptr[0..key_len];
    if (lua_vtable.current_vtable) |vtable| if (lua_vtable.current_ctx) |ctx| {
        var value_len: usize = 0;
        const value_ptr = c.lua_tolstring(L, 3, &value_len);
        if (value_ptr != null) vtable.state_set(ctx, key, value_ptr[0..value_len]) catch {};
    };
    _ = c.lua_getfield(L, 1, "state");
    c.lua_pushvalue(L, 3);
    c.lua_setfield(L, -2, @ptrCast(key_ptr));
    c.lua_pop(L, 1);
    return 1;
}

pub fn l_debug(L: ?*c.lua_State) callconv(.c) c_int {
    const state_int: usize = @intFromPtr(L.?);
    var buf: [32]u8 = undefined;
    const state_text = std.fmt.bufPrint(&buf, "{x}", .{state_int}) catch "unknown";
    c.lua_newtable(L);
    _ = c.lua_pushlstring(L, state_text.ptr, state_text.len);
    c.lua_setfield(L, -2, "lua_state_id");
    c.lua_pushinteger(L, @intCast(lua_stats.debug_worker_counter));
    c.lua_setfield(L, -2, "worker_counter");
    return 1;
}

pub fn l_shared_counter(L: ?*c.lua_State) callconv(.c) c_int {
    const value = lua_stats.debug_shared_counter.fetchAdd(1, .monotonic) + 1;
    c.lua_pushinteger(L, @intCast(value));
    return 1;
}

pub fn l_worker_counter(L: ?*c.lua_State) callconv(.c) c_int {
    lua_stats.debug_worker_counter += 1;
    c.lua_pushinteger(L, @intCast(lua_stats.debug_worker_counter));
    return 1;
}

pub fn setClosure(L: ?*c.lua_State, name: [*c]const u8, func: c.lua_CFunction) void {
    c.lua_pushcfunction(L, func);
    c.lua_setfield(L, -2, name);
}

pub fn pushResponse(L: ?*c.lua_State, status: u16, content_type: []const u8, body: []const u8) c_int {
    c.lua_newtable(L);
    c.lua_pushinteger(L, status);
    c.lua_setfield(L, -2, "status");
    _ = c.lua_pushlstring(L, @ptrCast(content_type.ptr), content_type.len);
    c.lua_setfield(L, -2, "content_type");
    _ = c.lua_pushlstring(L, @ptrCast(body.ptr), body.len);
    c.lua_setfield(L, -2, "body");
    return 1;
}

pub fn getCapabilityString(kind: []const u8, name: []const u8, comptime field: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, kind, "http")) return lookupString(graph.capabilities.http, name, field);
    if (std.mem.eql(u8, kind, "auth")) return lookupString(graph.capabilities.auth, name, field);
    if (std.mem.eql(u8, kind, "zig")) {
        const value = lookupZig(graph.capabilities.zig, name) orelse return null;
        if (std.mem.eql(u8, field, "path")) return value;
    }
    return null;
}

pub fn getCapabilityInt(kind: []const u8, name: []const u8, comptime field: []const u8) ?i64 {
    if (std.mem.eql(u8, kind, "http")) return lookupInt(graph.capabilities.http, name, field);
    if (std.mem.eql(u8, kind, "auth")) return lookupInt(graph.capabilities.auth, name, field);
    return null;
}

pub fn lookupString(comptime T: type, name: []const u8, comptime field: []const u8) ?[]const u8 {
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

pub fn lookupInt(comptime T: type, name: []const u8, comptime field: []const u8) ?i64 {
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

pub fn lookupZig(comptime T: type, name: []const u8) ?[]const u8 {
    const decls = comptime std.meta.declarations(T);
    inline for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) {
            const cap = @field(T, decl.name);
            return cap;
        }
    }
    return null;
}

// ============================================================
