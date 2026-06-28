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
