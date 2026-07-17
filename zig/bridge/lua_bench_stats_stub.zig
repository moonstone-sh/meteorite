const std = @import("std");

pub fn incLuaPcallByPath(_: []const u8) void {}
pub fn incNativeByName(_: []const u8) void {}
pub fn reset() void {}

pub fn writeJson(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\"routes\":{}}");
}
