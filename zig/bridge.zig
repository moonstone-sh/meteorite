const std = @import("std");
const graph = @import("meteorite_graph");
const c_imports = @import("bridge/c_imports.zig");
const c = c_imports.c;
const lua_stats = @import("bridge/lua_stats.zig");
const lua_vtable = @import("bridge/lua_vtable.zig");
const lua_json = @import("bridge/lua_json.zig");
const lua_http = @import("bridge/lua_http.zig");

pub const LuaRuntimeUnavailable = struct {
    pub const lua_state_strategy = "none";
    pub const lua_handler_ref_strategy = "none";
    pub const capability_store_strategy = "none";
    pub const require_cache_strategy = "none";

    pub const Stats = LuaStats;

    pub fn snapshotStats() Stats {
        return .{};
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        _ = handler;
        try ctx.text(501, "handler requires Lua runtime");
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        _ = handler;
        _ = ctx;
        return false;
    }

    pub fn reloadAll() !void {}
};

pub const LuaStats = lua_stats.Stats;
const incLua = lua_stats.inc;
const snapshotLuaStats = lua_stats.snapshot;
const AtomicCounter = std.atomic.Value(u64);

pub const HttpClient = lua_http.HttpClient;
const encodeLuaValue = lua_json.encodeLuaValue;
const encodeJsonString = lua_json.encodeJsonString;
const HttpResponse = lua_http.HttpResponse;

pub const HybridContract = struct {
    pub const RequestLocalState = struct {
        allocator: std.mem.Allocator,
    };
};

const VTable = lua_vtable.VTable;
const makeVTable = lua_vtable.makeVTable;
const globalVtable = lua_vtable.globalVtable;

const lua_bindings = @import("bridge/lua_bindings.zig");

