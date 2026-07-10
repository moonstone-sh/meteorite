const std = @import("std");
const Io = std.Io;
const proto = @import("meteorite_protocol");
const http_date = @import("../server/http_date.zig");

pub const name = "std_http";
pub const connection_strategy = "std_http_single_connection_loop";
pub const bounded = true;
pub const threaded_connections = false;
pub const pooled_connections = false;
pub const configured_workers: u16 = 0;
pub const queue_limit: usize = 0;

pub const Method = proto.Method;
pub const Header = proto.Header;
pub const Counters = proto.Counters;

const AtomicCounters = proto.AtomicCounters;
var counters = AtomicCounters{};

pub fn snapshotCounters() Counters {
    // std_http doesn't use queue or dropped counters
    var c = proto.snapshotCounters(&counters);
    c.queue_depth = 0;
    c.max_queue_depth = 0;
    c.dropped_connections = 0;
    return c;
}

pub fn connectionStarted() void {
    proto.connectionStarted(&counters);
}
pub fn connectionEnded() void {
    proto.connectionEnded(&counters);
}
pub fn requestStarted() void {
    proto.requestStarted(&counters);
}
pub fn requestCompleted() void {
    proto.requestCompleted(&counters);
}
pub fn threadSpawned() void {
    proto.threadSpawned(&counters);
}
pub fn connectionError() void {
    proto.connectionError(&counters);
}
pub fn droppedConnection() void {
    proto.droppedConnection(&counters);
}
pub fn setQueueDepth(_: u64) void {}
pub fn resetAuditCounters() void {
    proto.resetAuditCounters(&counters);
}

pub const ListenConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    io: Io,
};

pub const Server = struct {
    io: Io,
    inner: Io.net.Server,

    pub fn deinit(self: *Server) void {
        self.inner.deinit(self.io);
    }
};

pub const Request = struct {
    stream: Io.net.Stream,
    recv_buffer: [8192]u8 = undefined,
    send_buffer: [8192]u8 = undefined,
    reader: Io.net.Stream.Reader = undefined,
    writer: Io.net.Stream.Writer = undefined,
    server: std.http.Server = undefined,
    inner: std.http.Server.Request = undefined,
    closed: bool = false,
    close_after_response: bool = true,
    body_cache: ?[]const u8 = null,
    request_count: u64 = 0,
    date_seconds: i64 = 0,
    target_value: []const u8 = "",
    target_storage: [4096]u8 = undefined,

    pub fn close(self: *Request, io: Io) void {
        if (!self.closed) {
            self.closed = true;
            proto.inc(&counters.connection_close_count);
            self.stream.close(io);
        }
    }
};

pub fn listen(config: ListenConfig) !Server {
    const address = Io.net.IpAddress.parse(config.host, config.port) catch unreachable;
    return .{
        .io = config.io,
        .inner = try address.listen(config.io, .{ .reuse_address = true }),
    };
}

pub fn accept(server: *Server, req: *Request) !void {
    req.* = Request{ .stream = try server.inner.accept(server.io) };
    proto.inc(&counters.total_connections);
    req.reader = req.stream.reader(server.io, &req.recv_buffer);
    req.writer = req.stream.writer(server.io, &req.send_buffer);
    req.server = std.http.Server.init(&req.reader.interface, &req.writer.interface);
}

pub fn rebind(req: *Request, io: Io) void {
    req.reader = req.stream.reader(io, &req.recv_buffer);
    req.writer = req.stream.writer(io, &req.send_buffer);
    req.server = std.http.Server.init(&req.reader.interface, &req.writer.interface);
    req.target_value = "";
}

pub fn receiveHead(req: *Request) !void {
    req.inner = try req.server.receiveHead();
    const request_target = req.inner.head.target;
    if (request_target.len == 0 or request_target.len > 4095) return error.BadRequest;
    for (request_target) |c| {
        if (c == 0 or c == 13 or c == 10) return error.BadRequest;
    }
    const target_dest = req.target_storage[0..request_target.len];
    @memcpy(target_dest, request_target);
    req.target_value = target_dest;
    req.request_count += 1;
    if (req.request_count > 1) proto.inc(&counters.keepalive_reuse_count);
    req.close_after_response = !req.inner.head.keep_alive;
    proto.add(&counters.bytes_read, estimateRequestHeadBytes(req));
}

