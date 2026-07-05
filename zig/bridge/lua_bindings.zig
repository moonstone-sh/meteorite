const std = @import("std");
const graph = @import("meteorite_graph");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const lua_stats = @import("lua_stats.zig");
const lua_vtable = @import("lua_vtable.zig");
const lua_json = @import("lua_json.zig");
const lua_http = @import("lua_http.zig");

const incLua = lua_stats.inc;
const snapshotLuaStats = lua_stats.snapshot;
const LuaStats = lua_stats.Stats;
const globalVtable = lua_vtable.globalVtable;
const VTable = lua_vtable.VTable;
const encodeLuaValue = lua_json.encodeLuaValue;
const encodeJsonString = lua_json.encodeJsonString;
const HttpClient = lua_http.HttpClient;
const HttpResponse = lua_http.HttpResponse;

pub fn upvalueIndex(i: c_int) c_int {
    return c.LUA_REGISTRYINDEX - i;
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
    if (c.lua_pcallk(L, 0, 0, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
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
}

pub fn l_text(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 2 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var body_arg: c_int = offset + 1;
    if (nargs >= offset + 2 and c.lua_isinteger(L, offset + 1) != 0) {
        status = @intCast(c.lua_tointegerx(L, offset + 1, @as([*c]c_int, null)));
        body_arg = offset + 2;
    } else if (nargs < offset + 1) {
        return directText(L, status, "");
    }
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return directText(L, status, body_ptr[0..body_len]);
}

pub fn l_json(L: ?*c.lua_State) callconv(.c) c_int {
    const rt = lua_vtable.current_vtable.?;
    const ctx = lua_vtable.current_ctx.?;
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 2 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var value_idx: c_int = offset + 1;
    if (nargs >= offset + 2 and c.lua_isinteger(L, offset + 1) != 0) {
        status = @intCast(c.lua_tointegerx(L, offset + 1, @as([*c]c_int, null)));
        value_idx = offset + 2;
    } else if (nargs < offset + 1) {
        return directJson(L, status, "{}");
    }

    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(rt.allocator(ctx));
    encodeLuaValue(L, value_idx, &list, rt.allocator(ctx)) catch |err| {
        std.log.err("json encode failed: {s}", .{@errorName(err)});
        _ = c.luaL_error(L, "json encode failed");
        unreachable;
    };

    return directJson(L, status, list.items);
}

pub fn l_bytes(L: ?*c.lua_State) callconv(.c) c_int {
    const nargs = c.lua_gettop(L);
    var status: u16 = 200;
    const offset: c_int = if (nargs >= 3 and c.lua_istable(L, 1)) @as(c_int, 1) else @as(c_int, 0);
    var content_type_arg: c_int = offset + 1;
    var body_arg: c_int = offset + 2;
    if (nargs >= offset + 3 and c.lua_isinteger(L, offset + 1) != 0) {
        status = @intCast(c.lua_tointegerx(L, offset + 1, @as([*c]c_int, null)));
        content_type_arg = offset + 2;
        body_arg = offset + 3;
    } else if (nargs < offset + 2) {
        return directBytes(L, status, "application/octet-stream", "");
    }
    var ct_len: usize = 0;
    const ct_ptr = c.lua_tolstring(L, content_type_arg, &ct_len);
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, body_arg, &body_len);
    return directBytes(L, status, ct_ptr[0..ct_len], body_ptr[0..body_len]);
}

fn directText(L: ?*c.lua_State, status: u16, body: []const u8) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, "text/plain; charset=utf-8", body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, "text/plain; charset=utf-8", body);
    rt.text(ctx, status, body) catch |err| return luaError(L, "text response failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

fn directJson(L: ?*c.lua_State, status: u16, body: []const u8) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, "application/json", body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, "application/json", body);
    rt.json(ctx, status, body) catch |err| return luaError(L, "json response failed: {s}", .{@errorName(err)});
    lua_vtable.markResponded();
    return 0;
}

fn directBytes(L: ?*c.lua_State, status: u16, content_type: []const u8, body: []const u8) c_int {
    const rt = lua_vtable.current_vtable orelse return pushResponse(L, status, content_type, body);
    const ctx = lua_vtable.current_ctx orelse return pushResponse(L, status, content_type, body);
    rt.bytes(ctx, status, content_type, body) catch |err| return luaError(L, "bytes response failed: {s}", .{@errorName(err)});
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
    const name = c.lua_tolstring(L, 2, null);
    if (lua_vtable.current_vtable.?.query(lua_vtable.current_ctx.?, std.mem.span(name))) |value| {
        _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
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

pub fn pushHttpClosure(L: ?*c.lua_State, client: *HttpClient, lua_name: []const u8, method: []const u8) void {
    c.lua_pushlightuserdata(L, @ptrCast(client));
    _ = c.lua_pushlstring(L, method.ptr, method.len);
    c.lua_pushcclosure(L, l_http_request, 2);
    _ = c.lua_pushlstring(L, lua_name.ptr, lua_name.len);
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
    const key = c.lua_tolstring(L, 2, null);
    _ = c.lua_getfield(L, 1, "state");
    _ = c.lua_getfield(L, -1, key);
    c.lua_remove(L, -2);
    return 1;
}

pub fn l_set(L: ?*c.lua_State) callconv(.c) c_int {
    const key = c.lua_tolstring(L, 2, null);
    _ = c.lua_getfield(L, 1, "state");
    c.lua_pushvalue(L, 3);
    c.lua_setfield(L, -2, key);
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
