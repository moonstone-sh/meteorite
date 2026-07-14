const std = @import("std");
const graph = @import("meteorite_graph");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const lua_stats = @import("lua_stats.zig");
const lua_vtable = @import("lua_vtable.zig");
const lua_abi = @import("lua_abi.zig");
const lua_context = @import("lua_context.zig");
const lua_response = @import("lua_response.zig");
const lua_bench_stats = @import("bridge/lua_bench_stats");
const lua_bindings = @import("lua_bindings.zig");

const LUA_OK = lua_abi.LUA_OK;
const pcall = lua_abi.pcall;
const loadfile = lua_abi.loadfile;
const incLua = lua_stats.inc;
const snapshotLuaStats = lua_stats.snapshot;
const LuaStats = lua_stats.Stats;
const AtomicCounter = std.atomic.Value(u64);
const setupLuaPackagePaths = lua_bindings.setupLuaPackagePaths;
const installGlobalResponseHelpers = lua_bindings.installGlobalResponseHelpers;
const upvalueIndex = lua_bindings.upvalueIndex;
const globalVtable = lua_vtable.globalVtable;

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
        installGlobalResponseHelpers(L);

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
        if (loadfile(L.?, @ptrCast(handler.chunk_path.ptr)) != LUA_OK) {
            std.log.err("cached load handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (pcall(L.?, 0, 1, 0) != LUA_OK) {
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
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        try refreshIfStale();
        const L2 = L.?;

        const idx = comptime routeIndexCached(handler.id);
        _ = c.lua_rawgeti(L2, c.LUA_REGISTRYINDEX, refs[idx]);

        const nargs = lua_context.pushHandlerArgs(handler, L2, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (@hasField(@TypeOf(handler), "bench_route")) lua_bench_stats.incLuaPcallByPath(handler.bench_route);
        if (pcall(L2, nargs, 1, 0) != LUA_OK) {
            const err = c.lua_tolstring(L2, -1, null);
            std.log.err("cached handler {s}: {s}", .{ handler.id, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L2, 1);
            return;
        }

        if (!try lua_response.finish(L2, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L2, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        const L2 = L.?;

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (loadfile(L2, @ptrCast(plugin_path.ptr)) != LUA_OK) {
            std.log.err("cached load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (pcall(L2, 0, 1, 0) != LUA_OK) {
            std.log.err("cached init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L2, -1)) {
            std.log.err("cached plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }

        _ = lua_context.pushFullRequestTable(handler, L2, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer {
            lua_vtable.resetCurrent();
        }

        if (pcall(L2, 1, 1, 0) != LUA_OK) {
            std.log.err("cached plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L2, 1);
            return true;
        }

        if (try lua_response.finish(L2, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) return true;
        c.lua_pop(L2, 1);
        return false;
    }
};
