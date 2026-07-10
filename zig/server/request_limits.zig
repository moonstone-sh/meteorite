const std = @import("std");

/// Request target and body limit enforcement.
/// Extracted from meteorite.zig for readability.

pub fn countQueryPairs(query_value: []const u8) usize {
    if (query_value.len == 0) return 0;
    var count: usize = 1;
    for (query_value) |byte| {
        if (byte == '&') count += 1;
    }
    return count;
}

pub fn countPathSegments(path_value: []const u8) usize {
    if (std.mem.eql(u8, path_value, "/")) return 0;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, path_value, '/');
    while (it.next()) |segment| {
        if (segment.len > 0) count += 1;
    }
    return count;
}

pub fn queryEncodingValid(query_value: []const u8) bool {
    var index: usize = 0;
    while (index < query_value.len) {
        const byte = query_value[index];
        if (byte == 0 or byte == '\r' or byte == '\n') return false;
        if (byte == '%') {
            if (index + 2 >= query_value.len) return false;
            const hi = std.fmt.charToDigit(query_value[index + 1], 16) catch return false;
            const lo = std.fmt.charToDigit(query_value[index + 2], 16) catch return false;
            const decoded: u8 = @intCast((hi << 4) | lo);
            if (decoded == 0 or decoded == '\r' or decoded == '\n') return false;
            index += 3;
            continue;
        }
        index += 1;
    }
    return true;
}
