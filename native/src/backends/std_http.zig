const std = @import("std");
const Io = std.Io;

pub const Method = enum { GET, POST, OTHER };

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
    body_cache: ?[]const u8 = null,

    pub fn close(self: *Request, io: Io) void {
        if (!self.closed) {
            self.closed = true;
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

pub fn accept(server: *Server) !Request {
    var req = Request{ .stream = try server.inner.accept(server.io) };
    req.reader = req.stream.reader(server.io, &req.recv_buffer);
    req.writer = req.stream.writer(server.io, &req.send_buffer);
    req.server = std.http.Server.init(&req.reader.interface, &req.writer.interface);
    req.inner = try req.server.receiveHead();
    return req;
}

pub fn method(req: *Request) Method {
    return switch (req.inner.head.method) {
        .GET => .GET,
        .POST => .POST,
        else => .OTHER,
    };
}

pub fn path(req: *Request) []const u8 {
    const target = req.inner.head.target;
    return if (std.mem.indexOfScalar(u8, target, '?')) |idx| target[0..idx] else target;
}

pub fn query(req: *Request) []const u8 {
    const target = req.inner.head.target;
    return if (std.mem.indexOfScalar(u8, target, '?')) |idx| target[idx + 1 ..] else "";
}

pub fn header(req: *Request, name: []const u8) ?[]const u8 {
    var it = req.inner.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
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
    return req.body_cache.?;
}

pub fn respondText(req: *Request, status: u16, body: []const u8) !void {
    try respondBytes(req, status, "text/plain; charset=utf-8", body);
}

pub fn respondBytes(req: *Request, status: u16, content_type: []const u8, body: []const u8) !void {
    try req.inner.respond(body, .{
        .status = statusFromCode(status),
        .keep_alive = false,
        .extra_headers = &.{ .{ .name = "content-type", .value = content_type } },
    });
}

pub fn finish(_: *Request) !void {}

fn statusFromCode(code: u16) std.http.Status {
    return switch (code) {
        200 => .ok,
        400 => .bad_request,
        404 => .not_found,
        405 => .method_not_allowed,
        413 => .payload_too_large,
        500 => .internal_server_error,
        501 => .not_implemented,
        else => .ok,
    };
}
