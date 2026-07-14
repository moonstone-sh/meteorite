const std = @import("std");

pub const Lookup = union(enum) {
    missing,
    invalid,
    value: []const u8,
};

pub fn trimCookieSpace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t");
}

pub fn cookieValue(header_value: []const u8, wanted: []const u8) Lookup {
    var found: ?[]const u8 = null;
    var fields = std.mem.splitScalar(u8, header_value, ';');
    while (fields.next()) |field| {
        const pair = trimCookieSpace(field);
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const name = trimCookieSpace(pair[0..eq]);
        if (std.mem.eql(u8, name, wanted)) {
            if (found != null) return .invalid;
            var raw_value = trimCookieSpace(pair[eq + 1 ..]);
            if (raw_value.len >= 2 and raw_value[0] == '"') {
                if (raw_value[raw_value.len - 1] != '"') return .invalid;
                raw_value = raw_value[1 .. raw_value.len - 1];
            } else if (std.mem.indexOfScalar(u8, raw_value, '"') != null) {
                return .invalid;
            }
            found = raw_value;
        }
    }
    if (found) |value| return .{ .value = value };
    return .missing;
}

pub fn contentTypeIs(content_type: []const u8, expected: []const u8) bool {
    const media_end = std.mem.indexOfScalar(u8, content_type, ';') orelse content_type.len;
    const media_type = std.mem.trim(u8, content_type[0..media_end], " \t");
    return std.ascii.eqlIgnoreCase(media_type, expected);
}

pub fn formComponentValid(value: []const u8) bool {
    var index: usize = 0;
    while (index < value.len) {
        const ch = value[index];
        if (ch == '%') {
            if (index + 2 >= value.len) return false;
            _ = std.fmt.charToDigit(value[index + 1], 16) catch return false;
            _ = std.fmt.charToDigit(value[index + 2], 16) catch return false;
            index += 3;
        } else {
            if (ch == 0 or ch == '\r' or ch == '\n') return false;
            index += 1;
        }
    }
    return true;
}

pub fn formValue(body: []const u8, wanted: []const u8) Lookup {
    var found: ?[]const u8 = null;
    var pairs = std.mem.splitScalar(u8, body, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const name = pair[0..eq];
        const value = if (eq < pair.len) pair[eq + 1 ..] else "";
        if (!formComponentValid(name) or !formComponentValid(value) or name.len == 0) return .invalid;
        if (std.mem.eql(u8, name, wanted)) {
            if (found != null) return .invalid;
            found = value;
        }
    }
    if (found) |value| return .{ .value = value };
    return .missing;
}

pub fn rawQueryValue(raw_query: []const u8, name: []const u8) ?[]const u8 {
    if (raw_query.len == 0) return null;
    var parts = std.mem.splitScalar(u8, raw_query, '&');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
        if (std.mem.eql(u8, part[0..eq], name)) {
            return if (eq < part.len) part[eq + 1 ..] else "";
        }
    }
    return null;
}

pub fn percentDecode(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, value.len);
    var out_len: usize = 0;
    var i: usize = 0;
    while (i < value.len) {
        if (value[i] == '%' and i + 2 < value.len) {
            const hi = std.fmt.charToDigit(value[i + 1], 16) catch {
                out[out_len] = value[i];
                out_len += 1;
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(value[i + 2], 16) catch {
                out[out_len] = value[i];
                out_len += 1;
                i += 1;
                continue;
            };
            out[out_len] = @intCast((hi << 4) | lo);
            out_len += 1;
            i += 3;
        } else {
            out[out_len] = value[i];
            out_len += 1;
            i += 1;
        }
    }
    return out[0..out_len];
}

pub fn queryValue(allocator: std.mem.Allocator, raw_query: []const u8, name: []const u8) ?[]const u8 {
    const raw = rawQueryValue(raw_query, name) orelse return null;
    if (std.mem.indexOfScalar(u8, raw, '%') == null) return raw;
    return percentDecode(allocator, raw) catch null;
}

pub fn queryAllValues(allocator: std.mem.Allocator, raw_query: []const u8, name: []const u8) ?[][]const u8 {
    if (raw_query.len == 0) return null;
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, raw_query, '&');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
        if (std.mem.eql(u8, part[0..eq], name)) count += 1;
    }
    if (count == 0) return null;
    var result = allocator.alloc([]const u8, count) catch return null;
    var idx: usize = 0;
    parts = std.mem.splitScalar(u8, raw_query, '&');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
        if (std.mem.eql(u8, part[0..eq], name)) {
            const raw = if (eq < part.len) part[eq + 1 ..] else "";
            if (std.mem.indexOfScalar(u8, raw, '%') == null) {
                result[idx] = raw;
            } else {
                result[idx] = percentDecode(allocator, raw) catch raw;
            }
            idx += 1;
        }
    }
    return result;
}
