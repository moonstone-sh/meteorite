const std = @import("std");

pub const LuaRuntimeUnavailable = struct {
    pub fn call(comptime id: []const u8, ctx: anytype) !void {
        _ = id;
        try ctx.text(501, "handler requires Lua runtime");
    }
};

pub const HybridContract = struct {
    pub const RequestLocalState = struct {
        allocator: std.mem.Allocator,
    };
};
