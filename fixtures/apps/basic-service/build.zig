const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static";
    const graph_input = b.option([]const u8, "graph-input", "Meteorite graph input") orelse "src/main.lua";
    const graph_output = b.option([]const u8, "graph-output", "Meteorite graph output") orelse ".meteorite/graph/current";
    const backend = b.option([]const u8, "backend", "Meteorite HTTP backend") orelse "std_http";
    const fast_http_strategy = "single";
    const fast_http_workers: u32 = 0;
    const fast_http_queue: u32 = 1024;
    const unix_socket_path = "";
    const unix_socket_mode = "0600";
    const unix_socket_unlink_stale = true;
    const require_peer_credentials = false;
    const peer_allow_uid = "";
    const peer_allow_gid = "";
    const router_dispatch = b.option([]const u8, "router-dispatch", "Router dispatch strategy: method_buckets, static_fast_path, param_matchers, or legacy_scan") orelse "method_buckets";
    const hybrid_profile = b.option([]const u8, "hybrid-profile", "Meteorite hybrid runtime profile") orelse "default";
    const lua_runtime = !std.mem.eql(u8, mode, "release-static");
    const lua_state_strategy = if (lua_runtime and std.mem.eql(u8, hybrid_profile, "optimized")) "per_thread_cached_refs" else if (lua_runtime) "per_request_state" else "none";

    const graph_step = b.addSystemCommand(&.{ "luajit", "../../../src/cli/main.lua", "graph", graph_input, graph_output, mode, backend });

    const build_info_content = std.fmt.allocPrint(b.allocator,
        \\const builtin = @import("builtin");
        \\pub const meteorite_mode = "{s}";
        \\pub const backend = "{s}";
        \\pub const transport = "tcp";
        \\pub const protocol = "http/1.1";
        \\pub const fast_http_strategy = "{s}";
        \\pub const fast_http_workers = {};
        \\pub const fast_http_queue = {};
        \\pub const unix_socket_path = "{s}";
        \\pub const unix_socket_mode = "{s}";
        \\pub const unix_socket_unlink_stale = {};
        \\pub const require_peer_credentials = {};
        \\pub const peer_allow_uid = "{s}";
        \\pub const peer_allow_gid = "{s}";
        \\pub const capability_http_headers = true;
        \\pub const capability_cookies = true;
        \\pub const capability_cors = true;
        \\pub const capability_redirects = true;
        \\pub const capability_ipc_metadata = false;
        \\pub const capability_peer_credentials = false;
        \\pub const capability_static_files = true;
        \\pub const lua_runtime = {};
        \\pub const hybrid_profile = "{s}";
        \\pub const lua_state_strategy = "{s}";
        \\pub const router_dispatch = "{s}";
        \\pub const zig_optimize = @tagName(builtin.mode);
        \\pub const cpu_arch = @tagName(builtin.cpu.arch);
        \\pub const os_tag = @tagName(builtin.os.tag);
        \\pub const abi = @tagName(builtin.abi);
        \\pub const target = cpu_arch ++ "-" ++ os_tag ++ "-" ++ abi;
        \\
    , .{ mode, backend, fast_http_strategy, fast_http_workers, fast_http_queue, unix_socket_path, unix_socket_mode, unix_socket_unlink_stale, require_peer_credentials, peer_allow_uid, peer_allow_gid, lua_runtime, hybrid_profile, lua_state_strategy, router_dispatch }) catch @panic("OOM");
    const write_build_info = b.addWriteFiles();
    const build_info_file = write_build_info.add(".meteorite/graph/current/build_info.zig", build_info_content);
    const build_info_module = b.createModule(.{
        .root_source_file = build_info_file,
        .target = target,
        .optimize = optimize,
    });
    graph_step.step.dependOn(&write_build_info.step);

    const graph_module = b.createModule(.{
        .root_source_file = b.path(".meteorite/graph/current/graph.zig"),
        .target = target,
        .optimize = optimize,
    });
    graph_module.addImport("meteorite_pattern", b.createModule(.{
        .root_source_file = b.path("../../../zig/pattern.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const ctx_module = b.createModule(.{
        .root_source_file = b.path(".meteorite/graph/current/ctx.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protocol_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/backends/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx_module.addImport("meteorite_protocol", protocol_module);
    const http_date_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/http_date.zig"),
        .target = target,
        .optimize = optimize,
    });
    const signals_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/signals.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cached_time_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/cached_time.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_bench_stats_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/bridge/lua_bench_stats.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_validators_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/validators.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_static_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/static_files.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_limits_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/server/request_limits.zig"),
        .target = target,
        .optimize = optimize,
    });
    graph_module.addImport("meteorite_ctx", ctx_module);
    const handlers_module = b.createModule(.{
        .root_source_file = b.path("zig/handlers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const validators_module = b.createModule(.{
        .root_source_file = b.path("zig/validators.zig"),
        .target = target,
        .optimize = optimize,
    });
    handlers_module.addImport("meteorite_graph", ctx_module);
    handlers_module.addImport("meteorite_build_info", build_info_module);
    graph_module.addImport("meteorite_handlers", handlers_module);
    graph_module.addImport("meteorite_validators", validators_module);

    const meteorite_module = b.createModule(.{
        .root_source_file = b.path("../../../zig/meteorite.zig"),
        .target = target,
        .optimize = optimize,
    });
    meteorite_module.addImport("build_options", build_info_module);
    meteorite_module.addImport("meteorite_protocol", protocol_module);
    meteorite_module.addImport("server/cached_time.zig", cached_time_module);
    meteorite_module.addImport("server/signals", signals_module);
    meteorite_module.addImport("server/http_date", http_date_module);
    meteorite_module.addImport("bridge/lua_bench_stats", bridge_bench_stats_module);
    meteorite_module.addImport("server/validators", server_validators_module);
    meteorite_module.addImport("server/static_files", server_static_module);
    meteorite_module.addImport("server/request_limits", server_limits_module);
    graph_module.addImport("meteorite.zig", meteorite_module);

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "meteorite_graph", .module = graph_module },
                .{ .name = "meteorite.zig", .module = meteorite_module },
                .{ .name = "build_options", .module = build_info_module },
            },
        }),
    });
    exe.step.dependOn(&graph_step.step);

    const install_server = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p dist && cp \"$1\" \"${2:-dist/server}\"", "sh" });
    install_server.addFileArg(exe.getEmittedBin());
    if (b.args) |args| {
        if (args.len > 0) install_server.addArg(args[0]) else install_server.addArg("dist/server");
    } else {
        install_server.addArg("dist/server");
    }
    install_server.step.dependOn(&exe.step);

    const install_step = b.step("install-server", "Build the Meteorite fixture server into dist/server");
    install_step.dependOn(&install_server.step);

    const default_step = b.getInstallStep();
    default_step.dependOn(install_step);
}
