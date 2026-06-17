const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mode = b.option([]const u8, "mode", "Meteorite build mode") orelse "release-static";

    const graph_step = b.addSystemCommand(&.{ "luajit", "../../src/meteorite/cli.lua", "graph", "src/main.lua", ".meteorite/graph/current", mode });

    const graph_module = b.createModule(.{
        .root_source_file = b.path(".meteorite/graph/current/graph.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    graph_module.addImport("meteorite_handlers", handlers_module);
    graph_module.addImport("meteorite_validators", validators_module);

    const meteorite_module = b.createModule(.{
        .root_source_file = b.path("../../native/src/meteorite.zig"),
        .target = target,
        .optimize = optimize,
    });
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
