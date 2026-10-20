const std = @import("std");
const Install = @This();
step: std.Build.Step,
binary: std.Build.LazyPath,
output: []const u8,
static_root: []const u8,

pub fn create(b: *std.Build, binary: std.Build.LazyPath, output: []const u8, static_root: []const u8) *Install {
    const self = b.allocator.create(Install) catch @panic("OOM");
    self.* = .{
        .step = std.Build.Step.init(.{ .id = .custom, .name = "install Meteorite service", .owner = b, .makeFn = make }),
        .binary = binary.dupe(b),
        .output = b.dupe(output),
        .static_root = b.dupe(static_root),
    };
    binary.addStepDependencies(&self.step);
    return self;
}
fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const self: *Install = @fieldParentPtr("step", step);
    const b = step.owner;
    const io = b.graph.io;
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(self.output)) |parent| {
        var existing = cwd.openDir(io, parent, .{}) catch |err| switch (err) {
            error.FileNotFound => blk: {
                try cwd.createDirPath(io, parent);
                break :blk try cwd.openDir(io, parent, .{});
            },
            else => return err,
        };
        existing.close(io);
    }
    // std.Build owns copying and executable permissions on every host.
    _ = try step.installFile(self.binary, self.output);
    var source = cwd.openDir(io, self.static_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer source.close(io);
    const destination = b.pathJoin(&.{ std.fs.path.dirname(self.output) orelse ".", "static" });
    try cwd.deleteTree(io, destination);
    try cwd.createDirPath(io, destination);
    var walker = try source.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const output = b.pathJoin(&.{ destination, entry.path });
        switch (entry.kind) {
            .directory => try cwd.createDirPath(io, output),
            .file => {
                if (std.fs.path.dirname(output)) |parent| try cwd.createDirPath(io, parent);
                try source.copyFile(entry.path, cwd, output, io, .{});
            },
            else => return step.fail("static assets must be regular files: {s}", .{entry.path}),
        }
    }
}
