const std = @import("std");
const meteorite = @import("meteorite.zig");
const bridge = @import("bridge.zig");
const graph = @import("meteorite_graph");
const build_info = @import("build_options");
const listen_config = @import("listen_config");

const ListenConfig = meteorite.ListenConfig;

fn enterReleaseRoot(init: std.process.Init) !void {
    const exe_dir = try std.process.executableDirPathAlloc(init.io, init.gpa);
    defer init.gpa.free(exe_dir);

    if (std.mem.eql(u8, std.fs.path.basename(exe_dir), "bin")) {
        const release_root = std.fs.path.dirname(exe_dir) orelse return;
        try std.Io.Threaded.chdir(release_root);
        return;
    }

    const manifest_path = try std.fs.path.join(init.gpa, &.{ exe_dir, "meteorite-release.json" });
    defer init.gpa.free(manifest_path);
    std.Io.Dir.cwd().access(init.io, manifest_path, .{}) catch return;
    try std.Io.Threaded.chdir(exe_dir);
}

const requires_lua = blk: {
    var req = false;
    for (graph.routes) |r| {
        if (r.runtime.requires_lua) req = true;
        switch (r.handler) {
            .inline_lua, .lua_file => req = true,
            else => {},
        }
        for (r.pipeline) |stage| {
            if (stage.strat == .inline_lua or stage.strat == .lua) req = true;
        }
    }
    for (graph.plugins) |p| {
        switch (p.handler) {
            .inline_lua, .lua_file => req = true,
            else => {},
        }
    }
    break :blk req;
};

const final_requires_lua = requires_lua or build_info.lua_runtime;

const LuaRuntime = if (!final_requires_lua)
    bridge.LuaRuntimeUnavailable
else if (std.mem.eql(u8, build_info.hybrid_profile, "optimized"))
    bridge.CachedHybridRuntime
else
    bridge.HybridLuaRuntime;

const SelectedBackend = if (std.mem.eql(u8, build_info.backend, "fast_http"))
    meteorite.backends.fast_http
else if (std.mem.eql(u8, build_info.backend, "std_http"))
    meteorite.backends.std_http
else if (std.mem.eql(u8, build_info.backend, "ipc_unixsocket"))
    meteorite.backends.unix_socket
else if (std.mem.eql(u8, build_info.backend, "ipc_unixsocket_http"))
    meteorite.backends.unix_socket_http
else
    @compileError("unsupported Meteorite backend; expected ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http");

const App = meteorite.compile(.{
    .graph = graph,
    .backend = SelectedBackend,
    .lua_runtime = LuaRuntime,
    .hybrid_profile = build_info.hybrid_profile,
});

pub fn main(init: std.process.Init) !void {
    try enterReleaseRoot(init);

    const listen_zon = listen_config.listen_zon;
    const parsed = try std.zon.parse.fromSliceAlloc(ListenConfig, init.gpa, listen_zon, null, .{});
    defer std.zon.parse.free(init.gpa, parsed);
    try App.serve(init.io, parsed);
}
