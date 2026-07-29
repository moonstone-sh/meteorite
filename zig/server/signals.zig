const std = @import("std");
const posix = std.posix;

/// Atomic shutdown flag set by SIGINT/SIGTERM handlers.
/// The accept loop and pool workers check this to initiate graceful shutdown.
var shutdown_requested = std.atomic.Value(bool).init(false);

/// Install SIGINT and SIGTERM handlers that set the shutdown flag.
/// Call once at server startup, before entering the accept loop.
pub fn installHandlers() void {
    const handler = posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(.INT, &handler, null);
    posix.sigaction(.TERM, &handler, null);
}

/// Returns true if SIGINT or SIGTERM was received.
pub fn isShutdownRequested() bool {
    return shutdown_requested.load(.acquire);
}

/// Signal the shutdown flag directly (for programmatic shutdown).
pub fn requestShutdown() void {
    shutdown_requested.store(true, .release);
}

fn signalHandler(_: posix.SIG) callconv(.c) void {
    shutdown_requested.store(true, .release);
    std.process.exit(0);
}
