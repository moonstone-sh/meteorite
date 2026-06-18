const std = @import("std");

pub const lua_exports = .{
    .device_name = deviceName,
};

pub fn deviceName(ctx: anytype, device_id: []const u8) ![]const u8 {
    _ = ctx;
    if (std.mem.eql(u8, device_id, "router_01")) return "Router 01";
    return device_id;
}
