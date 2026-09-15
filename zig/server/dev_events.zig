//! Opt-in, append-only dev event stream (newline-delimited JSON).
//!
//! Entirely comptime-gated on the `-Ddev-events=<path>` build option: when it is
//! empty — every production build, and every dev build that did not ask for it —
//! `enabled` is `false`, `logRequest` bodies out to `return` before touching
//! anything, and there is no runtime branch, no state and no open file.
//!
//! When a path is configured the file is opened lazily on first use with
//! O_APPEND, so each `write` of a whole line is atomic with respect to the other
//! connection threads writing to the same descriptor; no per-write locking and
//! no interleaved half-lines. The supervisor (`src/cli/dev.lua`) appends its own
//! `"source":"supervisor"` lines to the same file the same way.
//!
//! Schema (one object per line):
//!   {"v":1,"ts":<unix ms>,"source":"server","kind":"request",
//!    "method":"...","path":"...","status":<int>,"duration_ms":<number>,
//!    "remote_addr":"..."|null}
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const build_options = @import("build_options");

/// Configured path, or "" when the feature was not built in.
pub const path = build_options.dev_events_path;

/// Comptime feature gate. Everything below is dead code when this is false.
pub const enabled = path.len > 0 and builtin.os.tag != .windows;

/// Longest line we will emit. A request path is capped by the backends well
/// below this; anything that still would not fit is dropped rather than
/// truncated into invalid JSON.
const line_buffer_bytes = 8192;

var open_mutex: Io.Mutex = .init;
var open_attempted: bool = false;
var open_fd: std.posix.fd_t = -1;

fn handle(io: Io) ?Io.File {
    if (!@atomicLoad(bool, &open_attempted, .acquire)) {
        open_mutex.lockUncancelable(io);
        defer open_mutex.unlock(io);
        if (!open_attempted) {
            open_fd = std.posix.openat(
                std.posix.AT.FDCWD,
                path,
                .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true },
                0o644,
            ) catch -1;
            @atomicStore(bool, &open_attempted, true, .release);
        }
    }
    if (open_fd < 0) return null;
    return .{ .handle = open_fd, .flags = .{ .nonblocking = false } };
}

/// Append one `kind:"request"` line. Never fails the request it describes: any
/// error (unopenable path, oversized line, short write) silently drops the line.
pub fn logRequest(
    io: Io,
    method: []const u8,
    request_path: []const u8,
    status: u16,
    duration_ns: i96,
    remote_addr: ?[]const u8,
) void {
    if (comptime !enabled) return;
    const file = handle(io) orelse return;

    var buffer: [line_buffer_bytes]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    const unix_ms = @divTrunc(Io.Timestamp.now(io, .real).toNanoseconds(), std.time.ns_per_ms);
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / @as(f64, std.time.ns_per_ms);

    writer.print("{{\"v\":1,\"ts\":{d},\"source\":\"server\",\"kind\":\"request\",\"method\":\"", .{unix_ms}) catch return;
    writeEscaped(&writer, method) catch return;
    writer.writeAll("\",\"path\":\"") catch return;
    writeEscaped(&writer, request_path) catch return;
    writer.print("\",\"status\":{d},\"duration_ms\":{d:.3},\"remote_addr\":", .{ status, duration_ms }) catch return;
    if (remote_addr) |value| {
        writer.writeByte('"') catch return;
        writeEscaped(&writer, value) catch return;
        writer.writeByte('"') catch return;
    } else {
        writer.writeAll("null") catch return;
    }
    writer.writeAll("}\n") catch return;

    file.writeStreamingAll(io, writer.buffered()) catch return;
}

fn writeEscaped(writer: *Io.Writer, text: []const u8) !void {
    for (text) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...8, 11, 12, 14...31, 127 => try writer.print("\\u{x:0>4}", .{byte}),
        else => try writer.writeByte(byte),
    };
}

test "control characters and quotes are escaped" {
    var buffer: [128]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    try writeEscaped(&writer, "a\"b\\c\nd\x01e");
    try std.testing.expectEqualStrings("a\\\"b\\\\c\\nd\\u0001e", writer.buffered());
}
