//! Peer (remote) address capture for the real network backends.
//!
//! `Io.net.Server.accept` returns only a `Stream`, so the accepted peer's
//! address has to be read back off the socket with `getpeername`. The result is
//! rendered once, at accept() time, into caller-owned storage: a `Request` is
//! copied by value between the accept loop, the thread box and the pool queue,
//! so a slice pointing at another allocation would dangle. Storing the bytes
//! inline (plus a length) keeps the value copyable, exactly like the existing
//! `target_value`/`target_storage` pair.
//!
//! Only the address is rendered, not the ephemeral source port: the consumer of
//! this is a dev-tool "IP" column.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

/// INET6_ADDRSTRLEN.
pub const max_len = 46;

pub const Storage = [max_len]u8;

/// Render the connected peer's address into `storage`, setting `out_len` to the
/// number of bytes written (0 when unavailable: unix sockets, unsupported
/// address families, or a failed `getpeername`).
pub fn capture(stream: Io.net.Stream, storage: *Storage, out_len: *u8) void {
    out_len.* = 0;
    if (comptime builtin.os.tag == .windows) return;
    var addr: std.posix.sockaddr.storage = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
    std.posix.getpeername(stream.socket.handle, @ptrCast(&addr), &addr_len) catch return;
    var writer = Io.Writer.fixed(storage);
    switch (addr.family) {
        std.posix.AF.INET => {
            const in: *const std.posix.sockaddr.in = @ptrCast(@alignCast(&addr));
            writeIp4(&writer, @bitCast(in.addr)) catch return;
        },
        std.posix.AF.INET6 => {
            const in6: *const std.posix.sockaddr.in6 = @ptrCast(@alignCast(&addr));
            writeIp6(&writer, in6.addr) catch return;
        },
        else => return,
    }
    out_len.* = @intCast(writer.buffered().len);
}

fn writeIp4(writer: *Io.Writer, bytes: [4]u8) !void {
    try writer.print("{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] });
}

/// Uncompressed group form (no "::" elision), which is unambiguous and cheap.
/// IPv4-mapped addresses — what a dual-stack listener reports for an IPv4
/// client — are rendered as the IPv4 address they actually are.
fn writeIp6(writer: *Io.Writer, bytes: [16]u8) !void {
    const v4_mapped_prefix = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff };
    if (std.mem.eql(u8, bytes[0..12], &v4_mapped_prefix)) {
        return writeIp4(writer, bytes[12..16].*);
    }
    var index: usize = 0;
    while (index < 16) : (index += 2) {
        if (index != 0) try writer.writeByte(':');
        const group = (@as(u16, bytes[index]) << 8) | bytes[index + 1];
        try writer.print("{x}", .{group});
    }
}

test "IPv4-mapped IPv6 renders as IPv4" {
    var storage: Storage = undefined;
    var writer = Io.Writer.fixed(&storage);
    try writeIp6(&writer, .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 127, 0, 0, 1 });
    try std.testing.expectEqualStrings("127.0.0.1", writer.buffered());
}

test "IPv6 renders as uncompressed groups" {
    var storage: Storage = undefined;
    var writer = Io.Writer.fixed(&storage);
    try writeIp6(&writer, .{ 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });
    try std.testing.expectEqualStrings("2001:db8:0:0:0:0:0:1", writer.buffered());
}
