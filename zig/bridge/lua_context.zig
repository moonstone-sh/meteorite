const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const lua_abi = @import("lua_abi.zig");
const lua_bindings = @import("lua_bindings.zig");
const lua_vtable = @import("lua_vtable.zig");
const context_helpers = @import("context_helpers.zig");

const LUA_OK = lua_abi.LUA_OK;
const pcall = lua_abi.pcall;
const VTable = lua_vtable.VTable;

const l_text = lua_bindings.l_text;
const l_json = lua_bindings.l_json;
const l_bytes = lua_bindings.l_bytes;
const l_body = lua_bindings.l_body;
const l_param = lua_bindings.l_param;
const l_message = lua_bindings.l_message;
const l_metadata = lua_bindings.l_metadata;
const l_peer = lua_bindings.l_peer;
const l_query = lua_bindings.l_query;
const l_query_all = lua_bindings.l_query_all;
const l_header = lua_bindings.l_header;
const l_request_id = lua_bindings.l_request_id;
const l_cookie = lua_bindings.l_cookie;
const l_set_cookie = lua_bindings.l_set_cookie;
const l_http = lua_bindings.l_http;
const l_auth = lua_bindings.l_auth;
const l_zig = lua_bindings.l_zig;
const l_get = lua_bindings.l_get;
const l_set = lua_bindings.l_set;
const l_debug = lua_bindings.l_debug;
const l_shared_counter = lua_bindings.l_shared_counter;
const l_worker_counter = lua_bindings.l_worker_counter;
const pushMethod = lua_bindings.pushMethod;

fn pushJsonBodyMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.json_body_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "json_body") else c.lua_pop(L, 1);
}

fn pushFormBodyMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.form_body_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "form_body") else c.lua_pop(L, 1);
}

fn pushSecureHeadersMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.secure_headers_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "secure_headers") else c.lua_pop(L, 1);
}

fn pushCorsHeadersMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.cors_headers_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "cors_headers") else c.lua_pop(L, 1);
}

fn pushServerTimingMethods(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.server_timing_helper.ptr);
    if (pcall(L, 0, 1, 0) != LUA_OK) {
        c.lua_pop(L, 1);
        return;
    }
    _ = c.lua_getfield(L, -1, "headers");
    c.lua_setfield(L, -3, "server_timing");
    _ = c.lua_getfield(L, -1, "stage");
    c.lua_setfield(L, -3, "timing_stage");
    c.lua_pop(L, 1);
}

fn pushConstantTimeEqualMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.constant_time_equal_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "constant_time_equal") else c.lua_pop(L, 1);
}

fn pushBasicAuthMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.basic_auth_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "basic_auth") else c.lua_pop(L, 1);
}

fn pushBearerTokenMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.bearer_token_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "bearer_token") else c.lua_pop(L, 1);
}

fn pushSafeHeaderMethods(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.safe_header_helper.ptr);
    if (pcall(L, 0, 1, 0) != LUA_OK) {
        c.lua_pop(L, 1);
        return;
    }
    _ = c.lua_getfield(L, -1, "one");
    c.lua_setfield(L, -3, "safe_header");
    _ = c.lua_getfield(L, -1, "many");
    c.lua_setfield(L, -3, "safe_headers");
    c.lua_pop(L, 1);
}

fn pushLogMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, context_helpers.log_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "log") else c.lua_pop(L, 1);
}

fn pushCoreContextMethods(L: *c.lua_State) void {
    pushMethod(L, "text", l_text);
    pushMethod(L, "json", l_json);
    pushMethod(L, "bytes", l_bytes);
    pushMethod(L, "body", l_body);
    pushJsonBodyMethod(L);
    pushFormBodyMethod(L);
    pushSecureHeadersMethod(L);
    pushCorsHeadersMethod(L);
    pushServerTimingMethods(L);
    pushConstantTimeEqualMethod(L);
    pushBasicAuthMethod(L);
    pushBearerTokenMethod(L);
    pushSafeHeaderMethods(L);
    pushLogMethod(L);
    pushMethod(L, "param", l_param);
    pushMethod(L, "message", l_message);
    pushMethod(L, "metadata", l_metadata);
    pushMethod(L, "peer", l_peer);
    pushMethod(L, "query", l_query);
    pushMethod(L, "query_all", l_query_all);
    pushMethod(L, "header", l_header);
    pushMethod(L, "request_id", l_request_id);
    pushMethod(L, "cookie", l_cookie);
    pushMethod(L, "set_cookie", l_set_cookie);
    pushMethod(L, "http", l_http);
    pushMethod(L, "auth", l_auth);
    pushMethod(L, "zig", l_zig);
    pushMethod(L, "get", l_get);
    pushMethod(L, "set", l_set);
    pushMethod(L, "debug", l_debug);
    pushMethod(L, "shared_counter", l_shared_counter);
    pushMethod(L, "worker_counter", l_worker_counter);
}

