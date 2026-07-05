const std = @import("std");
const handlers = @import("meteorite_handlers");
const validators = @import("meteorite_validators");
const mt = @import("meteorite_ctx");

comptime {
    if (!@hasDecl(handlers, "delete_user")) @compileError("route DELETE /users/:id references missing handler `handlers.delete_user`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:30:1\n\nhint:\n  define `pub fn delete_user(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "echo")) @compileError("route POST /echo references missing handler `handlers.echo`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:34:1\n\nhint:\n  define `pub fn echo(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "email")) @compileError("route GET /emails/:email references missing handler `handlers.email`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:68:1\n\nhint:\n  define `pub fn email(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "file")) @compileError("route GET /files/:name references missing handler `handlers.file`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:50:1\n\nhint:\n  define `pub fn file(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "get_device")) @compileError("route GET /devices/:device_id references missing handler `handlers.get_device`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:44:1\n\nhint:\n  define `pub fn get_device(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "get_user")) @compileError("route GET /users/:id references missing handler `handlers.get_user`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:18:1\n\nhint:\n  define `pub fn get_user(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "health")) @compileError("route GET /health references missing handler `handlers.health`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:17:1\n\nhint:\n  define `pub fn health(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "hex")) @compileError("route GET /hex/:digest references missing handler `handlers.hex`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:64:1\n\nhint:\n  define `pub fn hex(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "hybrid_inline")) @compileError("route GET /hybrid-inline references missing handler `handlers.hybrid_inline`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:89:1\n\nhint:\n  define `pub fn hybrid_inline(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "patch_user")) @compileError("route PATCH /users/:id references missing handler `handlers.patch_user`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:26:1\n\nhint:\n  define `pub fn patch_user(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "put_user")) @compileError("route PUT /users/:id references missing handler `handlers.put_user`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:22:1\n\nhint:\n  define `pub fn put_user(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "search")) @compileError("route GET /search references missing handler `handlers.search`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:76:1\n\nhint:\n  define `pub fn search(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "slug")) @compileError("route GET /slugs/:slug references missing handler `handlers.slug`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:56:1\n\nhint:\n  define `pub fn slug(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "token")) @compileError("route GET /tokens/:token references missing handler `handlers.token`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:72:1\n\nhint:\n  define `pub fn token(ctx: anytype) !void` in zig/handlers.zig");
    if (!@hasDecl(handlers, "uuid")) @compileError("route GET /uuids/:id references missing handler `handlers.uuid`\n\ndeclared at:\n  fixtures/apps/showcase-service/src/app.lua:60:1\n\nhint:\n  define `pub fn uuid(ctx: anytype) !void` in zig/handlers.zig");
}


pub const HandlerId = enum {
    delete_user,
    echo,
    email,
    file,
    get_device,
    get_user,
    health,
    hex,
    hybrid_inline,
    patch_user,
    put_user,
    search,
    slug,
    token,
    uuid,
};

pub const ValidatorId = enum { none };

pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {
    return switch (id) {
        .delete_user => handlers.delete_user(ctx),
        .echo => handlers.echo(ctx),
        .email => handlers.email(ctx),
        .file => handlers.file(ctx),
        .get_device => handlers.get_device(ctx),
        .get_user => handlers.get_user(ctx),
        .health => handlers.health(ctx),
        .hex => handlers.hex(ctx),
        .hybrid_inline => handlers.hybrid_inline(ctx),
        .patch_user => handlers.patch_user(ctx),
        .put_user => handlers.put_user(ctx),
        .search => handlers.search(ctx),
        .slug => handlers.slug(ctx),
        .token => handlers.token(ctx),
        .uuid => handlers.uuid(ctx),
    };
}

pub fn callRoute(comptime route_id: []const u8, raw_ctx: anytype) !void {
    if (comptime std.mem.eql(u8, route_id, "delete_user")) return handlers.delete_user(try mt.ctx.delete_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "echo")) return handlers.echo(try mt.ctx.echo.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "email")) return handlers.email(try mt.ctx.email.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "file")) return handlers.file(try mt.ctx.file.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "get_device")) return handlers.get_device(try mt.ctx.get_device.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "get_user")) return handlers.get_user(try mt.ctx.get_user.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "health")) return handlers.health(try mt.ctx.health.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hex")) return handlers.hex(try mt.ctx.hex.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "hybrid_inline")) return handlers.hybrid_inline(try mt.ctx.hybrid_inline.from(raw_ctx));
    if (comptime std.mem.eql(u8, route_id, "patch_user")) return handlers.patch_user(try mt.ctx.patch_user.from(raw_ctx));
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
