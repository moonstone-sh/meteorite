const std = @import("std");
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
const setupLuaPackagePaths = lua_bindings.setupLuaPackagePaths;
const installGlobalResponseHelpers = lua_bindings.installGlobalResponseHelpers;
const globalVtable = lua_vtable.globalVtable;

pub const HybridLuaRuntime = struct {
    pub const lua_state_strategy = "per_request_state";
    pub const lua_handler_ref_strategy = "load_per_request";
    pub const capability_store_strategy = "process_shared_zig_debug_store";
    pub const require_cache_strategy = "per_request_lua_package_loaded";

    pub fn snapshotStats() LuaStats {
        return snapshotLuaStats();
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
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
        installGlobalResponseHelpers(L);

        if (loadfile(L, @ptrCast(handler.path.ptr)) != LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("load handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (pcall(L, 0, 1, 0) != LUA_OK) {
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

        const nargs = lua_context.pushHandlerArgs(handler, L, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (@hasField(@TypeOf(handler), "bench_route")) lua_bench_stats.incLuaPcallByPath(handler.bench_route);
        if (pcall(L, nargs, 1, 0) != LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L, 1);
            return;
        }

        if (!try lua_response.finish(L, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state for plugin", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        };
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        setupLuaPackagePaths(L) catch return error.LuaRuntimeError;
        installGlobalResponseHelpers(L);

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (loadfile(L, @ptrCast(plugin_path.ptr)) != LUA_OK) {
            std.log.err("load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (pcall(L, 0, 1, 0) != LUA_OK) {
            std.log.err("init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }

        _ = lua_context.pushFullRequestTable(handler, L, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (pcall(L, 1, 1, 0) != LUA_OK) {
            std.log.err("plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L, 1);
            return true;
        }

        if (try lua_response.finish(L, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) return true;
        c.lua_pop(L, 1);
        return false;
    }
};