/// Push a validated request value using the Lua type its declared schema kind
/// implies, so a handler observes what the generated LuaCATS types promise
/// (`---@field id integer`, `---@field active boolean`) instead of a string.
///
/// Validation (`request_validation.zig`) has already proven the raw bytes parse
/// for this kind, so the parses below are expected to succeed. They are still
/// written to fall back to the raw string rather than fabricate a value: a
/// coercion bug must never silently invent a number a request did not contain.
fn pushSchemaValue(L: *c.lua_State, kind: anytype, value: []const u8) void {
    switch (kind) {
        .u64 => {
            const parsed = std.fmt.parseInt(u64, value, 10) catch {
                _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                return;
            };
            // lua_Integer is i64; a u64 above that range would wrap to a
            // negative number, so keep the exact string instead of lying.
            if (parsed > std.math.maxInt(i64)) {
                _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                return;
            }
            c.lua_pushinteger(L, @intCast(parsed));
        },
        .i32 => {
            const parsed = std.fmt.parseInt(i32, value, 10) catch {
                _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                return;
            };
            c.lua_pushinteger(L, @intCast(parsed));
        },
        .bool => {
            // request_validation.zig accepts exactly these four spellings.
            const truthy = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
            c.lua_pushboolean(L, if (truthy) 1 else 0);
        },
        else => {
            _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
        },
    }
}

/// Look up the declared schema kind for a path param by name and push the
/// capture coerced to it. Falls back to a plain string when the route declares
/// no schema for that capture (e.g. an undeclared wildcard segment).
fn pushParamValue(L: *c.lua_State, ctx: anytype, name: []const u8, value: []const u8) void {
    if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "params")) {
        for (ctx.route.params) |spec| {
            if (std.mem.eql(u8, spec.name, name)) {
                pushSchemaValue(L, spec.kind, value);
                return;
            }
        }
    }
    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
}

/// Build the `params` table from the matched path captures. Always emitted
/// (empty when the route declares no params) so `c.params.x` can never raise
/// "attempt to index field 'params' (a nil value)".
fn pushParamsTable(L: *c.lua_State, ctx: anytype) void {
    if (!@hasField(@TypeOf(ctx.*), "captures")) return;
    c.lua_newtable(L);
    const captures = ctx.captures;
    for (captures.items[0..captures.len]) |item| {
        pushParamValue(L, ctx, item.name, item.value);
        c.lua_setfield(L, -2, @ptrCast(item.name.ptr));
    }
    c.lua_setfield(L, -2, "params");
}

/// Build the `query` table from the route's declared query schema. A missing
/// optional query param is deliberately left unset so it reads back as a real
/// Lua `nil`, matching the `|nil` in the generated types.
fn pushQueryTable(L: *c.lua_State, ctx: anytype, vtable: *const VTable) void {
    if (!(@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query"))) return;
    c.lua_newtable(L);
    for (ctx.route.query) |spec| {
        if (vtable.query(ctx, spec.name)) |value| {
            pushSchemaValue(L, spec.kind, value);
            c.lua_setfield(L, -2, @ptrCast(spec.name.ptr));
        }
    }
    c.lua_newtable(L);
    c.lua_pushcfunction(L, l_query);
    c.lua_setfield(L, -2, "__call");
    _ = c.lua_setmetatable(L, -2);
    c.lua_setfield(L, -2, "query");
}

pub fn pushFullRequestTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    c.lua_newtable(L);
    pushCoreContextMethods(L);

    pushParamsTable(L, ctx);
    pushQueryTable(L, ctx, vtable);

    c.lua_newtable(L);
    c.lua_setfield(L, -2, "state");

    if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
        c.lua_newtable(L);
        for (ctx.route.scope.context) |ref| {
            _ = c.lua_pushlstring(L, @ptrCast(ref.value.ptr), ref.value.len);
            c.lua_setfield(L, -2, @ptrCast(ref.key.ptr));
        }
        c.lua_setfield(L, -2, "scope");
    }

    return 1;
}

/// Context for handlers whose first parameter is named `ctx`/`c`/`context`.
///
/// This mode is what `luals_aids.lua` generates every typed route overload
/// for, so it must satisfy the generated types: those declare
/// `---@field params MeteoriteParams_<route>` on the context class, i.e. field
/// access. It previously pushed methods only, which made the framework's own
/// generated pattern fail at runtime with a 500. It now carries the same
/// `params`/`query` tables as the full request table while keeping every
/// method, so both documented access styles work.
fn pushLazyContextTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    c.lua_newtable(L);
    pushCoreContextMethods(L);
    pushParamsTable(L, ctx);
    pushQueryTable(L, ctx, vtable);
    c.lua_newtable(L);
    c.lua_setfield(L, -2, "state");
    return 1;
}

fn pushDirectParamArgs(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    var pushed: c_int = 0;
    var index: usize = 0;
    while (index < handler.nparams) : (index += 1) {
        if (vtable.param_at(ctx, index)) |value| {
            // param_at resolves positionally against route.params, so the
            // declared kind for this position is the matching spec.
            if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "params") and index < ctx.route.params.len) {
                pushSchemaValue(L, ctx.route.params[index].kind, value);
            } else {
                _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
            }
        } else {
            c.lua_pushnil(L);
        }
        pushed += 1;
    }
    return pushed;
}

pub fn pushHandlerArgs(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    return switch (handler.arg_mode) {
        .no_args => 0,
        .direct_params => pushDirectParamArgs(handler, L, ctx, vtable),
        .lazy_context => pushLazyContextTable(handler, L, ctx, vtable),
        .request_table => pushFullRequestTable(handler, L, ctx, vtable),
    };
}
