const std = @import("std");
const Io = std.Io;
const build_options = @import("build_options");
const proto = @import("protocol.zig");
const http_date = @import("../server/http_date.zig");

pub const name = "fast_http";
pub const connection_strategy = "fast_http_" ++ build_options.fast_http_strategy;
pub const bounded = std.mem.eql(u8, build_options.fast_http_strategy, "pool");
pub const threaded_connections = std.mem.eql(u8, build_options.fast_http_strategy, "threaded_probe");
pub const pooled_connections = std.mem.eql(u8, build_options.fast_http_strategy, "pool");
pub const configured_workers: u16 = build_options.fast_http_workers;
pub const queue_limit: usize = build_options.fast_http_queue;

pub const Method = proto.Method;
pub const Header = proto.Header;
pub const Counters = proto.Counters;

const AtomicCounters = proto.AtomicCounters;
var counters = AtomicCounters{};

pub fn snapshotCounters() Counters {
    var c = proto.snapshotCounters(&counters);
    c.budget_capacity = queue_limit;
    return c;
}

pub fn connectionStarted() void { proto.connectionStarted(&counters); }
pub fn connectionEnded() void { proto.connectionEnded(&counters); }
pub fn requestStarted() void { proto.requestStarted(&counters); }
pub fn requestCompleted() void { proto.requestCompleted(&counters); }
pub fn threadSpawned() void { proto.threadSpawned(&counters); }
pub fn connectionError() void { proto.connectionError(&counters); }
pub fn droppedConnection() void { proto.droppedConnection(&counters); }
pub fn setQueueDepth(value: u64) void { proto.setQueueDepth(&counters, value); }
pub fn resetAuditCounters() void { proto.resetAuditCounters(&counters); }

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
    recv_buffer: [16384]u8 = undefined,
    send_buffer: [8192]u8 = undefined,
    reader: Io.net.Stream.Reader = undefined,
    writer: Io.net.Stream.Writer = undefined,
    closed: bool = false,
    close_after_response: bool = true,
    body_cache: ?[]const u8 = null,
    body_read: bool = false,
    method_value: Method = .OTHER,
    target_value: []const u8 = "",
    path_value: []const u8 = "",
    query_value: []const u8 = "",
    keep_alive: bool = true,
    content_length: usize = 0,
    has_chunked_encoding: bool = false,
    headers: [32]Header = undefined,
    header_count: usize = 0,
    request_count: u64 = 0,
    date_seconds: i64 = 0,

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
}

pub fn rebind(req: *Request, io: Io) void {
    req.reader = req.stream.reader(io, &req.recv_buffer);
    req.writer = req.stream.writer(io, &req.send_buffer);
}

pub fn receiveHead(req: *Request) !void {
    req.body_cache = null;
    req.body_read = false;
    req.header_count = 0;
    req.content_length = 0;
    req.has_chunked_encoding = false;
    req.keep_alive = true;

    const request_line = (try req.reader.interface.takeDelimiter('\n')) orelse return error.HttpConnectionClosing;
    proto.add(&counters.bytes_read, request_line.len + 1);
    const clean_line = proto.trimCr(request_line);
    if (clean_line.len == 0) return error.HttpConnectionClosing;

    var parts = std.mem.splitScalar(u8, clean_line, ' ');
    const method_text = parts.next() orelse return error.BadRequest;
    const target_text = parts.next() orelse return error.BadRequest;
    const version_text = parts.next() orelse "HTTP/1.1";

    req.method_value = proto.parseMethod(method_text);
    req.target_value = target_text;
    if (std.mem.indexOfScalar(u8, target_text, '?')) |idx| {
        req.path_value = target_text[0..idx];
        req.query_value = target_text[idx + 1 ..];
    } else {
        req.path_value = target_text;
        req.query_value = "";
    }
    req.keep_alive = !std.mem.eql(u8, version_text, "HTTP/1.0");

    // Read headers with a total header size limit to prevent unbounded reads.
    var total_header_bytes: usize = 0;
    const max_header_bytes: usize = 16384; // recv buffer size

    while (true) {
        const line = (try req.reader.interface.takeDelimiter('\n')) orelse return error.BadRequest;
        proto.add(&counters.bytes_read, line.len + 1);
        total_header_bytes += line.len + 1;
        if (total_header_bytes > max_header_bytes) return error.HeaderTooLarge;

        const clean = proto.trimCr(line);
        if (clean.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, clean, ':') orelse continue;
        const header_name = std.mem.trim(u8, clean[0..colon], " \t");
        const value = std.mem.trim(u8, clean[colon + 1 ..], " \t");

        // Reject header values containing CR/LF (header injection prevention)
        if (std.mem.indexOfScalar(u8, value, '\r') != null or std.mem.indexOfScalar(u8, value, '\n') != null) {
            return error.BadRequest;
        }

        if (req.header_count < req.headers.len) {
            req.headers[req.header_count] = .{ .name = header_name, .value = value };
            req.header_count += 1;
        }
        if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
            req.content_length = std.fmt.parseInt(usize, value, 10) catch return error.BadRequest;
        } else if (std.ascii.eqlIgnoreCase(header_name, "connection")) {
            if (std.ascii.eqlIgnoreCase(value, "close")) req.keep_alive = false;
            if (std.ascii.eqlIgnoreCase(value, "keep-alive")) req.keep_alive = true;
        } else if (std.ascii.eqlIgnoreCase(header_name, "transfer-encoding")) {
            if (std.ascii.eqlIgnoreCase(value, "chunked")) {
                req.has_chunked_encoding = true;
                req.keep_alive = false; // chunked not supported; close after response
            }
        }
    }

    req.request_count += 1;
    if (req.request_count > 1) proto.inc(&counters.keepalive_reuse_count);
    req.close_after_response = !req.keep_alive;
}

