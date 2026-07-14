const std = @import("std");
const Io = std.Io;

var started = std.atomic.Value(bool).init(false);
var cached_seconds = std.atomic.Value(i64).init(0);

fn timerWorker(io: Io) void {
    while (true) {
        cached_seconds.store(Io.Timestamp.now(io, .real).toSeconds(), .release);
        io.sleep(.{ .nanoseconds = std.time.ns_per_s }, .real) catch {};
    }
}

pub fn start(io: Io) void {
    if (!started.swap(true, .acquire)) {
        cached_seconds.store(Io.Timestamp.now(io, .real).toSeconds(), .release);
        const thread = std.Thread.spawn(.{}, timerWorker, .{io}) catch unreachable;
        thread.detach();
    }
}

pub fn seconds() i64 {
    return cached_seconds.load(.acquire);
}
