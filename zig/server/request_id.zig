const std = @import("std");

pub fn isSafe(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |ch| {
        const ok = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == ':';
        if (!ok) return false;
    }
    return true;
}
