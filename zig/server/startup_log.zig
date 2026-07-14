const std = @import("std");

pub fn StartupLog(comptime graph: anytype, comptime backend: anytype, comptime build_info: anytype) type {
    return struct {
        pub fn print(config: anytype, graph_requires_lua: bool, inline_lua_handlers: usize, zig_handlers: usize) void {
            if (comptime std.mem.eql(u8, build_info.transport, "unix")) {
                std.debug.print("Meteorite build\n  mode: {s}\n  backend: {s}\n  transport: {s}\n  protocol: {s}\n  Lua runtime: {s}\n  Lua state: single_locked\n  workers: auto\n  inline Lua handlers: {d}\n  Zig handlers: {d}\n  routes: {d}\n  artifact: dist/server\nListening: unix://{s}\n", .{
                    if (graph_requires_lua) "hybrid" else "static",
                    build_info.backend,
                    build_info.transport,
                    build_info.protocol,
                    if (graph_requires_lua) "included" else "removed",
                    inline_lua_handlers,
                    zig_handlers,
                    graph.routes.len,
                    build_info.unix_socket_path,
                });
            } else std.debug.print("Meteorite build\n  mode: {s}\n  backend: {s}\n  Lua runtime: {s}\n  Lua state: single_locked\n  workers: auto\n  inline Lua handlers: {d}\n  Zig handlers: {d}\n  routes: {d}\n  artifact: dist/server\nListening: http://{s}:{d}\n", .{
                if (graph_requires_lua) "hybrid" else "static",
                backend.name,
                if (graph_requires_lua) "included" else "removed",
                inline_lua_handlers,
                zig_handlers,
                graph.routes.len,
                config.host,
                config.port,
            });
        }
    };
}
