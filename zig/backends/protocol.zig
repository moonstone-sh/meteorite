const std = @import("std");

/// Shared Meteorite protocol types used by all backends.
/// HTTP adapters use the HTTP-shaped aliases below; IPC adapters should use
/// the transport-neutral request/response types as they come online.
pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, OTHER };

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const MetadataEntry = struct {
    name: []const u8,
    value: []const u8,
};

pub const Transport = enum { tcp, unix };

pub const Protocol = enum { http_1_1, meteorite_ipc_v0 };

pub const ResultCode = enum(u16) {
    ok = 0,
    not_found = 1,
    method_not_allowed = 2,
    validation_error = 3,
    payload_too_large = 4,
    malformed_message = 5,
    unauthorized_peer = 6,
    busy = 7,
    timeout = 8,
    internal_error = 9,
};

pub const Peer = struct {
    uid: ?u32 = null,
    gid: ?u32 = null,
    pid: ?u32 = null,
};

pub const MeteoriteRequest = struct {
    route_key: []const u8 = "",
    message: []const u8 = "",
    method: ?Method = null,
    path: ?[]const u8 = null,
    params: []const MetadataEntry = &.{},
    query: []const MetadataEntry = &.{},
    metadata: []const MetadataEntry = &.{},
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    request_id: []const u8 = "",
    peer: ?Peer = null,
};

pub const MeteoriteResponse = struct {
    result: ResultCode = .ok,
    status: ?u16 = null,
    content_type: []const u8 = "text/plain; charset=utf-8",
    metadata: []const MetadataEntry = &.{},
    headers: []const Header = &.{},
    body: []const u8 = "",
    close_policy: enum { keep_open, close_after_response } = .keep_open,
};

pub const BackendCapabilities = struct {
    http_headers: bool = false,
    cookies: bool = false,
    cors: bool = false,
    redirects: bool = false,
    ipc_metadata: bool = false,
    peer_credentials: bool = false,
    static_files: bool = false,
};

pub const Counters = struct {
    active_connections: u64 = 0,
    inflight_current: u64 = 0,
    inflight_max: u64 = 0,
    total_connections: u64 = 0,
    accepted_connections: u64 = 0,
    accepted_total: u64 = 0,
    completed_total: u64 = 0,
    threads_spawned: u64 = 0,
    requests_served: u64 = 0,
    requests_per_connection: u64 = 0,
    keepalive_reuse_count: u64 = 0,
    connection_close_count: u64 = 0,
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,
    connection_errors: u64 = 0,
    malformed_frames: u64 = 0,
    oversized_frames: u64 = 0,
    protocol_errors: u64 = 0,
    early_closes: u64 = 0,
    max_active_connections: u64 = 0,
    queue_depth: u64 = 0,
    max_queue_depth: u64 = 0,
    worker_queue_depth_max: u64 = 0,
    budget_capacity: u64 = 0,
    budget_rejections_total: u64 = 0,
    backpressure_total: u64 = 0,
    dropped_connections: u64 = 0,
};

pub const AtomicCounter = std.atomic.Value(u64);

pub const AtomicCounters = struct {
    active_connections: AtomicCounter = AtomicCounter.init(0),
    inflight_current: AtomicCounter = AtomicCounter.init(0),
    inflight_max: AtomicCounter = AtomicCounter.init(0),
    total_connections: AtomicCounter = AtomicCounter.init(0),
    completed_total: AtomicCounter = AtomicCounter.init(0),
    threads_spawned: AtomicCounter = AtomicCounter.init(0),
    requests_served: AtomicCounter = AtomicCounter.init(0),
    keepalive_reuse_count: AtomicCounter = AtomicCounter.init(0),
    connection_close_count: AtomicCounter = AtomicCounter.init(0),
    bytes_read: AtomicCounter = AtomicCounter.init(0),
    bytes_written: AtomicCounter = AtomicCounter.init(0),
    connection_errors: AtomicCounter = AtomicCounter.init(0),
    malformed_frames: AtomicCounter = AtomicCounter.init(0),
    oversized_frames: AtomicCounter = AtomicCounter.init(0),
    protocol_errors: AtomicCounter = AtomicCounter.init(0),
    early_closes: AtomicCounter = AtomicCounter.init(0),
    max_active_connections: AtomicCounter = AtomicCounter.init(0),
    queue_depth: AtomicCounter = AtomicCounter.init(0),
    max_queue_depth: AtomicCounter = AtomicCounter.init(0),
    budget_rejections_total: AtomicCounter = AtomicCounter.init(0),
    backpressure_total: AtomicCounter = AtomicCounter.init(0),
    dropped_connections: AtomicCounter = AtomicCounter.init(0),
};

