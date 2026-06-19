const std = @import("std");
const build_info = @import("meteorite_build_info");

pub fn health(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn plain(ctx: anytype) !void {
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
