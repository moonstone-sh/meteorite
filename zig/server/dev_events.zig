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
//!    "remote_addr":"..."|null,
//!    "headers":[{"name":"...","value":"..."},...],
//!    "body":"..."?,"body_bytes":<int>?}
//!
//! `headers` is the request's headers, in the order the client sent them
//! (order and duplicates are meaningful for HTTP, so this is an array of
//! pairs, never a map — see hydronium's cli/src/event_model.lua, the one
//! and only consumer contract this file targets). A handful of names that
//! commonly carry secrets (authorization, cookie, set-cookie,
//! proxy-authorization — matched case-insensitively) are ALWAYS redacted:
//! the header still appears, so the inspector can show it was present, but
//! its value is replaced with `"[redacted]"`. This file is written to disk
//! and there is currently no opt-out; if one is ever added it must be
//! explicit and default OFF.
//!
//! `body` is the request body, included only when it both (a) fits under
//! `max_body_bytes` and (b) is valid UTF-8 (checked directly -- content-type
//! sniffing is not trusted, since it can lie). Otherwise only `body_bytes`
//! is emitted: the real, untruncated body length, with no content. This is
//! the "measured but not included" case event_model.request_detail already
//! treats as first-class. Neither field is emitted when the body was never
//! read at all (most non-matched-route responses: 404s, static files,
//! OPTIONS preflights, ...) -- that is genuinely "not captured", distinct
//! from a captured-and-empty body.
//!
//! Both `headers` and body inclusion are also bounded dynamically against
//! the remaining space in the line buffer (see `line_buffer_bytes`): once
//! that runs low the line is completed anyway (closing brackets/braces and
//! a trailing `body_bytes`, never a mid-value cut), just with fewer headers
//! or without the body's content. The whole point of these fields adding
//! *more* data than the old five-field line is that a single oversized
//! request must never cause the WHOLE line -- method/path/status included
//! -- to be silently dropped the way an over-long line already was before
//! this file captured headers or bodies at all.
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

/// Header names redacted (name kept, value replaced) because they routinely
/// carry secrets. Matched case-insensitively. This stream is a plaintext
/// file on disk -- leaking a session cookie or bearer token into it would be
/// a real vulnerability, not a nit.
const redacted_header_names = [_][]const u8{
    "authorization",
    "cookie",
    "set-cookie",
    "proxy-authorization",
};

const redacted_placeholder = "[redacted]";

/// Per-request captured header count and per-header name/value length caps.
/// These bound how MUCH of a large header set we show, purely for
/// readability -- the dynamic capacity check below (not these constants) is
/// what actually guarantees the line never overflows.
const max_headers = 100;
const max_header_name_bytes = 200;
const max_header_value_bytes = 512;

/// Captured request body cap, in raw (pre-escape) bytes. A body at or under
/// this size, and valid UTF-8, is included verbatim (escaped); anything
/// larger reports only its real length via `body_bytes`.
const max_body_bytes = 1024;

/// Minimum space always kept free while writing the headers array, so that
/// whatever happens with the body afterward -- full content, size-only
/// fallback, or nothing -- there is always room left to close out a valid
/// line (`],"body_bytes":<up to 20 digits>}\n` in the worst case).
const tail_min_reserve_bytes = 96;

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
///
/// `Backend` is the comptime backend module (`zig/backends/*.zig`) that
/// accepted this connection; `request` is its `*Backend.Request`. Both are
/// needed only to read headers/body -- everything else stays exactly the
/// scalar values the previous signature took. Header capture uses
/// `Backend.forEachHeader` when the backend declares it (all four backends
/// do); body capture reads `request.body_cache` directly when the field
/// exists, with no extra read triggered here -- whatever the request
/// pipeline already read (or didn't) for its own purposes is exactly what
/// gets reported, so this never forces an unwanted body read and never
/// touches the (unrelated) response-streaming path.
pub fn logRequest(
    io: Io,
    comptime Backend: type,
    request: *Backend.Request,
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

    writer.writeAll(",\"headers\":[") catch return;
    var header_ctx = HeaderCtx{ .writer = &writer };
    if (comptime @hasDecl(Backend, "forEachHeader")) {
        Backend.forEachHeader(request, &header_ctx, HeaderCtx.emit);
    }
    writer.writeByte(']') catch return;

    writeBodyFields(&writer, requestBodyCache(Backend, request));

    writer.writeAll("}\n") catch return;

    file.writeStreamingAll(io, writer.buffered()) catch return;
}

fn requestBodyCache(comptime Backend: type, request: *Backend.Request) ?[]const u8 {
    if (comptime @hasField(Backend.Request, "body_cache")) return request.body_cache;
    return null;
}

fn isRedactedHeaderName(name: []const u8) bool {
    for (redacted_header_names) |candidate| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}

/// Truncates `bytes` to at most `max_len` bytes without splitting a UTF-8
/// codepoint: walks back one byte at a time (at most 3 steps, the longest a
/// UTF-8 sequence can be) until the prefix validates. Used on values we are
/// about to escape and embed in a JSON string, where a half codepoint would
/// otherwise become invalid JSON string content.
fn utf8SafeTruncate(bytes: []const u8, max_len: usize) []const u8 {
    if (bytes.len <= max_len) return bytes;
    var end = max_len;
    while (end > 0 and !std.unicode.utf8ValidateSlice(bytes[0..end])) end -= 1;
    return bytes[0..end];
}

