pub fn health(ctx: anytype) !void {
    try ctx.text(200, "ok");
}

pub fn get_user(ctx: anytype) !void {
    const id = ctx.param("id") orelse "missing";
    try ctx.bytes(200, "application/json", id);
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
