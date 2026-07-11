const std = @import("std");
const meteorite_protocol = @import("meteorite_protocol");

pub const version: u16 = 0;
pub const max_frame_size: usize = 16 * 1024 * 1024;
pub const max_route_len: usize = 4 * 1024;
pub const max_metadata_len: usize = 64 * 1024;
pub const max_body_len: usize = max_frame_size;
pub const request_header_len: usize = 20;
pub const response_header_len: usize = 22;

pub const FrameError = error{
    FrameTooSmall,
    FrameTooLarge,
    LengthMismatch,
    UnsupportedVersion,
    UnsupportedFlags,
    RouteTooLarge,
    MetadataTooLarge,
    BodyTooLarge,
    InvalidLength,
    BufferTooSmall,
};

pub const RequestFrame = struct {
    version: u16,
    flags: u16,
    request_id: u64,
    route: []const u8,
    metadata: []const u8,
    body: []const u8,
};

pub const ResponseFrame = struct {
    flags: u16 = 0,
    request_id: u64,
    result: meteorite_protocol.ResultCode = .ok,
    content_type: []const u8 = "text/plain; charset=utf-8",
    metadata: []const u8 = "",
    body: []const u8 = "",
};

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

fn readU64(bytes: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writeU64(bytes: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
}

pub fn parseRequestFrame(frame: []const u8) FrameError!RequestFrame {
    if (frame.len < 4 + request_header_len) return error.FrameTooSmall;
    if (frame.len > max_frame_size) return error.FrameTooLarge;
    const declared_len = readU32(frame, 0);
    if (declared_len > max_frame_size - 4) return error.FrameTooLarge;
    if (declared_len != frame.len - 4) return error.LengthMismatch;

    const frame_version = readU16(frame, 4);
    const flags = readU16(frame, 6);
    if (frame_version != version) return error.UnsupportedVersion;
    if (flags != 0) return error.UnsupportedFlags;

    const request_id = readU64(frame, 8);
    const route_len: usize = readU16(frame, 16);
    const metadata_len: usize = readU16(frame, 18);
    const body_len: usize = readU32(frame, 20);
    if (route_len > max_route_len) return error.RouteTooLarge;
    if (metadata_len > max_metadata_len) return error.MetadataTooLarge;
    if (body_len > max_body_len) return error.BodyTooLarge;

    const payload_len = route_len + metadata_len + body_len;
    if (payload_len > max_frame_size - request_header_len) return error.FrameTooLarge;
    if (4 + request_header_len + payload_len != frame.len) return error.InvalidLength;

    const route_start = 4 + request_header_len;
    const metadata_start = route_start + route_len;
    const body_start = metadata_start + metadata_len;
    return .{
        .version = frame_version,
        .flags = flags,
        .request_id = request_id,
        .route = frame[route_start..metadata_start],
        .metadata = frame[metadata_start..body_start],
        .body = frame[body_start..][0..body_len],
    };
}

pub fn peekRequestId(frame: []const u8) ?u64 {
    if (frame.len < 16) return null;
    return readU64(frame, 8);
}

pub fn requestFrameLen(route_len: usize, metadata_len: usize, body_len: usize) FrameError!usize {
    if (route_len > max_route_len) return error.RouteTooLarge;
    if (metadata_len > max_metadata_len) return error.MetadataTooLarge;
    if (body_len > max_body_len) return error.BodyTooLarge;
    const total = 4 + request_header_len + route_len + metadata_len + body_len;
    if (total > max_frame_size) return error.FrameTooLarge;
    return total;
}

pub fn writeRequestFrame(buffer: []u8, request_id: u64, route: []const u8, metadata: []const u8, body: []const u8) FrameError![]u8 {
    const total = try requestFrameLen(route.len, metadata.len, body.len);
    if (buffer.len < total) return error.BufferTooSmall;
    writeU32(buffer, 0, @intCast(total - 4));
    writeU16(buffer, 4, version);
    writeU16(buffer, 6, 0);
    writeU64(buffer, 8, request_id);
    writeU16(buffer, 16, @intCast(route.len));
    writeU16(buffer, 18, @intCast(metadata.len));
    writeU32(buffer, 20, @intCast(body.len));
    var offset: usize = 4 + request_header_len;
    @memcpy(buffer[offset..][0..route.len], route);
    offset += route.len;
    @memcpy(buffer[offset..][0..metadata.len], metadata);
    offset += metadata.len;
    @memcpy(buffer[offset..][0..body.len], body);
    return buffer[0..total];
}

pub fn responseFrameLen(content_type_len: usize, metadata_len: usize, body_len: usize) FrameError!usize {
    if (content_type_len > max_metadata_len) return error.MetadataTooLarge;
    if (metadata_len > max_metadata_len) return error.MetadataTooLarge;
    if (body_len > max_body_len) return error.BodyTooLarge;
    const total = 4 + response_header_len + content_type_len + metadata_len + body_len;
    if (total > max_frame_size) return error.FrameTooLarge;
    return total;
}

pub fn writeResponseFrame(buffer: []u8, response: ResponseFrame) FrameError![]u8 {
    const total = try responseFrameLen(response.content_type.len, response.metadata.len, response.body.len);
    if (buffer.len < total) return error.BufferTooSmall;
    writeU32(buffer, 0, @intCast(total - 4));
    writeU16(buffer, 4, version);
    writeU16(buffer, 6, response.flags);
    writeU64(buffer, 8, response.request_id);
    writeU16(buffer, 16, @intFromEnum(response.result));
    writeU16(buffer, 18, @intCast(response.content_type.len));
    writeU16(buffer, 20, @intCast(response.metadata.len));
    writeU32(buffer, 22, @intCast(response.body.len));
    var offset: usize = 4 + response_header_len;
    @memcpy(buffer[offset..][0..response.content_type.len], response.content_type);
    offset += response.content_type.len;
    @memcpy(buffer[offset..][0..response.metadata.len], response.metadata);
    offset += response.metadata.len;
    @memcpy(buffer[offset..][0..response.body.len], response.body);
    return buffer[0..total];
}

test "parse valid request frame" {
    var buffer: [128]u8 = undefined;
    const frame = try writeRequestFrame(&buffer, 42, "users.get", "content_type=application/json\n", "{\"id\":1}");
    const parsed = try parseRequestFrame(frame);
    try std.testing.expectEqual(@as(u64, 42), parsed.request_id);
    try std.testing.expectEqualStrings("users.get", parsed.route);
    try std.testing.expectEqualStrings("content_type=application/json\n", parsed.metadata);
    try std.testing.expectEqualStrings("{\"id\":1}", parsed.body);
}

test "reject partial frame" {
    var buffer: [64]u8 = undefined;
    const frame = try writeRequestFrame(&buffer, 1, "a.b", "", "");
    try std.testing.expectError(error.LengthMismatch, parseRequestFrame(frame[0 .. frame.len - 1]));
}

test "reject oversized route" {
    var route: [max_route_len + 1]u8 = undefined;
    @memset(&route, 'a');
    var buffer: [max_route_len + 64]u8 = undefined;
    try std.testing.expectError(error.RouteTooLarge, writeRequestFrame(&buffer, 1, &route, "", ""));
}

test "reject unsupported version" {
    var buffer: [64]u8 = undefined;
    const frame = try writeRequestFrame(&buffer, 1, "a.b", "", "");
    writeU16(frame, 4, 99);
    try std.testing.expectError(error.UnsupportedVersion, parseRequestFrame(frame));
}

test "reject unsupported flags" {
    var buffer: [64]u8 = undefined;
    const frame = try writeRequestFrame(&buffer, 1, "a.b", "", "");
    writeU16(frame, 6, 1);
    try std.testing.expectError(error.UnsupportedFlags, parseRequestFrame(frame));
}

test "write response frame" {
    var buffer: [128]u8 = undefined;
    const frame = try writeResponseFrame(&buffer, .{ .request_id = 7, .result = .validation_error, .content_type = "text/plain", .metadata = "field=id\n", .body = "bad" });
    try std.testing.expectEqual(@as(u32, @intCast(frame.len - 4)), readU32(frame, 0));
    try std.testing.expectEqual(@as(u64, 7), readU64(frame, 8));
    try std.testing.expectEqual(@as(u16, @intFromEnum(meteorite_protocol.ResultCode.validation_error)), readU16(frame, 16));
    try std.testing.expectEqualStrings("text/plain", frame[26..36]);
}
