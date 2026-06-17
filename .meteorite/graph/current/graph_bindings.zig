const handlers = @import("meteorite_handlers");
const validators = @import("meteorite_validators");

comptime {
    if (!@hasDecl(handlers, "echo")) @compileError("route POST /echo references missing handler `handlers.echo`\n\ndeclared at:\n  src/app.lua:10:1\n\nhint:\n  define `pub fn echo(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "file")) @compileError("route GET /files/:name references missing handler `handlers.file`\n\ndeclared at:\n  src/app.lua:28:1\n\nhint:\n  define `pub fn file(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "get_device")) @compileError("route GET /devices/:device_id references missing handler `handlers.get_device`\n\ndeclared at:\n  src/app.lua:22:1\n\nhint:\n  define `pub fn get_device(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "get_user")) @compileError("route GET /users/:id references missing handler `handlers.get_user`\n\ndeclared at:\n  src/app.lua:6:1\n\nhint:\n  define `pub fn get_user(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "health")) @compileError("route GET /health references missing handler `handlers.health`\n\ndeclared at:\n  src/app.lua:5:1\n\nhint:\n  define `pub fn health(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "hex")) @compileError("route GET /hex/:digest references missing handler `handlers.hex`\n\ndeclared at:\n  src/app.lua:42:1\n\nhint:\n  define `pub fn hex(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "slug")) @compileError("route GET /slugs/:slug references missing handler `handlers.slug`\n\ndeclared at:\n  src/app.lua:34:1\n\nhint:\n  define `pub fn slug(ctx: anytype) !void` in native/src/handlers.zig");
    if (!@hasDecl(handlers, "uuid")) @compileError("route GET /uuids/:id references missing handler `handlers.uuid`\n\ndeclared at:\n  src/app.lua:38:1\n\nhint:\n  define `pub fn uuid(ctx: anytype) !void` in native/src/handlers.zig");
}

pub const HandlerId = enum {
    echo,
    file,
    get_device,
    get_user,
    health,
    hex,
    slug,
    uuid,
};

pub const ValidatorId = enum { none };

pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {
    return switch (id) {
        .echo => handlers.echo(ctx),
        .file => handlers.file(ctx),
        .get_device => handlers.get_device(ctx),
        .get_user => handlers.get_user(ctx),
        .health => handlers.health(ctx),
        .hex => handlers.hex(ctx),
        .slug => handlers.slug(ctx),
        .uuid => handlers.uuid(ctx),
    };
}

pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {
    _ = id;
    return validators.none(value);
}
