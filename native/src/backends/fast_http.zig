const std = @import("std");
const Io = std.Io;

const build_options = @import("build_options");

pub const name = "fast_http";
pub const connection_strategy = "fast_http_" ++ build_options.fast_http_strategy;
pub const bounded = std.mem.eql(u8, build_options.fast_http_strategy, "pool");
pub const threaded_connections = std.mem.eql(u8, build_options.fast_http_strategy, "threaded_probe");
pub const pooled_connections = std.mem.eql(u8, build_options.fast_http_strategy, "pool");
pub const configured_workers: u16 = build_options.fast_http_workers;
pub const queue_limit: usize = build_options.fast_http_queue;

pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OTHER };

pub const Counters = struct {
    active_connections: u64 = 0,
    total_connections: u64 = 0,
    accepted_connections: u64 = 0,
    threads_spawned: u64 = 0,
    requests_served: u64 = 0,
    requests_per_connection: u64 = 0,
    keepalive_reuse_count: u64 = 0,
    connection_close_count: u64 = 0,
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,
    connection_errors: u64 = 0,
    max_active_connections: u64 = 0,
    queue_depth: u64 = 0,
    max_queue_depth: u64 = 0,
    dropped_connections: u64 = 0,
};

const AtomicCounter = std.atomic.Value(u64);
const AtomicCounters = struct {
    active_connections: AtomicCounter = AtomicCounter.init(0),
    total_connections: AtomicCounter = AtomicCounter.init(0),
    threads_spawned: AtomicCounter = AtomicCounter.init(0),
    requests_served: AtomicCounter = AtomicCounter.init(0),
    keepalive_reuse_count: AtomicCounter = AtomicCounter.init(0),
    connection_close_count: AtomicCounter = AtomicCounter.init(0),
    bytes_read: AtomicCounter = AtomicCounter.init(0),
    bytes_written: AtomicCounter = AtomicCounter.init(0),
    connection_errors: AtomicCounter = AtomicCounter.init(0),
    max_active_connections: AtomicCounter = AtomicCounter.init(0),
    queue_depth: AtomicCounter = AtomicCounter.init(0),
    max_queue_depth: AtomicCounter = AtomicCounter.init(0),
    dropped_connections: AtomicCounter = AtomicCounter.init(0),
};

var counters = AtomicCounters{};

pub fn snapshotCounters() Counters {
    const total = counters.total_connections.load(.monotonic);
    const served = counters.requests_served.load(.monotonic);
    return .{
        .active_connections = counters.active_connections.load(.monotonic),
        .total_connections = total,
        .accepted_connections = total,
        .threads_spawned = counters.threads_spawned.load(.monotonic),
        .requests_served = served,
        .requests_per_connection = if (total == 0) 0 else served / total,
        .keepalive_reuse_count = counters.keepalive_reuse_count.load(.monotonic),
        .connection_close_count = counters.connection_close_count.load(.monotonic),
        .bytes_read = counters.bytes_read.load(.monotonic),
        .bytes_written = counters.bytes_written.load(.monotonic),
        .connection_errors = counters.connection_errors.load(.monotonic),
        .max_active_connections = counters.max_active_connections.load(.monotonic),
        .queue_depth = counters.queue_depth.load(.monotonic),
        .max_queue_depth = counters.max_queue_depth.load(.monotonic),
        .dropped_connections = counters.dropped_connections.load(.monotonic),
    };
}

fn inc(counter: *AtomicCounter) void {
    _ = counter.fetchAdd(1, .monotonic);
}

fn dec(counter: *AtomicCounter) void {
    _ = counter.fetchSub(1, .monotonic);
}

fn add(counter: *AtomicCounter, value: u64) void {
    _ = counter.fetchAdd(value, .monotonic);
}

fn maxCounter(counter: *AtomicCounter, value: u64) void {
    var current = counter.load(.monotonic);
    while (value > current) {
        current = counter.cmpxchgWeak(current, value, .monotonic, .monotonic) orelse return;
    }
}

pub fn connectionStarted() void {
    const active = counters.active_connections.fetchAdd(1, .monotonic) + 1;
    maxCounter(&counters.max_active_connections, active);
}

pub fn connectionEnded() void {
    dec(&counters.active_connections);
}

pub fn threadSpawned() void {
    inc(&counters.threads_spawned);
}

pub fn connectionError() void {
    inc(&counters.connection_errors);
}

pub fn droppedConnection() void {
    inc(&counters.dropped_connections);
}

