const std = @import("std");

fn join(b: *std.Build, parts: []const []const u8) []const u8 {
    return std.fs.path.join(b.allocator, parts) catch @panic("OOM");
}

fn projectPath(b: *std.Build, project_root: []const u8, value: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(value)) return value;
    return join(b, &.{ project_root, value });
}

fn cwdPath(path: []const u8) std.Build.LazyPath {
    return .{ .cwd_relative = path };
}

fn cwdFileExists(b: *std.Build, path: []const u8) bool {
    const z = b.allocator.dupeZ(u8, path) catch @panic("OOM");
    defer b.allocator.free(z);
    return std.c.access(z.ptr, 0) == 0;
}

fn readSmallFile(b: *std.Build, path: []const u8) ?[]const u8 {
    const z = b.allocator.dupeZ(u8, path) catch @panic("OOM");
    defer b.allocator.free(z);
    const fd = std.c.open(z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    const buffer = b.allocator.alloc(u8, 1024 * 1024) catch @panic("OOM");
    const read = std.c.read(fd, buffer.ptr, buffer.len);
    if (read < 0) return null;
    return buffer[0..@intCast(read)];
}

fn addZigFileImports(b: *std.Build, graph_module: *std.Build.Module, graph_output: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const manifest_path = join(b, &.{ graph_output, "zig-files.tsv" });
    const manifest = readSmallFile(b, manifest_path) orelse return;
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const name = line[0..tab];
        const path = line[tab + 1 ..];
        if (name.len == 0 or path.len == 0) continue;
        const module = b.createModule(.{
            .root_source_file = cwdPath(path),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("meteorite_graph", graph_module);
        graph_module.addImport(name, module);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static";
    const project_root = b.option([]const u8, "project-root", "Project root, relative to the invoking working directory") orelse ".";
    const default_meteorite_cli = if (cwdFileExists(b, ".moonstone/env/share/lua/5.4/meteorite/cli/main.lua"))
        ".moonstone/env/share/lua/5.4/meteorite/cli/main.lua"
    else if (cwdFileExists(b, ".moonstone/env/libexec/meteorite/files/meteorite/cli/main.lua"))
        ".moonstone/env/libexec/meteorite/files/meteorite/cli/main.lua"
    else if (cwdFileExists(b, ".moonstone/env/libexec/meteorite/src/cli/main.lua"))
        ".moonstone/env/libexec/meteorite/src/cli/main.lua"
    else
        "src/cli/main.lua";
    const meteorite_cli = b.option([]const u8, "meteorite-cli", "Meteorite CLI Lua entrypoint") orelse default_meteorite_cli;
    const graph_input = b.option([]const u8, "graph-input", "Meteorite app entry Lua file") orelse "fixtures/apps/showcase-service/src/main.lua";
    const graph_output = b.option([]const u8, "graph-output", "Generated Meteorite graph directory") orelse ".meteorite/graph/current";
    const lua_root = b.option([]const u8, "lua-root", "Lua runtime root with include/ and lib/") orelse ".moonstone/env/libexec/lua/files";
    const hybrid_profile = b.option([]const u8, "hybrid-profile", "Hybrid profile") orelse "default";
    const backend = b.option([]const u8, "backend", "Meteorite backend: ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http") orelse "fast_http";
    const fast_http_strategy = b.option([]const u8, "fast-http-strategy", "fast_http strategy: threaded_probe or pool") orelse "threaded_probe";
    const fast_http_workers = b.option(u16, "fast-http-workers", "fast_http pool worker count; 0 means CPU count") orelse 0;
    const fast_http_queue = b.option(u16, "fast-http-queue", "fast_http pool queue limit") orelse 1024;
    const unix_socket_path = b.option([]const u8, "unix-socket-path", "unix_socket path") orelse "/tmp/meteorite.sock";
    const unix_socket_mode = b.option([]const u8, "unix-socket-mode", "unix_socket filesystem mode") orelse "0660";
    const unix_socket_unlink_stale = b.option(bool, "unix-socket-unlink-stale", "unlink stale unix_socket path when safe") orelse true;
    const router_dispatch = b.option([]const u8, "router-dispatch", "Router dispatch strategy: method_buckets, static_fast_path, param_matchers, or legacy_scan") orelse "method_buckets";
    if (!std.mem.eql(u8, backend, "ipc_unixsocket") and !std.mem.eql(u8, backend, "ipc_unixsocket_http") and !std.mem.eql(u8, backend, "std_http") and !std.mem.eql(u8, backend, "fast_http")) {
        std.debug.panic("unsupported -Dbackend={s}; expected ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http", .{backend});
    }
    if (!std.mem.eql(u8, fast_http_strategy, "threaded_probe") and !std.mem.eql(u8, fast_http_strategy, "pool")) {
        std.debug.panic("unsupported -Dfast-http-strategy={s}; expected threaded_probe or pool", .{fast_http_strategy});
    }
    if (!std.mem.eql(u8, router_dispatch, "method_buckets") and !std.mem.eql(u8, router_dispatch, "static_fast_path") and !std.mem.eql(u8, router_dispatch, "param_matchers") and !std.mem.eql(u8, router_dispatch, "legacy_scan")) {
        std.debug.panic("unsupported -Drouter-dispatch={s}; expected method_buckets, static_fast_path, param_matchers, or legacy_scan", .{router_dispatch});
    }
    // Meteorite release modes must be compiled with Zig release optimization.
    const optimize: std.builtin.OptimizeMode = if (std.mem.startsWith(u8, mode, "release-"))
        .ReleaseFast
    else
        b.standardOptimizeOption(.{});
    const lua_runtime = !std.mem.eql(u8, mode, "release-static");
    const lua_state_strategy = if (lua_runtime and std.mem.eql(u8, hybrid_profile, "optimized")) "per_thread_cached_refs" else if (lua_runtime) "per_request_state" else "none";
    const is_native_ipc = std.mem.eql(u8, backend, "ipc_unixsocket");
    const is_unix_transport = is_native_ipc or std.mem.eql(u8, backend, "ipc_unixsocket_http");

    const project_graph_input = projectPath(b, project_root, graph_input);
    const project_graph_output = projectPath(b, project_root, graph_output);
    const project_lua_root = projectPath(b, project_root, lua_root);
    const graph_step = b.addSystemCommand(&.{ join(b, &.{ project_root, ".moonstone/env/bin/lua" }), meteorite_cli, "graph", project_graph_input, project_graph_output, mode, backend });

    // Generated build metadata so the server can report exactly what was compiled.
    const build_info_content = std.fmt.allocPrint(b.allocator,
        \\const builtin = @import("builtin");
        \\
        \\pub const meteorite_mode = "{s}";
        \\pub const backend = "{s}";
        \\pub const transport = "{s}";
        \\pub const protocol = "{s}";
        \\pub const fast_http_strategy = "{s}";
        \\pub const fast_http_workers = {};
        \\pub const fast_http_queue = {};
        \\pub const unix_socket_path = "{s}";
        \\pub const unix_socket_mode = "{s}";
        \\pub const unix_socket_unlink_stale = {};
        \\pub const capability_http_headers = {};
        \\pub const capability_cookies = {};
        \\pub const capability_cors = {};
        \\pub const capability_redirects = {};
        \\pub const capability_ipc_metadata = {};
        \\pub const capability_peer_credentials = {};
        \\pub const capability_static_files = {};
        \\pub const lua_runtime = {};
        \\pub const hybrid_profile = "{s}";
        \\pub const lua_state_strategy = "{s}";
        \\pub const router_dispatch = "{s}";
        \\
        \\pub const zig_optimize = @tagName(builtin.mode);
        \\pub const cpu_arch = @tagName(builtin.cpu.arch);
        \\pub const os_tag = @tagName(builtin.os.tag);
        \\pub const abi = @tagName(builtin.abi);
        \\pub const target = cpu_arch ++ "-" ++ os_tag ++ "-" ++ abi;
        \\
    , .{
        mode,
        backend,
        if (is_unix_transport) "unix" else "tcp",
        if (is_native_ipc) "meteorite.ipc.v0" else "http/1.1",
        fast_http_strategy,
        fast_http_workers,
        fast_http_queue,
        unix_socket_path,
        unix_socket_mode,
        unix_socket_unlink_stale,
        !is_native_ipc,
        !is_native_ipc,
        !is_native_ipc,
        !is_native_ipc,
        is_native_ipc,
        false,
        !is_native_ipc,
        lua_runtime,
        hybrid_profile,
        lua_state_strategy,
        router_dispatch,
    }) catch @panic("OOM");
    const write_build_info = b.addWriteFiles();
    const build_info_file = write_build_info.add("build_info.zig", build_info_content);
    graph_step.step.dependOn(&write_build_info.step);

    const pattern_module = b.createModule(.{
        .root_source_file = b.path("zig/pattern.zig"),
        .target = target,
        .optimize = optimize,
    });
    const build_info_module = b.createModule(.{
        .root_source_file = build_info_file,
        .target = target,
        .optimize = optimize,
    });
    const ctx_module = b.createModule(.{
        .root_source_file = cwdPath(join(b, &.{ project_graph_output, "ctx.zig" })),
        .target = target,
        .optimize = optimize,
    });
    const project_handlers = join(b, &.{ project_root, "zig/handlers.zig" });
    const handlers_module = b.createModule(.{
        .root_source_file = if (cwdFileExists(b, project_handlers)) cwdPath(project_handlers) else b.path("zig/empty_handlers.zig"),
        .target = target,
        .optimize = optimize,
    });
    handlers_module.addImport("meteorite_build_info", build_info_module);
    const project_validators = join(b, &.{ project_root, "zig/validators.zig" });
    const validators_module = b.createModule(.{
        .root_source_file = if (cwdFileExists(b, project_validators)) cwdPath(project_validators) else b.path("zig/empty_validators.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protocol_module = b.createModule(.{
        .root_source_file = b.path("zig/backends/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx_module.addImport("meteorite_protocol", protocol_module);
    const http_date_module = b.createModule(.{
        .root_source_file = b.path("zig/server/http_date.zig"),
        .target = target,
        .optimize = optimize,
    });
    const signals_module = b.createModule(.{
        .root_source_file = b.path("zig/server/signals.zig"),
        .target = target,
        .optimize = optimize,
    });
    const c_imports_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/c_imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_stats_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_stats.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_bench_stats_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_bench_stats.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_vtable_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_vtable.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_vtable_module.addImport("meteorite_protocol", protocol_module);
    const bridge_json_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_json.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_json_module.addImport("c_imports", c_imports_module);
    const bridge_http_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_http.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_http_module.addImport("bridge/lua_vtable", bridge_vtable_module);
    bridge_http_module.addImport("bridge/lua_json", bridge_json_module);
    const meteorite_module = b.createModule(.{
        .root_source_file = b.path("zig/meteorite.zig"),
        .target = target,
        .optimize = optimize,
    });
    meteorite_module.addImport("build_options", build_info_module);
    meteorite_module.addImport("meteorite_protocol", protocol_module);
    meteorite_module.addImport("server/signals", signals_module);
    meteorite_module.addImport("server/http_date", http_date_module);
    meteorite_module.addImport("bridge/lua_bench_stats", bridge_bench_stats_module);

    const server_validators_module = b.createModule(.{
        .root_source_file = b.path("zig/server/validators.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_static_module = b.createModule(.{
        .root_source_file = b.path("zig/server/static_files.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_limits_module = b.createModule(.{
        .root_source_file = b.path("zig/server/request_limits.zig"),
        .target = target,
        .optimize = optimize,
    });
    meteorite_module.addImport("server/validators", server_validators_module);
    meteorite_module.addImport("server/static_files", server_static_module);
    meteorite_module.addImport("server/request_limits", server_limits_module);
    const bridge_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (lua_runtime) {
        bridge_module.addIncludePath(cwdPath(join(b, &.{ project_lua_root, "include" })));
        bridge_module.addLibraryPath(cwdPath(join(b, &.{ project_lua_root, "lib" })));
        bridge_module.linkSystemLibrary("lua", .{});
        bridge_module.linkSystemLibrary("m", .{});
    }

    const graph_module = b.createModule(.{
        .root_source_file = cwdPath(join(b, &.{ project_graph_output, "graph.zig" })),
        .target = target,
        .optimize = optimize,
    });
    graph_module.addImport("meteorite_ctx", ctx_module);

    const bridge_bindings_module = b.createModule(.{
        .root_source_file = b.path("zig/bridge/lua_bindings.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_bindings_module.addImport("meteorite_graph", graph_module);
    bridge_bindings_module.addImport("meteorite_protocol", protocol_module);
    bridge_bindings_module.addImport("c_imports", c_imports_module);
    bridge_bindings_module.addImport("bridge/lua_stats", bridge_stats_module);
    bridge_bindings_module.addImport("bridge/lua_vtable", bridge_vtable_module);
    bridge_bindings_module.addImport("bridge/lua_json", bridge_json_module);
    bridge_bindings_module.addImport("bridge/lua_http", bridge_http_module);
    graph_module.addImport("meteorite_pattern", pattern_module);
    graph_module.addImport("meteorite_handlers", handlers_module);
    graph_module.addImport("meteorite_validators", validators_module);
    addZigFileImports(b, graph_module, project_graph_output, target, optimize);
    handlers_module.addImport("meteorite_graph", ctx_module);
    handlers_module.addImport("bridge/lua_bench_stats", bridge_bench_stats_module);
    bridge_module.addImport("meteorite_graph", graph_module);
    bridge_module.addImport("meteorite_protocol", protocol_module);
    bridge_module.addImport("server/http_date", http_date_module);
    bridge_module.addImport("bridge/lua_stats", bridge_stats_module);
    bridge_module.addImport("bridge/lua_bench_stats", bridge_bench_stats_module);
    bridge_module.addImport("bridge/lua_vtable", bridge_vtable_module);
    bridge_module.addImport("bridge/lua_json", bridge_json_module);
    bridge_module.addImport("bridge/lua_http", bridge_http_module);
    bridge_module.addImport("bridge/lua_bindings", bridge_bindings_module);
    bridge_module.addImport("bridge/c_imports", c_imports_module);

    const listen_config_module = b.createModule(.{
        .root_source_file = cwdPath(join(b, &.{ project_graph_output, "listen_config.zig" })),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "meteorite_graph", .module = graph_module },
                .{ .name = "meteorite.zig", .module = meteorite_module },
                .{ .name = "bridge.zig", .module = bridge_module },
                .{ .name = "build_options", .module = build_info_module },
                .{ .name = "meteorite_pattern", .module = pattern_module },
                .{ .name = "listen_config", .module = listen_config_module },
            },
        }),
    });
    exe.rdynamic = lua_runtime;
    if (lua_runtime) exe.link_gc_sections = false;
    exe.step.dependOn(&graph_step.step);

    const install_server = b.addSystemCommand(&.{ "sh", "-c", "out=\"${2:-dist/server}\"; dir=$(dirname \"$out\"); mkdir -p \"$dir\"; rm -f \"$out\"; cp \"$1\" \"$out\"; if [ -d \"$3/static\" ]; then rm -rf \"$dir/static\"; cp -R \"$3/static\" \"$dir/static\"; fi", "sh" });
    install_server.addFileArg(exe.getEmittedBin());
    if (b.args) |args| {
        if (args.len > 0) install_server.addArg(args[0]) else install_server.addArg("dist/server");
    } else {
        install_server.addArg("dist/server");
    }
    install_server.addArg(graph_output);
    install_server.step.dependOn(&exe.step);

    const install_step = b.step("install-server", "Build the Meteorite HTTP server into dist/server");
    install_step.dependOn(&install_server.step);

    const default_step = b.getInstallStep();
    default_step.dependOn(install_step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(&graph_step.step);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Build and run the Meteorite HTTP server");
    run_step.dependOn(&run.step);
}
