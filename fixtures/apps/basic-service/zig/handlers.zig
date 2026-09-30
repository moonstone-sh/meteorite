const std = @import("std");
const builtin = @import("builtin");

pub fn health(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

// Used by fixtures/tests/signal-shutdown.sh to hold a request in flight
// while a shutdown signal is sent, long enough (1s) to reliably straddle
// normal process/network scheduling jitter in that test.
pub fn sleep_1s(ctx: anytype) !void {
    // A static Linux build does not link libc (macOS always does), so use
    // the raw syscall there; std.c.nanosleep would fail to compile.
    if (builtin.os.tag == .linux and !builtin.link_libc) {
        const linux = std.os.linux;
        var req: linux.timespec = .{ .sec = 1, .nsec = 0 };
        var rem: linux.timespec = undefined;
        while (linux.errno(linux.nanosleep(&req, &rem)) == .INTR) {
            req = rem;
        }
    } else {
        var req: std.c.timespec = .{ .sec = 1, .nsec = 0 };
        var rem: std.c.timespec = undefined;
        while (std.c.nanosleep(&req, &rem) != 0) {
            req = rem;
        }
    }
    try ctx.text(200, "slept");
}

pub fn get_user(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    try ctx.bytes(200, "application/json", id);
}

pub fn put_user(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    const body = try ctx.body();
    _ = body;
    try ctx.text(200, id);
}

pub fn patch_user(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    const body = try ctx.body();
    _ = body;
    try ctx.text(200, id);
}

pub fn delete_user(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    try ctx.text(200, id);
}

pub fn echo(ctx: anytype) !void {
    const value = try ctx.body();
    try ctx.text(200, value);
}

pub fn get_device(ctx: anytype) !void {
    const id = ctx.param("device_id") orelse "missing";
    try ctx.bytes(200, "application/json", id);
}

pub fn file(ctx: anytype) !void {
    const name = ctx.param("name") orelse "missing";
    try ctx.text(200, name);
}

pub fn slug(ctx: anytype) !void {
    const value = ctx.param("slug") orelse "missing";
    try ctx.text(200, value);
}

pub fn uuid(ctx: anytype) !void {
    const value = ctx.param("id") orelse "missing";
    try ctx.text(200, value);
}

pub fn hex(ctx: anytype) !void {
    const value = ctx.param("digest") orelse "missing";
    try ctx.text(200, value);
}

pub fn search(ctx: anytype) !void {
    const q = ctx.query.q;
    try ctx.text(200, q);
}
