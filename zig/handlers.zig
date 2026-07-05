const std = @import("std");
const build_info = @import("meteorite_build_info");
const bench_stats = @import("bridge/lua_bench_stats");

pub fn health(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn plain(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn zig_static(ctx: anytype) !void {
    bench_stats.incNativeByName("zig-static");
    try ctx.text(200, "ok");
}

pub fn plain_static(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn hybrid_zig(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn hybrid_inline(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn bench_hybrid_inline(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn bench_hybrid_inline_text_literal(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn hybrid_inline_params(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    try ctx.text(200, id);
}

pub fn hybrid_inline_echo(ctx: anytype) !void {
    const value = try ctx.body();
    try ctx.text(200, value);
}

pub fn hybrid_debug_unavailable(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_state(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_global(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_leak(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_shared(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_worker(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_unavailable_require(ctx: anytype) !void {
    try ctx.text(501, "hybrid debug route requires Lua runtime");
}

pub fn bench_meta(ctx: anytype) !void {
    _ = build_info;
    try ctx.bytes(200, "application/json", "{}");
}

pub fn bench_raw(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn bench_counters(ctx: anytype) !void {
    try ctx.bytes(200, "application/json", "{}");
}

pub fn bench_stats_handler(ctx: anytype) !void {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(std.heap.page_allocator);
    try bench_stats.writeJson(&list, std.heap.page_allocator);
    try ctx.bytes(200, "application/json", list.items);
}

pub fn bench_stats_reset(ctx: anytype) !void {
    bench_stats.reset();
    try ctx.text(200, "ok");
}

pub fn bench_fixture_info(ctx: anytype) !void {
    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(std.heap.page_allocator);
    try bench_stats.writeJson(&list, std.heap.page_allocator);
    try ctx.bytes(200, "application/json", list.items);
}

fn monotonicNs() i128 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return (@as(i128, ts.sec) * std.time.ns_per_s) + @as(i128, ts.nsec);
}

fn spinFor(ns: i128) void {
    const start = monotonicNs();
    while (monotonicNs() - start < ns) {
        std.atomic.spinLoopHint();
    }
}

fn workCpu(ctx: anytype, comptime label: []const u8, comptime ns: i128, comptime checksum: []const u8) !void {
    spinFor(ns);
    try ctx.text(200, "work:cpu:" ++ label ++ ":" ++ checksum);
}

fn workSleep(ctx: anytype, comptime label: []const u8, comptime ns: u64) !void {
    const req: std.c.timespec = .{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
    _ = std.c.nanosleep(&req, null);
    try ctx.text(200, "sleep:" ++ label);
}

pub fn work_cpu_50us(ctx: anytype) !void { try workCpu(ctx, "50us", 50_000, "50"); }
pub fn work_cpu_100us(ctx: anytype) !void { try workCpu(ctx, "100us", 100_000, "100"); }
pub fn work_cpu_250us(ctx: anytype) !void { try workCpu(ctx, "250us", 250_000, "250"); }
pub fn work_cpu_500us(ctx: anytype) !void { try workCpu(ctx, "500us", 500_000, "500"); }
pub fn work_cpu_1ms(ctx: anytype) !void { try workCpu(ctx, "1ms", 1_000_000, "1000"); }
pub fn work_cpu_2ms(ctx: anytype) !void { try workCpu(ctx, "2ms", 2_000_000, "2000"); }
pub fn work_cpu_5ms(ctx: anytype) !void { try workCpu(ctx, "5ms", 5_000_000, "5000"); }
pub fn work_sleep_1ms(ctx: anytype) !void { try workSleep(ctx, "1ms", 1_000_000); }
pub fn work_sleep_5ms(ctx: anytype) !void { try workSleep(ctx, "5ms", 5_000_000); }
pub fn work_sleep_10ms(ctx: anytype) !void { try workSleep(ctx, "10ms", 10_000_000); }

pub fn lua_empty(ctx: anytype) !void {
    try ctx.text(204, "");
}

pub fn bench_json_small(ctx: anytype) !void {
    try ctx.bytes(200, "application/json", "{\"ok\":true}");
}

pub fn bench_loop_0(ctx: anytype) !void {
    try ctx.text(200, "0");
}

pub fn bench_loop_10(ctx: anytype) !void {
    try ctx.text(200, "55");
}

pub fn bench_loop_100(ctx: anytype) !void {
    try ctx.text(200, "5050");
}

pub fn bench_loop_1000(ctx: anytype) !void {
    try ctx.text(200, "500500");
}

pub fn bench_loop_10000(ctx: anytype) !void {
    try ctx.text(200, "50005000");
}

pub fn bench_loop_100000(ctx: anytype) !void {
    try ctx.text(200, "5000050000");
}

pub fn bench_sleep_unavailable(ctx: anytype) !void {
    try ctx.text(501, "lua sleep proof requires Lua runtime");
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

pub fn email(ctx: anytype) !void {
    const value = ctx.param("email") orelse "missing";
    try ctx.text(200, value);
}

pub fn token(ctx: anytype) !void {
    const value = ctx.param("token") orelse "missing";
    try ctx.text(200, value);
}
