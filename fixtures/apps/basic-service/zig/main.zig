const std = @import("std");
const meteorite = @import("meteorite.zig");
const graph = @import("meteorite_graph");

const App = meteorite.compile(.{
    .graph = graph,
    .backend = meteorite.backends.std_http,
});

pub fn main(init: std.process.Init) !void {
    try App.run(init.io);
}
