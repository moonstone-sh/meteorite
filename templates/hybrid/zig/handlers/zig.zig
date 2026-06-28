pub fn handle(ctx: anytype) !void {
    try ctx.text(200, "hello from Zig inside a hybrid Meteorite app");
}
