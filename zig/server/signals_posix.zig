const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const native_os = builtin.os.tag;

/// Atomic shutdown flag set by SIGINT/SIGTERM handlers.
/// The accept loop and pool workers check this to initiate graceful shutdown.
var shutdown_requested = std.atomic.Value(bool).init(false);

/// Self-pipe used to wake a thread blocked waiting to accept a connection
/// the instant a signal arrives, instead of only noticing it once the next
/// real connection shows up.
///
/// Zig 0.16 moved `read`/`write`/`pipe`/`exit` off `std.posix` onto the
/// `std.Io` interface, which is not async-signal-safe (it can allocate,
/// take locks, or dispatch through a vtable) and so must never be called
/// from a signal handler. This file therefore talks to the two platforms
/// Meteorite ships on directly, bypassing `std.Io` and `std.posix` for
/// exactly these four primitives:
///   - Linux: raw syscalls via `std.os.linux`. These work whether or not
///     libc is linked, which matters for `-Dmode=release-static` builds
///     that never request libc.
///   - Everything else (macOS/BSD): `std.c`. Darwin has no stable raw
///     syscall ABI of its own, so Zig always links libSystem there
///     regardless of build mode -- verified against this repo's own build:
///     `otool -L` on a `release-static`, no-Lua `dist/server` still shows
///     libSystem linked.
var wake_read_fd: posix.fd_t = -1;
var wake_write_fd: posix.fd_t = -1;

const raw = if (native_os == .linux) linux_raw else libc_raw;

const linux_raw = struct {
    const linux = std.os.linux;

    fn pipe() ?[2]posix.fd_t {
        var fds: [2]i32 = .{ -1, -1 };
        const rc = linux.pipe2(&fds, .{ .CLOEXEC = true, .NONBLOCK = true });
        if (linux.errno(rc) != .SUCCESS) return null;
        return fds;
    }

    fn write1(fd: posix.fd_t, byte: u8) void {
        var buf = [1]u8{byte};
        _ = linux.write(fd, &buf, 1);
    }

    fn drain(fd: posix.fd_t) void {
        var buf: [64]u8 = undefined;
        while (true) {
            const rc = linux.read(fd, &buf, buf.len);
            if (linux.errno(rc) != .SUCCESS or rc == 0) break;
        }
    }

    fn forceExit(code: u8) noreturn {
        linux.exit_group(code);
    }
};

const libc_raw = struct {
    fn pipe() ?[2]posix.fd_t {
        var fds: [2]posix.fd_t = .{ -1, -1 };
        if (std.c.pipe(&fds) != 0) return null;
        const cloexec: c_int = posix.FD_CLOEXEC;
        _ = std.c.fcntl(fds[0], posix.F.SETFD, cloexec);
        _ = std.c.fcntl(fds[1], posix.F.SETFD, cloexec);
        // Nonblocking is what makes `drain`'s loop below terminate: without
        // it, the read that empties the last byte blocks forever instead of
        // returning EAGAIN, since the write end stays open.
        const nonblock: c_int = @bitCast(posix.O{ .NONBLOCK = true });
        _ = std.c.fcntl(fds[0], posix.F.SETFL, nonblock);
        _ = std.c.fcntl(fds[1], posix.F.SETFL, nonblock);
        return fds;
    }

    fn write1(fd: posix.fd_t, byte: u8) void {
        var buf = [1]u8{byte};
        _ = std.c.write(fd, &buf, 1);
    }

    fn drain(fd: posix.fd_t) void {
        var buf: [64]u8 = undefined;
        while (true) {
            const n = std.c.read(fd, &buf, buf.len);
            if (n <= 0) break; // 0 = EOF (can't happen, we hold the write end); <0 = EAGAIN once drained
        }
    }

    fn forceExit(code: u8) noreturn {
        std.c._exit(code);
    }
};

/// Install SIGINT and SIGTERM handlers and create the self-pipe they use to
/// wake a thread blocked waiting to accept a connection. Call once at
/// server startup, before entering the accept loop.
pub fn installHandlers() void {
    if (raw.pipe()) |fds| {
        wake_read_fd = fds[0];
        wake_write_fd = fds[1];
    } else {
        // No self-pipe: the shutdown flag still gets set by the handler
        // below, so the server still exits -- just only once something
        // else makes the accept loop check it (e.g. the next connection),
        // same as before this fix. Startup itself must not fail over this.
        std.debug.print("meteorite: failed to create shutdown self-pipe; SIGINT/SIGTERM while idle may be delayed\n", .{});
    }

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

/// Signal the shutdown flag directly (for programmatic shutdown), and wake
/// anything blocked in `waitForAcceptable` the same way a real signal would.
pub fn requestShutdown() void {
    if (!shutdown_requested.swap(true, .acq_rel)) wake();
}

fn wake() void {
    if (wake_write_fd >= 0) raw.write1(wake_write_fd, 1);
}

fn signalHandler(sig: posix.SIG) callconv(.c) void {
    if (shutdown_requested.swap(true, .acq_rel)) {
        // Second SIGINT/SIGTERM: a graceful shutdown is already under way
        // (or stuck). _exit()/exit_group() is async-signal-safe -- no
        // atexit handlers, no stdio flushing, no allocation -- unlike
        // std.process.exit(), which calls libc exit() when libc is linked.
        // 128+signal matches the shell convention for "killed by signal N"
        // (130 for SIGINT, 143 for SIGTERM), since that is effectively
        // what just happened.
        const signum: u8 = @intCast(@intFromEnum(sig));
        raw.forceExit(128 + signum);
    }
    wake();
}

/// Blocks until either `listen_fd` has a pending connection or a shutdown
/// was requested, whichever happens first. Returns `true` when the caller
/// should proceed to `accept()`, `false` when it should shut down instead.
///
/// This is the actual fix for "ignores SIGINT/SIGTERM while idle": the
/// accept loop used to check `isShutdownRequested()` only immediately
/// *before* a blocking `accept()` call, so a signal delivered while already
/// blocked there was invisible until the next connection arrived (Zig's
/// std.Io accept retries on EINTR internally, so the signal alone never
/// unblocks it). Polling the listening socket next to the self-pipe means
/// the pipe write from the signal handler always wakes this immediately,
/// and the flag is then re-checked with no intervening blocking syscall --
/// the listening socket itself is never shut down or closed to achieve
/// this, so a real pending connection can never be lost or misdirected.
pub fn waitForAcceptable(listen_fd: posix.fd_t) bool {
    if (isShutdownRequested()) return false;
    if (wake_read_fd < 0) return true; // no self-pipe: fall back to the old behavior
    var fds = [2]posix.pollfd{
        .{ .fd = listen_fd, .events = posix.POLL.IN, .revents = 0 },
        .{ .fd = wake_read_fd, .events = posix.POLL.IN, .revents = 0 },
    };
    _ = posix.poll(&fds, -1) catch return !isShutdownRequested();
    if (fds[1].revents != 0) {
        raw.drain(wake_read_fd);
        return false;
    }
    return !isShutdownRequested();
}