pub fn method(req: *Request) Method {
    return switch (req.inner.head.method) {
        .GET => .GET,
        .HEAD => .HEAD,
        .POST => .POST,
        .PUT => .PUT,
        .PATCH => .PATCH,
        .DELETE => .DELETE,
        .OPTIONS => .OPTIONS,
        else => .OTHER,
    };
}

pub fn respondParseError(req: *Request, status: u16, body: []const u8) void {
    const reason = proto.reasonPhrase(status);
    var response_buffer: [512]u8 = undefined;
    const bytes = std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {s}\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: {d}\r\nconnection: close\r\n\r\n{s}", .{ reason, body.len, body }) catch return;
    req.writer.interface.writeAll(bytes) catch return;
    req.writer.interface.flush() catch return;
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, bytes.len);
    req.close_after_response = true;
}

pub fn path(req: *Request) []const u8 {
    const request_target = req.target_value;
    return if (std.mem.indexOfScalar(u8, request_target, '?')) |idx| request_target[0..idx] else request_target;
}

pub fn target(req: *Request) []const u8 {
    return req.target_value;
}

pub fn query(req: *Request) []const u8 {
    const request_target = req.target_value;
    return if (std.mem.indexOfScalar(u8, request_target, '?')) |idx| request_target[idx + 1 ..] else "";
}

pub fn header(req: *Request, header_name: []const u8) ?[]const u8 {
    var it = req.inner.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, header_name)) return h.value;
    }
    return null;
}

pub fn readBody(req: *Request, allocator: std.mem.Allocator, max_bytes: usize) ![]const u8 {
    if (req.body_cache) |body| return body;
    if (max_bytes == 0) {
        if ((req.inner.head.content_length orelse 0) > 0) return error.PayloadTooLarge;
        req.body_cache = &.{};
        return req.body_cache.?;
    }
    if ((req.inner.head.content_length orelse 0) > max_bytes) return error.PayloadTooLarge;
    const len: usize = @intCast(req.inner.head.content_length orelse 0);
    var buffer: [4096]u8 = undefined;
    var body_reader = req.inner.readerExpectNone(&buffer);
    req.body_cache = try body_reader.readAlloc(allocator, len);
    proto.add(&counters.bytes_read, len);
    return req.body_cache.?;
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    if (method(req) != .HEAD and status == 200 and std.mem.eql(u8, body, "ok")) return respondRawOk(req);
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondTextWithHeaders(req: *Request, status: u16, body: []const u8, extra_headers: []const proto.Header) !void {
    try respondBytesWithHeaders(req, status, "text/plain; charset=utf-8", body, extra_headers);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    try respondBytesWithHeaders(req, status, content_type, body, &.{});
}

pub fn respondBytesWithHeaders(req: *Request, status: u16, content_type: []const u8, body: []const u8, extra_headers: []const proto.Header) !void {
    if (std.mem.eql(u8, content_type, "text/plain; charset=utf-8") and body.len <= 4096) {
        if (extra_headers.len == 0) return respondSmall(req, reasonFromCode(status), content_type, body);
    }
    const reason = reasonFromCode(status);
    const connection = if (req.inner.head.keep_alive) "keep-alive" else "close";
    const date = http_date.formatHttpDate(req.date_seconds);
    var header_buffer: [4096]u8 = undefined;
    var stream = std.Io.Writer.fixed(&header_buffer);
    try stream.print("HTTP/1.1 {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\ndate: {s}\r\n", .{ reason, content_type, body.len, connection, date });
    for (extra_headers) |header_item| {
        try stream.print("{s}: {s}\r\n", .{ header_item.name, header_item.value });
    }
    try stream.writeAll("\r\n");
    const headers = stream.buffered();
    const head_only = method(req) == .HEAD;
    try req.writer.interface.writeAll(headers);
    if (!head_only and body.len > 0) try req.writer.interface.writeAll(body);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, headers.len + if (head_only) 0 else body.len);
    req.close_after_response = !req.inner.head.keep_alive;
}

