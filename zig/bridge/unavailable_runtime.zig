const lua_stats = @import("lua_stats.zig");

pub const LuaRuntimeUnavailable = struct {
    pub const lua_state_strategy = "none";
    pub const lua_handler_ref_strategy = "none";
    pub const capability_store_strategy = "none";
    pub const require_cache_strategy = "none";

    pub const Stats = lua_stats.Stats;

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
