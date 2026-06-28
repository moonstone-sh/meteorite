const std = @import("std");
const Io = std.Io;

/// Static file serving: path normalization, compression negotiation,
/// ETag matching, and file reading.
/// Extracted from meteorite.zig for readability.

pub const SelectedAsset = struct {
    path: []const u8,
    length: u64,
    etag: []const u8,
    encoding: []const u8,
};

/// Normalize a static path captured from a route parameter.
/// Rejects path traversal, NUL bytes, backslashes, and malformed percent-encoding.
/// Returns an allocated, normalized path that must be freed by the caller.
pub fn normalizeStaticPath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len == 0 or raw[0] == '/' or raw[0] == '\\') return error.InvalidStaticPath;
    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(allocator);
    var i: usize = 0;
    while (i < raw.len) {
        const ch = raw[i];
        if (ch == 0 or ch == '\\') return error.InvalidStaticPath;
        if (ch == '%') {
            if (i + 2 >= raw.len) return error.InvalidStaticPath;
            const hi = std.fmt.charToDigit(raw[i + 1], 16) catch return error.InvalidStaticPath;
            const lo = std.fmt.charToDigit(raw[i + 2], 16) catch return error.InvalidStaticPath;
            const decoded_ch: u8 = @intCast((hi << 4) | lo);
            if (decoded_ch == 0 or decoded_ch == '/' or decoded_ch == '\\') return error.InvalidStaticPath;
            try decoded.append(allocator, decoded_ch);
            i += 3;
            continue;
        }
        try decoded.append(allocator, ch);
        i += 1;
    }
    var parts = std.mem.splitScalar(u8, decoded.items, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidStaticPath;
    }
    return decoded.toOwnedSlice(allocator);
}

/// Check if the If-None-Match header matches the given ETag.
pub fn ifNoneMatch(header_value: []const u8, etag: []const u8) bool {
    var it = std.mem.splitScalar(u8, header_value, ',');
    while (it.next()) |item| {
        const candidate = std.mem.trim(u8, item, " \t");
        if (std.mem.eql(u8, candidate, "*")) return true;
        if (std.mem.eql(u8, candidate, etag)) return true;
        if (std.mem.startsWith(u8, candidate, "W/") and std.mem.eql(u8, candidate[2..], etag)) return true;
    }
    return false;
}

/// Check if an Accept-Encoding header value contains a specific encoding.
pub fn tokenListContains(header_value: []const u8, expected: []const u8) bool {
    var it = std.mem.splitScalar(u8, header_value, ',');
    while (it.next()) |raw_item| {
        const item = std.mem.trim(u8, raw_item, " \t");
        const token_end = std.mem.indexOfScalar(u8, item, ';') orelse item.len;
        if (!qualityIsZero(item) and std.ascii.eqlIgnoreCase(std.mem.trim(u8, item[0..token_end], " \t"), expected)) return true;
    }
    return false;
}

pub fn qualityIsZero(item: []const u8) bool {
    var params = std.mem.splitScalar(u8, item, ';');
    _ = params.next();
    while (params.next()) |raw_param| {
        const param = std.mem.trim(u8, raw_param, " \t");
        if (std.mem.startsWith(u8, param, "q=")) {
            const value = std.mem.trim(u8, param[2..], " \t");
            if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "0.0") or std.mem.eql(u8, value, "0.00") or std.mem.eql(u8, value, "0.000")) return true;
        }
    }
    return false;
}

/// Read a file from an artifact path, resolving relative to the executable directory.
pub fn readArtifactFile(allocator: std.mem.Allocator, io: Io, artifact_path: []const u8, content_length: u64) ![]u8 {
    const limit = Io.Limit.limited64(content_length + 1);
    if (std.fs.path.isAbsolute(artifact_path)) return std.Io.Dir.cwd().readFileAlloc(io, artifact_path, allocator, limit);
    const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(exe_dir);
    const full_path = try std.fs.path.join(allocator, &.{ exe_dir, artifact_path });
    defer allocator.free(full_path);
    return std.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, limit) catch |err| switch (err) {
        error.FileNotFound => {
            const release_root_path = try std.fs.path.join(allocator, &.{ exe_dir, "..", artifact_path });
            defer allocator.free(release_root_path);
            return std.Io.Dir.cwd().readFileAlloc(io, release_root_path, allocator, limit);
        },
        else => return err,
    };
}