pub fn method(req: *Request) Method {
    return req.method_value;
}

pub fn path(req: *Request) []const u8 {
    return req.path_value;
}

pub fn target(req: *Request) []const u8 {
    return req.target_value;
}

pub fn query(req: *Request) []const u8 {
    return req.query_value;
}

pub fn header(req: *Request, header_name: []const u8) ?[]const u8 {
    for (req.headers[0..req.header_count]) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, header_name)) return h.value;
    }
    return null;
}

pub fn readBody(req: *Request, allocator: std.mem.Allocator, max_bytes: usize) ![]const u8 {
    if (req.body_cache) |body| return body;
    if (req.has_chunked_encoding) {
        // Chunked transfer encoding is not supported.
        // Mark as read and return empty so the connection can close cleanly.
        req.body_read = true;
        req.body_cache = &.{};
        return req.body_cache.?;
    }
    if (max_bytes == 0) {
        if (req.content_length > 0) return error.PayloadTooLarge;
        req.body_read = true;
        req.body_cache = &.{};
        return req.body_cache.?;
    }
    if (req.content_length > max_bytes) return error.PayloadTooLarge;
    const body = try allocator.alloc(u8, req.content_length);
    try req.reader.interface.readSliceAll(body);
    proto.add(&counters.bytes_read, body.len);
    req.body_cache = body;
    req.body_read = true;
    return body;
}

/// Drain any unread body so the connection can be reused for the next request.
/// Must be called after serveRequest if keep-alive is desired.
pub fn drainBody(req: *Request) void {
    if (req.body_read or req.content_length == 0 or req.has_chunked_encoding) return;
    // Drain content_length bytes from the reader
    var remaining = req.content_length;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        req.reader.interface.readSliceAll(buf[0..to_read]) catch {
            // If drain fails, force close the connection
            req.keep_alive = false;
            req.close_after_response = true;
            return;
        };
        proto.add(&counters.bytes_read, to_read);
        remaining -= to_read;
    }
    req.body_read = true;
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    if (status == 200 and std.mem.eql(u8, body, "ok")) return respondRawOk(req);
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    const reason = proto.reasonPhrase(status);
    const connection = if (req.keep_alive) "keep-alive" else "close";
    const date = http_date.formatHttpDate(req.date_seconds);

    var header_buffer: [4096]u8 = undefined;
    const headers = try std.fmt.bufPrint(&header_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ status, reason, content_type, body.len, connection, date });
    
    try req.writer.interface.writeAll(headers);
    if (body.len > 0) {
        try req.writer.interface.writeAll(body);
    }
    try req.writer.interface.flush();
    
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, headers.len + body.len);
    req.close_after_response = !req.keep_alive;
}

pub fn respondStatic(req: *Request, status: u16, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8, body: []const u8, head_only: bool) !void {
    const reason = proto.reasonPhrase(status);
    var response_buffer: [16384]u8 = undefined;
    const connection = if (req.keep_alive) "keep-alive" else "close";
    const encoding = content_encoding orelse "";
    const date = http_date.formatHttpDate(req.date_seconds);
    const response = if (status == 304 and content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\n\r\n", .{ cache_control, etag, connection })
    else if (status == 304)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\n\r\n", .{ cache_control, etag, connection })
    else if (content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\ncontent-encoding: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\n\r\n", .{ status, reason, content_type, content_length, cache_control, etag, encoding, connection })
    else
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\ndate: {s}\r\n\r\n", .{ status, reason, content_type, content_length, cache_control, etag, connection, date });
    try req.writer.interface.writeAll(response);
    if (!head_only and status != 304) try req.writer.interface.writeAll(body);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, response.len + if (head_only or status == 304) 0 else body.len);
    req.close_after_response = !req.keep_alive;
}

pub fn respondRawOk(req: *Request) !void {
    const bytes = if (req.keep_alive) raw_ok_keepalive else raw_ok_close;
    try writeRaw(req, bytes);
}

pub fn writeRaw(req: *Request, bytes: []const u8) !void {
    try req.writer.interface.writeAll(bytes);
    try req.writer.interface.flush();
    proto.inc(&counters.requests_served);
    proto.add(&counters.bytes_written, bytes.len);
    req.close_after_response = !req.keep_alive;
}

pub fn finish(_: *Request) !void {}


const raw_ok_keepalive = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\nok";
const raw_ok_close = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok";
