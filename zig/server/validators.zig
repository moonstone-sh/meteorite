const std = @import("std");

/// Built-in parameter validators used by route matching.
/// These are pure functions with no dependencies on the graph or backend.

pub fn isUnsigned(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| if (c < '0' or c > '9') return false;
    return true;
}

pub fn isI32(value: []const u8) bool {
    if (value.len == 0) return false;
    const start: usize = if (value[0] == '-') 1 else 0;
    if (start == value.len) return false;
    return isUnsigned(value[start..]);
}

pub fn isSlug(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}

pub fn isHex(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

pub fn isUuid(value: []const u8) bool {
    if (value.len != 36) return false;
    for (value, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) {
            if (c != '-') return false;
        } else {
            const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
            if (!ok) return false;
        }
    }
    return true;
}

pub fn isEmail(value: []const u8) bool {
    if (value.len == 0 or value.len > 254) return false;
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return false;
    if (std.mem.indexOfScalarPos(u8, value, at + 1, '@') != null) return false;
    const local = value[0..at];
    const domain = value[at + 1 ..];
    if (local.len == 0 or local.len > 64) return false;
    if (domain.len == 0 or domain.len > 189) return false;
    if (local[0] == '.' or local[local.len - 1] == '.') return false;
    var i: usize = 1;
    while (i < local.len) : (i += 1) {
        if (local[i] == '.' and local[i - 1] == '.') return false;
    }
    for (local) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or
            c == '!' or c == '#' or c == '$' or c == '%' or c == '&' or c == 39 or c == '*' or
            c == '+' or c == '/' or c == '=' or c == '?' or c == '^' or c == '_' or c == '`' or
            c == '{' or c == '|' or c == '}' or c == '~' or c == '.' or c == '-';
        if (!ok) return false;
    }
    var label_iter = std.mem.splitScalar(u8, domain, '.');
    var labels: usize = 0;
    while (label_iter.next()) |label| {
        labels += 1;
        if (label.len == 0 or label.len > 63) return false;
        if (label[0] == '-' or label[label.len - 1] == '-') return false;
        for (label) |c| {
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-';
            if (!ok) return false;
        }
    }
    return labels >= 2;
}

pub fn isToken(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or
            c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}
