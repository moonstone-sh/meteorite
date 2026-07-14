pub const Stats = struct {
    lua_states_created: u64 = 0,
    lua_handler_refs_loaded: u64 = 0,
    lua_handler_calls: u64 = 0,
    lua_errors: u64 = 0,
    lua_state_reuse_hits: u64 = 0,
    lua_state_reuse_misses: u64 = 0,
    per_thread_state_count: u64 = 0,
};

pub const Runtime = struct {
    pub const lua_state_strategy = "none";
    pub const lua_handler_ref_strategy = "none";
    pub const capability_store_strategy = "none";
    pub const require_cache_strategy = "none";

    pub fn snapshotStats() Stats {
        return .{};
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        _ = handler;
        try ctx.text(501, "handler requires Lua runtime");
    }
};
