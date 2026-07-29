const std = @import("std");
const meteorite = @import("zig/build_api.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = meteorite.addService(b, .{
        .meteorite_root = b.pathFromRoot("."),
        .target = target,
        .optimize = optimize,
        .mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static",
        .project_root = b.option([]const u8, "project-root", "Project root, relative to the invoking working directory") orelse ".",
        .meteorite_cli = b.option([]const u8, "meteorite-cli", "Meteorite CLI Lua entrypoint"),
        .graph_input = b.option([]const u8, "graph-input", "Meteorite app entry Lua file") orelse "src/main.lua",
        .graph_output = b.option([]const u8, "graph-output", "Generated Meteorite graph directory") orelse ".meteorite/graph/current",
        .lua_root = b.option([]const u8, "lua-root", "Lua runtime root with include/ and lib/") orelse ".moonstone/env/libexec/lua/files",
        .hybrid_profile = b.option([]const u8, "hybrid-profile", "Hybrid profile") orelse "default",
        .backend = b.option([]const u8, "backend", "Meteorite backend: ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http") orelse "fast_http",
        .fast_http_strategy = b.option([]const u8, "fast-http-strategy", "fast_http strategy: threaded_probe or pool") orelse "threaded_probe",
        .fast_http_workers = b.option(u16, "fast-http-workers", "fast_http pool worker count; 0 means CPU count") orelse 0,
        .fast_http_queue = b.option(u16, "fast-http-queue", "fast_http pool queue limit") orelse 1024,
        .benchmark_instrumentation = b.option(bool, "benchmark-instrumentation", "Enable fixture benchmark counters and metadata") orelse false,
        .unix_socket_path = b.option([]const u8, "unix-socket-path", "unix_socket path") orelse "/tmp/meteorite.sock",
        .unix_socket_mode = b.option([]const u8, "unix-socket-mode", "unix_socket filesystem mode") orelse "0660",
        .unix_socket_unlink_stale = b.option(bool, "unix-socket-unlink-stale", "unlink stale unix_socket path when safe") orelse true,
        .require_peer_credentials = b.option(bool, "require-peer-credentials", "require Unix peer credentials when backend supports them") orelse false,
        .peer_allow_uid = b.option([]const u8, "peer-allow-uid", "allowed peer uid for Unix peer credential policy") orelse "",
        .peer_allow_gid = b.option([]const u8, "peer-allow-gid", "allowed peer gid for Unix peer credential policy") orelse "",
        .router_dispatch = b.option([]const u8, "router-dispatch", "Router dispatch strategy: method_buckets, static_fast_path, param_matchers, or legacy_scan") orelse "method_buckets",
    });
}
