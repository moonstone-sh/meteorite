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

pub fn pushFullRequestTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    c.lua_newtable(L);
    pushCoreContextMethods(L);

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

fn pushLazyContextTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    _ = ctx;
    _ = vtable;
    c.lua_newtable(L);
    pushCoreContextMethods(L);
    c.lua_newtable(L);
    c.lua_setfield(L, -2, "state");
    return 1;
}

fn pushDirectParamArgs(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    var pushed: c_int = 0;
    var index: usize = 0;
    while (index < handler.nparams) : (index += 1) {
        if (vtable.param_at(ctx, index)) |value| {
            _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
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

