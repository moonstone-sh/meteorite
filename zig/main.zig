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

const LuaRuntime = if (std.mem.eql(u8, build_info.hybrid_profile, "optimized"))
    bridge.CachedHybridRuntime
else
    bridge.HybridLuaRuntime;

const SelectedBackend = if (std.mem.eql(u8, build_info.backend, "fast_http"))
    meteorite.backends.fast_http
else
    meteorite.backends.std_http;

const App = meteorite.compile(.{
    .graph = graph,
    .backend = SelectedBackend,
    .lua_runtime = LuaRuntime,
    .hybrid_profile = build_info.hybrid_profile,
});

pub fn main(init: std.process.Init) !void {
    try enterReleaseRoot(init);

    const listen_zon = listen_config.listen_zon;
    const listen_zon_nt = try std.mem.concatWithSentinel(init.gpa, u8, &.{listen_zon}, 0);
    defer init.gpa.free(listen_zon_nt);
    const parsed = try std.zon.parse.fromSliceAlloc(ListenConfig, init.gpa, listen_zon_nt, null, .{});
    defer std.zon.parse.free(init.gpa, parsed);
    try App.serve(init.io, parsed);
}