pub fn setQueueDepth(value: u64) void {
    counters.queue_depth.store(value, .monotonic);
    maxCounter(&counters.max_queue_depth, value);
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

pub const Header = struct {
    name: []const u8,
    value: []const u8,
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
    method_value: Method = .OTHER,
    target_value: []const u8 = "",
    path_value: []const u8 = "",
    query_value: []const u8 = "",
    keep_alive: bool = true,
    content_length: usize = 0,
    headers: [32]Header = undefined,
    header_count: usize = 0,
    request_count: u64 = 0,

    pub fn close(self: *Request, io: Io) void {
        if (!self.closed) {
            self.closed = true;
            inc(&counters.connection_close_count);
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
    inc(&counters.total_connections);
    req.reader = req.stream.reader(server.io, &req.recv_buffer);
    req.writer = req.stream.writer(server.io, &req.send_buffer);
}

pub fn rebind(req: *Request, io: Io) void {
    req.reader = req.stream.reader(io, &req.recv_buffer);
    req.writer = req.stream.writer(io, &req.send_buffer);
}

pub fn receiveHead(req: *Request) !void {
    req.body_cache = null;
    req.header_count = 0;
    req.content_length = 0;
    req.keep_alive = true;

    const request_line = (try req.reader.interface.takeDelimiter('\n')) orelse return error.HttpConnectionClosing;
    add(&counters.bytes_read, request_line.len + 1);
    const clean_line = trimCr(request_line);
    if (clean_line.len == 0) return error.HttpConnectionClosing;

    var parts = std.mem.splitScalar(u8, clean_line, ' ');
    const method_text = parts.next() orelse return error.BadRequest;
    const target_text = parts.next() orelse return error.BadRequest;
    const version_text = parts.next() orelse "HTTP/1.1";

    req.method_value = parseMethod(method_text);
    req.target_value = target_text;
    if (std.mem.indexOfScalar(u8, target_text, '?')) |idx| {
        req.path_value = target_text[0..idx];
        req.query_value = target_text[idx + 1 ..];
    } else {
        req.path_value = target_text;
        req.query_value = "";
    }
    req.keep_alive = !std.mem.eql(u8, version_text, "HTTP/1.0");

    while (true) {
        const line = (try req.reader.interface.takeDelimiter('\n')) orelse return error.BadRequest;
        add(&counters.bytes_read, line.len + 1);
        const clean = trimCr(line);
        if (clean.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, clean, ':') orelse continue;
        const header_name = std.mem.trim(u8, clean[0..colon], " \t");
        const value = std.mem.trim(u8, clean[colon + 1 ..], " \t");
        if (req.header_count < req.headers.len) {
            req.headers[req.header_count] = .{ .name = header_name, .value = value };
            req.header_count += 1;
        }
        if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
            req.content_length = std.fmt.parseInt(usize, value, 10) catch return error.BadRequest;
        } else if (std.ascii.eqlIgnoreCase(header_name, "connection")) {
            if (std.ascii.eqlIgnoreCase(value, "close")) req.keep_alive = false;
            if (std.ascii.eqlIgnoreCase(value, "keep-alive")) req.keep_alive = true;
        }
    }

    req.request_count += 1;
    if (req.request_count > 1) inc(&counters.keepalive_reuse_count);
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
    if (max_bytes == 0) {
        if (req.content_length > 0) return error.PayloadTooLarge;
        req.body_cache = &.{};
        return req.body_cache.?;
    }
    if (req.content_length > max_bytes) return error.PayloadTooLarge;
    const body = try allocator.alloc(u8, req.content_length);
    try req.reader.interface.readSliceAll(body);
    add(&counters.bytes_read, body.len);
    req.body_cache = body;
    return body;
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    if (status == 200 and std.mem.eql(u8, body, "ok")) return respondRawOk(req);
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    const reason = reasonPhrase(status);
    var response_buffer: [8192]u8 = undefined;
    const connection = if (req.keep_alive) "keep-alive" else "close";
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\n\r\n{s}", .{ status, reason, content_type, body.len, connection, body });
    try writeRaw(req, response);
}

pub fn respondStatic(req: *Request, status: u16, content_type: []const u8, content_length: u64, cache_control: []const u8, etag: []const u8, content_encoding: ?[]const u8, body: []const u8, head_only: bool) !void {
    const reason = reasonPhrase(status);
    var response_buffer: [16384]u8 = undefined;
    const connection = if (req.keep_alive) "keep-alive" else "close";
    const encoding = content_encoding orelse "";
    const response = if (status == 304 and content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\n\r\n", .{ cache_control, etag, connection })
    else if (status == 304)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 304 Not Modified\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\n\r\n", .{ cache_control, etag, connection })
    else if (content_encoding != null)
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\ncontent-encoding: {s}\r\nvary: Accept-Encoding\r\nconnection: {s}\r\n\r\n", .{ status, reason, content_type, content_length, cache_control, etag, encoding, connection })
    else
        try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {d} {s}\r\ncontent-type: {s}\r\ncontent-length: {d}\r\ncache-control: {s}\r\netag: {s}\r\nconnection: {s}\r\n\r\n", .{ status, reason, content_type, content_length, cache_control, etag, connection });
    try req.writer.interface.writeAll(response);
    if (!head_only and status != 304) try req.writer.interface.writeAll(body);
    try req.writer.interface.flush();
    inc(&counters.requests_served);
    add(&counters.bytes_written, response.len + if (head_only or status == 304) 0 else body.len);
    req.close_after_response = !req.keep_alive;
}

pub fn respondRawOk(req: *Request) !void {
    const bytes = if (req.keep_alive) raw_ok_keepalive else raw_ok_close;
    try writeRaw(req, bytes);
}

pub fn writeRaw(req: *Request, bytes: []const u8) !void {
    try req.writer.interface.writeAll(bytes);
    try req.writer.interface.flush();
    inc(&counters.requests_served);
    add(&counters.bytes_written, bytes.len);
    req.close_after_response = !req.keep_alive;
}

pub fn finish(_: *Request) !void {}

const raw_ok_keepalive = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\nok";
const raw_ok_close = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok";

fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn parseMethod(value: []const u8) Method {
    if (std.mem.eql(u8, value, "GET")) return .GET;
    if (std.mem.eql(u8, value, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, value, "POST")) return .POST;
    if (std.mem.eql(u8, value, "PUT")) return .PUT;
    if (std.mem.eql(u8, value, "PATCH")) return .PATCH;
    if (std.mem.eql(u8, value, "DELETE")) return .DELETE;
    return .OTHER;
}

fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        414 => "URI Too Long",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        else => "OK",
    };
}
