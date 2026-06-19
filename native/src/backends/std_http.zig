const std = @import("std");
const Io = std.Io;

pub const name = "std_http";
pub const connection_strategy = "std_http_single_connection_loop";
pub const bounded = true;
pub const threaded_connections = false;
pub const pooled_connections = false;
pub const configured_workers: u16 = 0;
pub const queue_limit: usize = 0;

pub const Method = enum { GET, POST, PUT, PATCH, DELETE, OTHER };

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
        .queue_depth = 0,
        .max_queue_depth = 0,
        .dropped_connections = 0,
    };
}

fn inc(counter: *AtomicCounter) void { _ = counter.fetchAdd(1, .monotonic); }
fn dec(counter: *AtomicCounter) void { _ = counter.fetchSub(1, .monotonic); }
fn add(counter: *AtomicCounter, value: u64) void { _ = counter.fetchAdd(value, .monotonic); }
fn maxCounter(counter: *AtomicCounter, value: u64) void {
    var current = counter.load(.monotonic);
    while (value > current) current = counter.cmpxchgWeak(current, value, .monotonic, .monotonic) orelse return;
}

pub fn connectionStarted() void {
    const active = counters.active_connections.fetchAdd(1, .monotonic) + 1;
    maxCounter(&counters.max_active_connections, active);
}
pub fn connectionEnded() void { dec(&counters.active_connections); }
pub fn threadSpawned() void { inc(&counters.threads_spawned); }
pub fn connectionError() void { inc(&counters.connection_errors); }
pub fn droppedConnection() void { inc(&counters.connection_errors); }
pub fn setQueueDepth(_: u64) void {}

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
    req.server = std.http.Server.init(&req.reader.interface, &req.writer.interface);
}

pub fn rebind(req: *Request, io: Io) void {
    req.reader = req.stream.reader(io, &req.recv_buffer);
    req.writer = req.stream.writer(io, &req.send_buffer);
    req.server = std.http.Server.init(&req.reader.interface, &req.writer.interface);
}

pub fn receiveHead(req: *Request) !void {
    req.inner = try req.server.receiveHead();
    req.request_count += 1;
    if (req.request_count > 1) inc(&counters.keepalive_reuse_count);
    req.close_after_response = !req.inner.head.keep_alive;
    add(&counters.bytes_read, estimateRequestHeadBytes(req));
}

pub fn method(req: *Request) Method {
    return switch (req.inner.head.method) {
        .GET => .GET,
        .POST => .POST,
        .PUT => .PUT,
        .PATCH => .PATCH,
        .DELETE => .DELETE,
        else => .OTHER,
    };
}

pub fn path(req: *Request) []const u8 {
    const request_target = req.inner.head.target;
    return if (std.mem.indexOfScalar(u8, request_target, '?')) |idx| request_target[0..idx] else request_target;
}

pub fn target(req: *Request) []const u8 {
    return req.inner.head.target;
}

pub fn query(req: *Request) []const u8 {
    const request_target = req.inner.head.target;
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
    add(&counters.bytes_read, len);
    return req.body_cache.?;
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    if (status == 200 and std.mem.eql(u8, body, "ok")) return respondRawOk(req);
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    if (status == 200 and std.mem.eql(u8, content_type, "text/plain; charset=utf-8") and body.len <= 4096) {
        return respondSmall(req, "200 OK", content_type, body);
    }
    try req.inner.respond(body, .{
        .status = statusFromCode(status),
        .keep_alive = req.inner.head.keep_alive,
        .extra_headers = &.{ .{ .name = "content-type", .value = content_type } },
    });
    inc(&counters.requests_served);
    add(&counters.bytes_written, estimateResponseBytes(content_type, body));
    req.close_after_response = !req.inner.head.keep_alive;
}

pub fn respondRawOk(req: *Request) !void {
    const bytes = if (req.inner.head.keep_alive) raw_ok_keepalive else raw_ok_close;
    try writeRaw(req, bytes);
}

pub fn writeRaw(req: *Request, bytes: []const u8) !void {
    try req.writer.interface.writeAll(bytes);
    try req.writer.interface.flush();
    inc(&counters.requests_served);
    add(&counters.bytes_written, bytes.len);
    req.close_after_response = !req.inner.head.keep_alive;
}

pub fn finish(_: *Request) !void {}

const raw_ok_keepalive = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\nok";
const raw_ok_close = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok";

fn respondSmall(req: *Request, comptime reason: []const u8, content_type: []const u8, body: []const u8) !void {
    var response_buffer: [8192]u8 = undefined;
    const connection = if (req.inner.head.keep_alive) "keep-alive" else "close";
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 " ++ reason ++ "\r\ncontent-type: {s}\r\ncontent-length: {d}\r\nconnection: {s}\r\n\r\n{s}", .{ content_type, body.len, connection, body });
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
        400 => .bad_request,
        404 => .not_found,
        405 => .method_not_allowed,
        413 => .payload_too_large,
        414 => .uri_too_long,
        500 => .internal_server_error,
        501 => .not_implemented,
        else => .ok,
    };
}