pub fn respondStatic(req: *Request, status: u16, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8, body: []const u8, head_only: bool) !void {
    var response_buffer: [16384]u8 = undefined;
    const encoding = content_encoding orelse "";
    const reason = reasonFromCode(status);
    const date = http_date.formatHttpDate(req.date_seconds);
    const response = if (status == 304 and content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ cache_control, etag, if (req.inner.head.keep_alive) "keep-alive" else "close", date })
    else if (status == 304)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ cache_control, etag, if (req.inner.head.keep_alive) "keep-alive" else "close", date })
    else if (content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\ncontent-encoding: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ reason, content_type, content_length, cache_control, etag, encoding, if (req.inner.head.keep_alive) "keep-alive" else "close", date })
    else
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ reason, content_type, content_length, cache_control, etag, if (req.inner.head.keep_alive) "keep-alive" else "close", date });
    try req.writer.interface.writeAll(response);
    if (!head_only and status != 304) try req.writer.interface.writeAll(body);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, estimateResponseBytes(content_type, body));
    req.close_after_response = !req.inner.head.keep_alive;
}

pub fn respondRawOk(req: *Request) !void {
    var response_buffer: [256]u8 = undefined;
    const connection = if (req.inner.head.keep_alive) "keep-alive" else "close";
    const date = http_date.formatHttpDate(req.date_seconds);
    const bytes = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: {s}\r\ndate: {s}\r\n\r\nok", .{ connection, date });
    try writeRaw(req, bytes);
}

pub fn writeRaw(req: *Request, bytes: []const u8) !void {
    try req.writer.interface.writeAll(bytes);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, bytes.len);
    req.close_after_response = !req.inner.head.keep_alive;
}

pub fn finish(_: *Request) !void {}


fn respondSmall(req: *Request, reason: []const u8, content_type: []const u8, body: []const u8) !void {
    var response_buffer: [8192]u8 = undefined;
    const connection = if (req.inner.head.keep_alive) "keep-alive" else "close";
    const date = http_date.formatHttpDate(req.date_seconds);
    const response = if (method(req) == .HEAD)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ reason, content_type, body.len, connection, date })
    else
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n{s}", .{ reason, content_type, body.len, connection, date, body });
    try writeRaw(req, response);
}

fn estimateRequestHeadBytes(req: *Request) u64 {
    var total: u64 = @tagName(req.inner.head.method).len + 1 + req.inner.head.target.len + " HTTP/1.1\r\n\r\n".len;
    var it = req.inner.iterateHeaders();
    while (it.next()) |h| total += h.name.len + 2 + h.value.len + 2;
    return total;
}

fn estimateResponseBytes(content_type: []const u8, body: []const u8) u64 {
    var len_buf: [32]u8 = undefined;
    const len_text = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable;
    return "HTTP/1.1 200 OK\r\ncontent-type: \r\ncontent-length: \r\n\r\n".len + content_type.len + len_text.len + body.len;
}

fn statusFromCode(code: u16) std.http.Status {
    return switch (code) {
        200 => .ok,
        204 => .no_content,
        301 => .moved_permanently,
        302 => .found,
        303 => .see_other,
        304 => .not_modified,
        307 => .temporary_redirect,
        308 => .permanent_redirect,
        400 => .bad_request,
        401 => .unauthorized,
        403 => .forbidden,
        404 => .not_found,
        405 => .method_not_allowed,
        413 => .payload_too_large,
        414 => .uri_too_long,
        500 => .internal_server_error,
        501 => .not_implemented,
        else => .ok,
    };
}

fn reasonFromCode(code: u16) []const u8 {
    return switch (code) {
        200 => "200 OK",
        204 => "204 No Content",
        301 => "301 Moved Permanently",
        302 => "302 Found",
        303 => "303 See Other",
        304 => "304 Not Modified",
        307 => "307 Temporary Redirect",
        308 => "308 Permanent Redirect",
        400 => "400 Bad Request",
        401 => "401 Unauthorized",
        403 => "403 Forbidden",
        404 => "404 Not Found",
        405 => "405 Method Not Allowed",
        413 => "413 Payload Too Large",
        414 => "414 URI Too Long",
        500 => "500 Internal Server Error",
        501 => "501 Not Implemented",
        else => "200 OK",
    };
}