// Re-export bindings for runtime types to use
const upvalueIndex = lua_bindings.upvalueIndex;
const setupLuaPackagePaths = lua_bindings.setupLuaPackagePaths;
const l_text = lua_bindings.l_text;
const l_json = lua_bindings.l_json;
const l_bytes = lua_bindings.l_bytes;
const l_body = lua_bindings.l_body;
const l_param = lua_bindings.l_param;
const l_query = lua_bindings.l_query;
const l_header = lua_bindings.l_header;
const l_http = lua_bindings.l_http;
const l_http_request = lua_bindings.l_http_request;
const l_auth = lua_bindings.l_auth;
const l_auth_headers = lua_bindings.l_auth_headers;
const l_auth_authorization = lua_bindings.l_auth_authorization;
const l_zig = lua_bindings.l_zig;
const l_zig_device_name = lua_bindings.l_zig_device_name;
const l_get = lua_bindings.l_get;
const l_set = lua_bindings.l_set;
const l_debug = lua_bindings.l_debug;
const l_shared_counter = lua_bindings.l_shared_counter;
const l_worker_counter = lua_bindings.l_worker_counter;
const setClosure = lua_bindings.setClosure;
const pushResponse = lua_bindings.pushResponse;
const pushMethod = lua_bindings.pushMethod;
const getCapabilityString = lua_bindings.getCapabilityString;
const getCapabilityInt = lua_bindings.getCapabilityInt;
const lookupString = lua_bindings.lookupString;
const lookupInt = lua_bindings.lookupInt;
const lookupZig = lua_bindings.lookupZig;
pub const HybridLuaRuntime = struct {
    pub const lua_state_strategy = "per_request_state";
    pub const lua_handler_ref_strategy = "load_per_request";
    pub const capability_store_strategy = "process_shared_zig_debug_store";
    pub const require_cache_strategy = "per_request_lua_package_loaded";

    pub fn snapshotStats() LuaStats {
        return snapshotLuaStats();
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        incLua(&lua_stats.stats.lua_handler_calls);
        incLua(&lua_stats.stats.lua_state_reuse_misses);
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaOutOfMemory;
        };
        incLua(&lua_stats.stats.lua_states_created);
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        try setupLuaPackagePaths(L);

        if (c.luaL_loadfilex(L, @ptrCast(handler.path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("load handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (c.lua_pcallk(L, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("init handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("handler {s} did not return a function", .{handler.path});
            incLua(&lua_stats.stats.lua_errors);
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
        pushMethod(L, "debug", l_debug);
        pushMethod(L, "shared_counter", l_shared_counter);
        pushMethod(L, "worker_counter", l_worker_counter);

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

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        defer {
            lua_vtable.current_ctx = null;
            lua_vtable.current_vtable = null;
        }

        if (c.lua_pcallk(L, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (c.lua_istable(L, -1)) {
            _ = c.lua_getfield(L, -1, "status");
            const status: u16 = if (c.lua_isinteger(L, -1) != 0) @intCast(c.lua_tointegerx(L, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L, 1);

            _ = c.lua_getfield(L, -1, "content_type");
            _ = c.lua_getfield(L, -2, "body");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L, -2, &content_type_len);
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (content_type_ptr != null) {
                const ct = content_type_ptr[0..content_type_len];
                if (std.mem.eql(u8, ct, "application/json")) {
                    try lua_vtable.current_vtable.?.json(lua_vtable.current_ctx.?, status, body);
                } else {
                    try lua_vtable.current_vtable.?.bytes(lua_vtable.current_ctx.?, status, ct, body);
                }
            } else {
                try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, status, body);
            }
            c.lua_pop(L, 3);
        } else if (c.lua_isstring(L, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, -1, &len);
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L, 1);
        } else {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        incLua(&lua_stats.stats.lua_handler_calls);
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state for plugin", .{});
            incLua(&lua_stats.stats.lua_errors);
            return false;
        };
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        setupLuaPackagePaths(L) catch return false;

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (c.luaL_loadfilex(L, @ptrCast(plugin_path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
            std.log.err("load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }
        if (c.lua_pcallk(L, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return false;
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
        pushMethod(L, "debug", l_debug);
        pushMethod(L, "shared_counter", l_shared_counter);
        pushMethod(L, "worker_counter", l_worker_counter);

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

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        defer {
            lua_vtable.current_ctx = null;
            lua_vtable.current_vtable = null;
        }

        if (c.lua_pcallk(L, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }

        if (c.lua_istable(L, -1)) {
            _ = c.lua_getfield(L, -1, "status");
            const status: u16 = if (c.lua_isinteger(L, -1) != 0) @intCast(c.lua_tointegerx(L, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L, 1);
            _ = c.lua_getfield(L, -1, "content_type");
            _ = c.lua_getfield(L, -2, "body");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L, -2, &content_type_len);
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (content_type_ptr != null) {
                const ct = content_type_ptr[0..content_type_len];
                if (std.mem.eql(u8, ct, "application/json")) {
                    try lua_vtable.current_vtable.?.json(lua_vtable.current_ctx.?, status, body);
                } else {
                    try lua_vtable.current_vtable.?.bytes(lua_vtable.current_ctx.?, status, ct, body);
                }
            } else {
                try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, status, body);
            }
            c.lua_pop(L, 3);
            return true;
        } else if (c.lua_isstring(L, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, -1, &len);
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L, 1);
            return true;
        }
        c.lua_pop(L, 1);
        return false;
    }
};

const graph_cached = graph;

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
    pub const lua_state_strategy = "per_thread_cached_refs";
    pub const lua_handler_ref_strategy = "per_thread_registry_refs";
    pub const capability_store_strategy = "process_shared_zig_debug_store";
    pub const require_cache_strategy = "per_thread_package_loaded";

    pub fn snapshotStats() LuaStats {
        return snapshotLuaStats();
    }

    threadlocal var L: ?*c.lua_State = null;
    threadlocal var refs: [inlineLuaRouteCount()]c_int = undefined;
    threadlocal var initialized: bool = false;
    threadlocal var loaded_reload_epoch: u64 = 0;
    var reload_epoch = AtomicCounter.init(0);

    fn init() !void {
        if (initialized) {
            incLua(&lua_stats.stats.lua_state_reuse_hits);
            return;
        }
        incLua(&lua_stats.stats.lua_state_reuse_misses);
        L = c.luaL_newstate() orelse {
            std.log.err("failed to create cached Lua state", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaOutOfMemory;
        };
        incLua(&lua_stats.stats.lua_states_created);
        c.luaL_openlibs(L.?);

        try setupLuaPackagePaths(L);

        comptime var idx: usize = 0;
        inline for (graph_cached.routes) |route| {
            if (route.handler == .inline_lua) {
                const handler = route.handler.inline_lua;
                try loadHandlerRef(idx, handler, false);
                idx += 1;
            }
        }
        loaded_reload_epoch = reload_epoch.load(.acquire);
        initialized = true;
    }

    fn reloadRefs() !void {
        comptime var idx: usize = 0;
        inline for (graph_cached.routes) |route| {
            if (route.handler == .inline_lua) {
                try loadHandlerRef(idx, route.handler.inline_lua, true);
                idx += 1;
            }
        }
    }

    fn refreshIfStale() !void {
        const current_epoch = reload_epoch.load(.acquire);
        if (loaded_reload_epoch == current_epoch) return;
        try reloadRefs();
        loaded_reload_epoch = current_epoch;
    }

    fn loadHandlerRef(comptime idx: usize, comptime handler: graph_cached.InlineLuaHandler, comptime replace: bool) !void {
        if (replace) c.luaL_unref(L.?, c.LUA_REGISTRYINDEX, refs[idx]);
        if (c.luaL_loadfilex(L.?, @ptrCast(handler.chunk_path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
            std.log.err("cached load handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (c.lua_pcallk(L.?, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("cached init handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L.?, -1)) {
            std.log.err("cached handler {s} did not return a function", .{handler.chunk_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }
        refs[idx] = c.luaL_ref(L.?, c.LUA_REGISTRYINDEX);
        incLua(&lua_stats.stats.lua_handler_refs_loaded);
    }

    pub fn reloadAll() !void {
        try init();
        try reloadRefs();
        loaded_reload_epoch = reload_epoch.fetchAdd(1, .acq_rel) + 1;
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        incLua(&lua_stats.stats.lua_handler_calls);
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        try refreshIfStale();
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
        pushMethod(L2, "debug", l_debug);
        pushMethod(L2, "shared_counter", l_shared_counter);
        pushMethod(L2, "worker_counter", l_worker_counter);

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

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
            c.lua_newtable(L2);
            for (ctx.route.scope.context) |ref| {
                _ = c.lua_pushlstring(L2, @ptrCast(ref.value.ptr), ref.value.len);
                c.lua_setfield(L2, -2, @ptrCast(ref.key.ptr));
            }
            c.lua_setfield(L2, -2, "scope");
        }

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        defer {
            lua_vtable.current_ctx = null;
            lua_vtable.current_vtable = null;
        }

        if (c.lua_pcallk(L2, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            const err = c.lua_tolstring(L2, -1, null);
            std.log.err("cached handler {s}: {s}", .{ handler.id, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (c.lua_istable(L2, -1)) {
            _ = c.lua_getfield(L2, -1, "status");
            const status: u16 = if (c.lua_isinteger(L2, -1) != 0) @intCast(c.lua_tointegerx(L2, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L2, 1);

            _ = c.lua_getfield(L2, -1, "content_type");
            _ = c.lua_getfield(L2, -2, "body");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L2, -2, &content_type_len);
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L2, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (content_type_ptr != null) {
                const ct = content_type_ptr[0..content_type_len];
                if (std.mem.eql(u8, ct, "application/json")) {
                    try lua_vtable.current_vtable.?.json(lua_vtable.current_ctx.?, status, body);
                } else {
                    try lua_vtable.current_vtable.?.bytes(lua_vtable.current_ctx.?, status, ct, body);
                }
            } else {
                try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, status, body);
            }
            c.lua_pop(L2, 3);
        } else if (c.lua_isstring(L2, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L2, -1, &len);
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L2, 1);
        } else {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L2, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        incLua(&lua_stats.stats.lua_handler_calls);
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        const L2 = L.?;

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (c.luaL_loadfilex(L2, @ptrCast(plugin_path.ptr), @as([*c]const u8, null)) != c.LUA_OK) {
            std.log.err("cached load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }
        if (c.lua_pcallk(L2, 0, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("cached init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }
        if (!c.lua_isfunction(L2, -1)) {
            std.log.err("cached plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }

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
        pushMethod(L2, "debug", l_debug);
        pushMethod(L2, "shared_counter", l_shared_counter);
        pushMethod(L2, "worker_counter", l_worker_counter);

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

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
            c.lua_newtable(L2);
            for (ctx.route.scope.context) |ref| {
                _ = c.lua_pushlstring(L2, @ptrCast(ref.value.ptr), ref.value.len);
                c.lua_setfield(L2, -2, @ptrCast(ref.key.ptr));
            }
            c.lua_setfield(L2, -2, "scope");
        }

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        defer {
            lua_vtable.current_ctx = null;
            lua_vtable.current_vtable = null;
        }

        if (c.lua_pcallk(L2, 1, 1, 0, 0, @as(c.lua_KFunction, null)) != c.LUA_OK) {
            std.log.err("cached plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return false;
        }

        if (c.lua_istable(L2, -1)) {
            _ = c.lua_getfield(L2, -1, "status");
            const status: u16 = if (c.lua_isinteger(L2, -1) != 0) @intCast(c.lua_tointegerx(L2, -1, @as([*c]c_int, null))) else 200;
            c.lua_pop(L2, 1);
            _ = c.lua_getfield(L2, -1, "content_type");
            _ = c.lua_getfield(L2, -2, "body");
            var content_type_len: usize = 0;
            const content_type_ptr = c.lua_tolstring(L2, -2, &content_type_len);
            var body_len: usize = 0;
            const body_ptr = c.lua_tolstring(L2, -1, &body_len);
            const body = body_ptr[0..body_len];

            if (content_type_ptr != null) {
                const ct = content_type_ptr[0..content_type_len];
                if (std.mem.eql(u8, ct, "application/json")) {
                    try lua_vtable.current_vtable.?.json(lua_vtable.current_ctx.?, status, body);
                } else {
                    try lua_vtable.current_vtable.?.bytes(lua_vtable.current_ctx.?, status, ct, body);
                }
            } else {
                try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, status, body);
            }
            c.lua_pop(L2, 3);
            return true;
        } else if (c.lua_isstring(L2, -1) != 0) {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L2, -1, &len);
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 200, ptr[0..len]);
            c.lua_pop(L2, 1);
            return true;
        }
        c.lua_pop(L2, 1);
        return false;
    }
};
