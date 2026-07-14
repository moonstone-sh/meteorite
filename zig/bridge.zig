const std = @import("std");
const lua_stats = @import("bridge/lua_stats.zig");
const lua_http = @import("bridge/lua_http.zig");

pub const LuaRuntimeUnavailable = @import("bridge/unavailable_runtime.zig").LuaRuntimeUnavailable;
pub const HybridLuaRuntime = @import("bridge/hybrid_runtime.zig").HybridLuaRuntime;
pub const CachedHybridRuntime = @import("bridge/cached_runtime.zig").CachedHybridRuntime;
pub const LuaStats = lua_stats.Stats;
pub const HttpClient = lua_http.HttpClient;

pub const HybridContract = struct {
    pub const RequestLocalState = struct {
        allocator: std.mem.Allocator,
    };
};
