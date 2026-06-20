const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static";

    const graph_step = b.addSystemCommand(&.{ ".moonstone/env/bin/lua", "src/meteorite/cli.lua", "graph", "src/main.lua", ".meteorite/graph/current", mode });

    const graph_module = b.createModule(.{
        .root_source_file = b.path(".meteorite/graph/current/graph.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ctx_module = b.createModule(.{
        .root_source_file = b.path(".meteorite/graph/current/ctx.zig"),
        .target = target,
        .optimize = optimize,
    });
    graph_module.addImport("meteorite_ctx", ctx_module);
    const handlers_module = b.createModule(.{
        .root_source_file = b.path("native/src/handlers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const validators_module = b.createModule(.{
        .root_source_file = b.path("native/src/validators.zig"),
        .target = target,
        .optimize = optimize,
    });
    const meteorite_module = b.createModule(.{
        .root_source_file = b.path("native/src/meteorite.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_module = b.createModule(.{
        .root_source_file = b.path("native/src/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_module.addIncludePath(b.path(".moonstone/env/libexec/lua/files/include"));
    bridge_module.addLibraryPath(b.path(".moonstone/env/libexec/lua/files/lib"));
    bridge_module.linkSystemLibrary("lua", .{});
    bridge_module.linkSystemLibrary("m", .{});
    bridge_module.addImport("meteorite_graph", graph_module);

    handlers_module.addImport("meteorite_graph", ctx_module);
    graph_module.addImport("meteorite_handlers", handlers_module);
    graph_module.addImport("meteorite_validators", validators_module);
    graph_module.addImport("meteorite.zig", meteorite_module);

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "meteorite_graph", .module = graph_module },
                .{ .name = "meteorite.zig", .module = meteorite_module },
                .{ .name = "bridge.zig", .module = bridge_module },
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
