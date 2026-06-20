const std = @import("std");
const handlers = @import("meteorite_handlers");
const validators = @import("meteorite_validators");
const mt = @import("meteorite_ctx");

comptime {
    if (!@hasDecl(handlers, "bench_counters")) @compileError("route GET /__bench/counters references missing handler `handlers.bench_counters`\n\ndeclared at:\n  src/app.lua:23:1\n\nhint:\n  define `pub fn bench_counters(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_hybrid_inline")) @compileError("route GET /__bench/hybrid-inline references missing handler `handlers.bench_hybrid_inline`\n\ndeclared at:\n  src/app.lua:136:1\n\nhint:\n  define `pub fn bench_hybrid_inline(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_hybrid_inline_text_literal")) @compileError("route GET /__bench/hybrid-inline-text-literal references missing handler `handlers.bench_hybrid_inline_text_literal`\n\ndeclared at:\n  src/app.lua:137:1\n\nhint:\n  define `pub fn bench_hybrid_inline_text_literal(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_meta")) @compileError("route GET /__bench/meta references missing handler `handlers.bench_meta`\n\ndeclared at:\n  src/app.lua:21:1\n\nhint:\n  define `pub fn bench_meta(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_raw")) @compileError("route GET /__bench/raw references missing handler `handlers.bench_raw`\n\ndeclared at:\n  src/app.lua:22:1\n\nhint:\n  define `pub fn bench_raw(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_global")) @compileError("route GET /__bench/lua-global-counter references missing handler `handlers.bench_unavailable_global`\n\ndeclared at:\n  src/app.lua:146:1\n\nhint:\n  define `pub fn bench_unavailable_global(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_leak")) @compileError("route GET /__bench/lua-state-leak references missing handler `handlers.bench_unavailable_leak`\n\ndeclared at:\n  src/app.lua:147:1\n\nhint:\n  define `pub fn bench_unavailable_leak(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_require")) @compileError("route GET /__bench/lua-require-cache references missing handler `handlers.bench_unavailable_require`\n\ndeclared at:\n  src/app.lua:150:1\n\nhint:\n  define `pub fn bench_unavailable_require(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_shared")) @compileError("route GET /__bench/lua-shared-store references missing handler `handlers.bench_unavailable_shared`\n\ndeclared at:\n  src/app.lua:148:1\n\nhint:\n  define `pub fn bench_unavailable_shared(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_state")) @compileError("route GET /__bench/lua-debug-state references missing handler `handlers.bench_unavailable_state`\n\ndeclared at:\n  src/app.lua:145:1\n\nhint:\n  define `pub fn bench_unavailable_state(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "bench_unavailable_worker")) @compileError("route GET /__bench/lua-worker-store references missing handler `handlers.bench_unavailable_worker`\n\ndeclared at:\n  src/app.lua:149:1\n\nhint:\n  define `pub fn bench_unavailable_worker(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "delete_user")) @compileError("route DELETE /users/:id references missing handler `handlers.delete_user`\n\ndeclared at:\n  src/app.lua:38:1\n\nhint:\n  define `pub fn delete_user(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "echo")) @compileError("route POST /echo references missing handler `handlers.echo`\n\ndeclared at:\n  src/app.lua:42:1\n\nhint:\n  define `pub fn echo(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "email")) @compileError("route GET /emails/:email references missing handler `handlers.email`\n\ndeclared at:\n  src/app.lua:78:1\n\nhint:\n  define `pub fn email(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "file")) @compileError("route GET /files/:name references missing handler `handlers.file`\n\ndeclared at:\n  src/app.lua:60:1\n\nhint:\n  define `pub fn file(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "get_device")) @compileError("route GET /devices/:device_id references missing handler `handlers.get_device`\n\ndeclared at:\n  src/app.lua:54:1\n\nhint:\n  define `pub fn get_device(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "get_user")) @compileError("route GET /users/:id references missing handler `handlers.get_user`\n\ndeclared at:\n  src/app.lua:26:1\n\nhint:\n  define `pub fn get_user(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "health")) @compileError("route GET /health references missing handler `handlers.health`\n\ndeclared at:\n  src/app.lua:25:1\n\nhint:\n  define `pub fn health(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hex")) @compileError("route GET /hex/:digest references missing handler `handlers.hex`\n\ndeclared at:\n  src/app.lua:74:1\n\nhint:\n  define `pub fn hex(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hybrid_inline")) @compileError("route GET /hybrid-inline references missing handler `handlers.hybrid_inline`\n\ndeclared at:\n  src/app.lua:135:1\n\nhint:\n  define `pub fn hybrid_inline(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hybrid_inline_echo")) @compileError("route POST /__bench/hybrid-inline-echo references missing handler `handlers.hybrid_inline_echo`\n\ndeclared at:\n  src/app.lua:141:1\n\nhint:\n  define `pub fn hybrid_inline_echo(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hybrid_inline_params")) @compileError("route GET /__bench/hybrid-inline-params/:id references missing handler `handlers.hybrid_inline_params`\n\ndeclared at:\n  src/app.lua:138:1\n\nhint:\n  define `pub fn hybrid_inline_params(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hybrid_zig")) @compileError("route GET /__bench/hybrid-zig references missing handler `handlers.hybrid_zig`\n\ndeclared at:\n  src/app.lua:20:1\n\nhint:\n  define `pub fn hybrid_zig(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "patch_user")) @compileError("route PATCH /users/:id references missing handler `handlers.patch_user`\n\ndeclared at:\n  src/app.lua:34:1\n\nhint:\n  define `pub fn patch_user(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "plain")) @compileError("route GET /__bench/plain references missing handler `handlers.plain`\n\ndeclared at:\n  src/app.lua:18:1\n\nhint:\n  define `pub fn plain(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "plain_static")) @compileError("route GET /__bench/plain-static references missing handler `handlers.plain_static`\n\ndeclared at:\n  src/app.lua:19:1\n\nhint:\n  define `pub fn plain_static(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "put_user")) @compileError("route PUT /users/:id references missing handler `handlers.put_user`\n\ndeclared at:\n  src/app.lua:30:1\n\nhint:\n  define `pub fn put_user(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "search")) @compileError("route GET /search references missing handler `handlers.search`\n\ndeclared at:\n  src/app.lua:86:1\n\nhint:\n  define `pub fn search(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "slug")) @compileError("route GET /slugs/:slug references missing handler `handlers.slug`\n\ndeclared at:\n  src/app.lua:66:1\n\nhint:\n  define `pub fn slug(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "token")) @compileError("route GET /tokens/:token references missing handler `handlers.token`\n\ndeclared at:\n  src/app.lua:82:1\n\nhint:\n  define `pub fn token(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "uuid")) @compileError("route GET /uuids/:id references missing handler `handlers.uuid`\n\ndeclared at:\n  src/app.lua:70:1\n\nhint:\n  define `pub fn uuid(ctx: anytype) !void` in native/src/handlers.zig");
}

pub const HandlerId = enum {
    bench_counters,
    bench_hybrid_inline,
    bench_hybrid_inline_text_literal,
    bench_meta,
    bench_raw,
    bench_unavailable_global,
    bench_unavailable_leak,
    bench_unavailable_require,
    bench_unavailable_shared,
    bench_unavailable_state,
    bench_unavailable_worker,
    delete_user,
    echo,
    email,
    file,
    get_device,
    get_user,
    health,
    hex,
    hybrid_inline,
    hybrid_inline_echo,
    hybrid_inline_params,
    hybrid_zig,
    patch_user,
    plain,
    plain_static,
    put_user,
    search,
    slug,
    token,
    uuid,
};

pub const ValidatorId = enum { none };

pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {
    return switch (id) {
        .bench_counters => handlers.bench_counters(ctx),
        .bench_hybrid_inline => handlers.bench_hybrid_inline(ctx),
        .bench_hybrid_inline_text_literal => handlers.bench_hybrid_inline_text_literal(ctx),
        .bench_meta => handlers.bench_meta(ctx),
        .bench_raw => handlers.bench_raw(ctx),
        .bench_unavailable_global => handlers.bench_unavailable_global(ctx),
        .bench_unavailable_leak => handlers.bench_unavailable_leak(ctx),
        .bench_unavailable_require => handlers.bench_unavailable_require(ctx),
        .bench_unavailable_shared => handlers.bench_unavailable_shared(ctx),
        .bench_unavailable_state => handlers.bench_unavailable_state(ctx),
        .bench_unavailable_worker => handlers.bench_unavailable_worker(ctx),
        .delete_user => handlers.delete_user(ctx),
        .echo => handlers.echo(ctx),
        .email => handlers.email(ctx),
        .file => handlers.file(ctx),
        .get_device => handlers.get_device(ctx),
        .get_user => handlers.get_user(ctx),
        .health => handlers.health(ctx),
        .hex => handlers.hex(ctx),
        .hybrid_inline => handlers.hybrid_inline(ctx),
        .hybrid_inline_echo => handlers.hybrid_inline_echo(ctx),
        .hybrid_inline_params => handlers.hybrid_inline_params(ctx),
        .hybrid_zig => handlers.hybrid_zig(ctx),
        .patch_user => handlers.patch_user(ctx),
        .plain => handlers.plain(ctx),
        .plain_static => handlers.plain_static(ctx),
        .put_user => handlers.put_user(ctx),
        .search => handlers.search(ctx),
        .slug => handlers.slug(ctx),
        .token => handlers.token(ctx),
        .uuid => handlers.uuid(ctx),
    };
}

pub fn callRoute(comptime route_id: []const u8, raw_ctx: anytype) !void {
    if (comptime std.mem.eql(u8, route_id, "bench_counters")) return handlers.bench_counters(try mt.ctx.bench_counters.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_hybrid_inline")) return handlers.bench_hybrid_inline(try mt.ctx.bench_hybrid_inline.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_hybrid_inline_text_literal")) return handlers.bench_hybrid_inline_text_literal(try mt.ctx.bench_hybrid_inline_text_literal.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_meta")) return handlers.bench_meta(try mt.ctx.bench_meta.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_raw")) return handlers.bench_raw(try mt.ctx.bench_raw.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_global")) return handlers.bench_unavailable_global(try mt.ctx.bench_unavailable_global.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_leak")) return handlers.bench_unavailable_leak(try mt.ctx.bench_unavailable_leak.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_require")) return handlers.bench_unavailable_require(try mt.ctx.bench_unavailable_require.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_shared")) return handlers.bench_unavailable_shared(try mt.ctx.bench_unavailable_shared.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_state")) return handlers.bench_unavailable_state(try mt.ctx.bench_unavailable_state.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "bench_unavailable_worker")) return handlers.bench_unavailable_worker(try mt.ctx.bench_unavailable_worker.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "delete_user")) return handlers.delete_user(try mt.ctx.delete_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "echo")) return handlers.echo(try mt.ctx.echo.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "email")) return handlers.email(try mt.ctx.email.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "file")) return handlers.file(try mt.ctx.file.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "get_device")) return handlers.get_device(try mt.ctx.get_device.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "get_user")) return handlers.get_user(try mt.ctx.get_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "health")) return handlers.health(try mt.ctx.health.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hex")) return handlers.hex(try mt.ctx.hex.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hybrid_inline")) return handlers.hybrid_inline(try mt.ctx.hybrid_inline.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hybrid_inline_echo")) return handlers.hybrid_inline_echo(try mt.ctx.hybrid_inline_echo.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hybrid_inline_params")) return handlers.hybrid_inline_params(try mt.ctx.hybrid_inline_params.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hybrid_zig")) return handlers.hybrid_zig(try mt.ctx.hybrid_zig.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "patch_user")) return handlers.patch_user(try mt.ctx.patch_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "plain")) return handlers.plain(try mt.ctx.plain.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "plain_static")) return handlers.plain_static(try mt.ctx.plain_static.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "put_user")) return handlers.put_user(try mt.ctx.put_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "search")) return handlers.search(try mt.ctx.search.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "slug")) return handlers.slug(try mt.ctx.slug.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "token")) return handlers.token(try mt.ctx.token.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "uuid")) return handlers.uuid(try mt.ctx.uuid.from(raw_ctx));
    @compileError("missing generated route handler binding for route `" ++ route_id ++ "`");
}

pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {
    _ = id;
    return validators.none(value);
}