pub fn inc(counter: *AtomicCounter) void {
    _ = counter.fetchAdd(1, .monotonic);
}

pub fn dec(counter: *AtomicCounter) void {
    _ = counter.fetchSub(1, .monotonic);
}

pub fn add(counter: *AtomicCounter, value: u64) void {
    _ = counter.fetchAdd(value, .monotonic);
}

pub fn maxCounter(counter: *AtomicCounter, value: u64) void {
    var current = counter.load(.monotonic);
    while (value > current) {
        current = counter.cmpxchgWeak(current, value, .monotonic, .monotonic) orelse return;
    }
}

pub fn snapshotCounters(c: *const AtomicCounters) Counters {
    const total = c.total_connections.load(.monotonic);
    const served = c.requests_served.load(.monotonic);
    return .{
        .active_connections = c.active_connections.load(.monotonic),
        .inflight_current = c.inflight_current.load(.monotonic),
        .inflight_max = c.inflight_max.load(.monotonic),
        .total_connections = total,
        .accepted_connections = total,
        .accepted_total = total,
        .completed_total = c.completed_total.load(.monotonic),
        .threads_spawned = c.threads_spawned.load(.monotonic),
        .requests_served = served,
        .requests_per_connection = if (total == 0) 0 else served / total,
        .keepalive_reuse_count = c.keepalive_reuse_count.load(.monotonic),
        .connection_close_count = c.connection_close_count.load(.monotonic),
        .bytes_read = c.bytes_read.load(.monotonic),
        .bytes_written = c.bytes_written.load(.monotonic),
        .connection_errors = c.connection_errors.load(.monotonic),
        .malformed_frames = c.malformed_frames.load(.monotonic),
        .oversized_frames = c.oversized_frames.load(.monotonic),
        .protocol_errors = c.protocol_errors.load(.monotonic),
        .early_closes = c.early_closes.load(.monotonic),
        .max_active_connections = c.max_active_connections.load(.monotonic),
        .queue_depth = c.queue_depth.load(.monotonic),
        .max_queue_depth = c.max_queue_depth.load(.monotonic),
        .worker_queue_depth_max = c.max_queue_depth.load(.monotonic),
        .budget_rejections_total = c.budget_rejections_total.load(.monotonic),
        .backpressure_total = c.backpressure_total.load(.monotonic),
        .dropped_connections = c.dropped_connections.load(.monotonic),
    };
}

pub fn connectionStarted(c: *AtomicCounters) void {
    const active = c.active_connections.fetchAdd(1, .monotonic) + 1;
    maxCounter(&c.max_active_connections, active);
}

pub fn connectionEnded(c: *AtomicCounters) void {
    dec(&c.active_connections);
}

pub fn requestStarted(c: *AtomicCounters) void {
    const active = c.inflight_current.fetchAdd(1, .monotonic) + 1;
    maxCounter(&c.inflight_max, active);
}

pub fn requestCompleted(c: *AtomicCounters) void {
    inc(&c.completed_total);
    dec(&c.inflight_current);
}

pub fn resetAuditCounters(c: *AtomicCounters) void {
    const current = c.inflight_current.load(.monotonic);
    c.inflight_max.store(current, .monotonic);
    c.completed_total.store(0, .monotonic);
    c.queue_depth.store(0, .monotonic);
    c.max_queue_depth.store(0, .monotonic);
    c.budget_rejections_total.store(0, .monotonic);
    c.backpressure_total.store(0, .monotonic);
    c.bytes_read.store(0, .monotonic);
    c.bytes_written.store(0, .monotonic);
    c.connection_errors.store(0, .monotonic);
    c.malformed_frames.store(0, .monotonic);
    c.oversized_frames.store(0, .monotonic);
    c.protocol_errors.store(0, .monotonic);
    c.early_closes.store(0, .monotonic);
}

pub fn threadSpawned(c: *AtomicCounters) void {
    inc(&c.threads_spawned);
}

pub fn connectionError(c: *AtomicCounters) void {
    inc(&c.connection_errors);
}

pub fn droppedConnection(c: *AtomicCounters) void {
    inc(&c.dropped_connections);
    inc(&c.budget_rejections_total);
    inc(&c.backpressure_total);
}

pub fn setQueueDepth(c: *AtomicCounters, value: u64) void {
    c.queue_depth.store(value, .monotonic);
    maxCounter(&c.max_queue_depth, value);
}

pub fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        304 => "Not Modified",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        414 => "URI Too Long",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        else => "OK",
    };
}

