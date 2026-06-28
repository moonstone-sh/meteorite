pub fn handle(ctx: anytype) !void {
    try ctx.text(200, "hello from {{name}} (static Zig)");
}
