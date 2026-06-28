const std = @import("std");

/// Shared HTTP protocol types used by all backends.
/// Backends import this to avoid duplicating counter logic and method enums.

pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OTHER };

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

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

pub const AtomicCounter = std.atomic.Value(u64);

pub const AtomicCounters = struct {
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
        .total_connections = total,
        .accepted_connections = total,
        .threads_spawned = c.threads_spawned.load(.monotonic),
        .requests_served = served,
        .requests_per_connection = if (total == 0) 0 else served / total,
        .keepalive_reuse_count = c.keepalive_reuse_count.load(.monotonic),
        .connection_close_count = c.connection_close_count.load(.monotonic),
        .bytes_read = c.bytes_read.load(.monotonic),
        .bytes_written = c.bytes_written.load(.monotonic),
        .connection_errors = c.connection_errors.load(.monotonic),
        .max_active_connections = c.max_active_connections.load(.monotonic),
        .queue_depth = c.queue_depth.load(.monotonic),
        .max_queue_depth = c.max_queue_depth.load(.monotonic),
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

pub fn threadSpawned(c: *AtomicCounters) void {
    inc(&c.threads_spawned);
}

pub fn connectionError(c: *AtomicCounters) void {
    inc(&c.connection_errors);
}

pub fn droppedConnection(c: *AtomicCounters) void {
    inc(&c.dropped_connections);
}

pub fn setQueueDepth(c: *AtomicCounters, value: u64) void {
    c.queue_depth.store(value, .monotonic);
    maxCounter(&c.max_queue_depth, value);
}

pub fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        304 => "Not Modified",
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

pub fn parseMethod(value: []const u8) Method {
    if (std.mem.eql(u8, value, "GET")) return .GET;
    if (std.mem.eql(u8, value, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, value, "POST")) return .POST;
    if (std.mem.eql(u8, value, "PUT")) return .PUT;
    if (std.mem.eql(u8, value, "PATCH")) return .PATCH;
    if (std.mem.eql(u8, value, "DELETE")) return .DELETE;
    return .OTHER;
}

pub fn trimCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}