const HeaderCtx = struct {
    writer: *Io.Writer,
    wrote_any: bool = false,
    count: usize = 0,
    stopped: bool = false,

    /// Matches the `cb: fn (@TypeOf(ctx), []const u8, []const u8) void`
    /// shape every backend's `forEachHeader` expects. Never returns an
    /// error: a header that will not fit just stops the loop (`stopped`),
    /// it does not fail the line -- `tail_min_reserve_bytes` guarantees
    /// there is always room left to close the line out afterward.
    fn emit(self: *HeaderCtx, name: []const u8, value: []const u8) void {
        if (self.stopped or name.len == 0) return;
        if (self.count >= max_headers) {
            self.stopped = true;
            return;
        }

        const shown_name = utf8SafeTruncate(name, max_header_name_bytes);
        const redact = isRedactedHeaderName(name);
        const shown_value = if (redact) redacted_placeholder else utf8SafeTruncate(value, max_header_value_bytes);

        // Worst case every byte becomes a `\u00XX` escape (6 bytes) plus
        // the entry's own JSON punctuation. Deliberately pessimistic: this
        // is what guarantees `emit` never hands `writeEscaped` more than
        // the buffer can hold.
        const worst_case = 24 + shown_name.len * 6 + shown_value.len * 6;
        if (self.writer.unusedCapacitySlice().len < worst_case + tail_min_reserve_bytes) {
            self.stopped = true;
            return;
        }

        if (self.wrote_any) {
            self.writer.writeByte(',') catch {
                self.stopped = true;
                return;
            };
        }
        self.writer.writeAll("{\"name\":\"") catch {
            self.stopped = true;
            return;
        };
        writeEscaped(self.writer, shown_name) catch {
            self.stopped = true;
            return;
        };
        self.writer.writeAll("\",\"value\":\"") catch {
            self.stopped = true;
            return;
        };
        writeEscaped(self.writer, shown_value) catch {
            self.stopped = true;
            return;
        };
        self.writer.writeAll("\"}") catch {
            self.stopped = true;
            return;
        };
        self.wrote_any = true;
        self.count += 1;
    }
};

/// Writes `,"body":"..."` (escaped) and/or `,"body_bytes":<n>` -- or
/// neither, when `body` is null (never read: no route matched, or the
/// matched route/response never touched the body). `body_bytes` is always
/// the real, untruncated length whenever a body was read at all, even when
/// its content is left out.
fn writeBodyFields(writer: *Io.Writer, body: ?[]const u8) void {
    const content = body orelse return;

    // A zero-length body is NOT "a body that happens to be empty" -- it is an
    // ordinary bodyless request (every GET) whose pipeline handed us an empty
    // slice rather than null. Emitting `"body":"","body_bytes":0` for those
    // makes the consumer's `has_body` true for essentially every request:
    // hydronium's event_model computes `has_body = body ~= nil or body_bytes
    // > 0`, so an empty string counts. The inspector would then show an empty
    // body section on every GET, which is noise that crowds out the requests
    // that really do carry one. Emit nothing, exactly as for a body we never
    // read -- from the consumer's side both are honestly "no body here".
    if (content.len == 0) return;

    const fits = content.len <= max_body_bytes;
    const is_text = fits and std.unicode.utf8ValidateSlice(content);
    if (is_text) {
        const worst_case = 40 + content.len * 6;
        if (writer.unusedCapacitySlice().len >= worst_case + tail_min_reserve_bytes) {
            writer.writeAll(",\"body\":\"") catch return;
            writeEscaped(writer, content) catch return;
            writer.writeAll("\"") catch return;
            writer.print(",\"body_bytes\":{d}", .{content.len}) catch return;
            return;
        }
    }
    // Too large, not valid UTF-8, or not enough room left in the line:
    // report the real size without the content. This is the same
    // "measured but not included" shape whether the reason is size,
    // binary content, or buffer pressure -- the consumer does not need to
    // know which.
    writer.print(",\"body_bytes\":{d}", .{content.len}) catch return;
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

test "redacted header names match case-insensitively" {
    try std.testing.expect(isRedactedHeaderName("Authorization"));
    try std.testing.expect(isRedactedHeaderName("COOKIE"));
    try std.testing.expect(isRedactedHeaderName("Set-Cookie"));
    try std.testing.expect(isRedactedHeaderName("proxy-authorization"));
    try std.testing.expect(!isRedactedHeaderName("content-type"));
}

test "utf8SafeTruncate never splits a codepoint" {
    const s = "a\xE2\x82\xACb"; // "a€b", € is 3 bytes
    try std.testing.expectEqualStrings("a", utf8SafeTruncate(s, 3));
    try std.testing.expectEqualStrings("a\xE2\x82\xACb", utf8SafeTruncate(s, 10));
}

test "writeBodyFields omits body but keeps body_bytes for an oversized body" {
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    const big = "x" ** (max_body_bytes + 1);
    writeBodyFields(&writer, big);
    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"body\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, ",\"body_bytes\":1025") != null);
}

test "writeBodyFields omits body for non-UTF-8 content" {
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    const binary = [_]u8{ 0xff, 0xfe, 0x00, 0x01 };
    writeBodyFields(&writer, &binary);
    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"body\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, ",\"body_bytes\":4") != null);
}

test "writeBodyFields includes small text bodies verbatim" {
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    writeBodyFields(&writer, "{\"ok\":true}");
    const out = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "\"body\":\"{\\\"ok\\\":true}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ",\"body_bytes\":11") != null);
}
