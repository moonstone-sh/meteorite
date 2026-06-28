pub fn handle(ctx: anytype) !void {
    try ctx.json(200, "{\"ok\":true,\"runtime\":\"zig\"}");
}