pub fn parseMethod(value: []const u8) Method {
    if (std.mem.eql(u8, value, "GET")) return .GET;
    if (std.mem.eql(u8, value, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, value, "POST")) return .POST;
    if (std.mem.eql(u8, value, "PUT")) return .PUT;
    if (std.mem.eql(u8, value, "PATCH")) return .PATCH;
    if (std.mem.eql(u8, value, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, value, "OPTIONS")) return .OPTIONS;
    return .OTHER;
}

pub fn isTokenChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or switch (ch) {
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}

pub fn isReservedResponseHeader(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "content-type") or
        std.ascii.eqlIgnoreCase(name, "content-length") or
        std.ascii.eqlIgnoreCase(name, "connection") or
        std.ascii.eqlIgnoreCase(name, "date") or
        std.ascii.eqlIgnoreCase(name, "transfer-encoding");
}

pub fn validateResponseHeader(name: []const u8, value: []const u8) !void {
    if (name.len == 0 or name.len > 64 or value.len > 1024) return error.InvalidResponseHeader;
    if (isReservedResponseHeader(name)) return error.ReservedResponseHeader;
    for (name) |ch| if (!isTokenChar(ch)) return error.InvalidResponseHeader;
    for (value) |ch| if (ch == '\r' or ch == '\n') return error.InvalidResponseHeader;
}

pub fn validateResponseHeaders(headers: []const Header) !void {
    if (headers.len > 16) return error.TooManyResponseHeaders;
    for (headers) |header| try validateResponseHeader(header.name, header.value);
}

pub fn isRedirectStatus(status: u16) bool {
    return switch (status) {
        301, 302, 303, 307, 308 => true,
        else => false,
    };
}

pub fn validateRedirectLocation(location: []const u8) !void {
    if (location.len == 0 or location.len > 2048) return error.InvalidRedirectLocation;
    for (location) |ch| if (ch == '\r' or ch == '\n') return error.InvalidRedirectLocation;
}

pub const SameSite = enum { lax, strict, none };

pub const CookieOptions = struct {
    path: ?[]const u8 = "/",
    domain: ?[]const u8 = null,
    max_age: ?i64 = null,
    expires: ?[]const u8 = null,
    secure: bool = true,
    http_only: bool = true,
    same_site: ?SameSite = .lax,
};

fn isCookieOctet(ch: u8) bool {
    return switch (ch) {
        0x21, 0x23...0x2b, 0x2d...0x3a, 0x3c...0x5b, 0x5d...0x7e => true,
        else => false,
    };
}

fn validateCookieName(name: []const u8) !void {
    if (name.len == 0 or name.len > 64) return error.InvalidCookieName;
    for (name) |ch| if (!isTokenChar(ch)) return error.InvalidCookieName;
}

fn validateCookieValue(value: []const u8) !void {
    if (value.len > 4096) return error.InvalidCookieValue;
    for (value) |ch| if (!isCookieOctet(ch)) return error.InvalidCookieValue;
}

fn validateCookieAttrValue(value: []const u8) !void {
    if (value.len == 0 or value.len > 1024) return error.InvalidCookieAttribute;
    for (value) |ch| if (ch < 0x20 or ch == 0x7f or ch == ';' or ch == '\r' or ch == '\n') return error.InvalidCookieAttribute;
}

pub fn buildSetCookie(buffer: []u8, name: []const u8, value: []const u8, options: CookieOptions) ![]const u8 {
    try validateCookieName(name);
    try validateCookieValue(value);
    if (options.path) |path| try validateCookieAttrValue(path);
    if (options.domain) |domain| try validateCookieAttrValue(domain);
    if (options.expires) |expires| try validateCookieAttrValue(expires);
    if (options.same_site == .none and !options.secure) return error.InsecureSameSiteNone;

    var stream = std.Io.Writer.fixed(buffer);
    try stream.print("{s}={s}", .{ name, value });
    if (options.path) |path| try stream.print("; Path={s}", .{path});
    if (options.domain) |domain| try stream.print("; Domain={s}", .{domain});
    if (options.max_age) |max_age| try stream.print("; Max-Age={d}", .{max_age});
    if (options.expires) |expires| try stream.print("; Expires={s}", .{expires});
    if (options.secure) try stream.writeAll("; Secure");
    if (options.http_only) try stream.writeAll("; HttpOnly");
    if (options.same_site) |same_site| switch (same_site) {
        .lax => try stream.writeAll("; SameSite=Lax"),
        .strict => try stream.writeAll("; SameSite=Strict"),
        .none => try stream.writeAll("; SameSite=None"),
    };
    return stream.buffered();
}

pub fn isToken(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| if (!isTokenChar(ch)) return false;
    return true;
}

pub fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}
