# {{name}}

A minimal Meteorite service.

## Commands

```bash
moon sync
moon run generate-graph
moon run dev       # graph-aware live reload
moon run build     # local dev binary at dist/server
moon run run       # runs dist/server
moon run release   # deploy directory at dist/release
meteorite help
meteorite doctor
```

The default project is Lua-first hybrid mode: no local Zig files are required.
Meteorite owns the hidden build driver, graph generation, and live reload loop.

## Add Zig later

Use a transportable Zig handler anywhere in your project:

```lua
app:get("/fast", m.zig("zig/handlers/fast.zig"))
```

Then create `zig/handlers/fast.zig`:

```zig
pub fn handle(ctx: anytype) !void {
    try ctx.text(200, "fast path");
}
```

For central handler scaffolding, initialize with:

```bash
meteorite init . --with-zig
```

## Release Exports

Production exports are owned by the Meteorite Ballad plugin on a per-app basis. `moon run release` runs `partiture.lua` and writes one deployable directory: `dist/release/`.

```lua
local ballad = require("ballad")
local moonstone = require("ballad.plugins.moonstone")

return ballad.partiture(function(p)
  local meteorite = p:use("meteorite.ballad")
  local project = moonstone.project_prepare({ root = ".", roles = { "runtime" } })
  local release = meteorite.release({
    project = project,
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    mode = "hybrid",
    bin = "bin/server",
    backend = "std_http",
  })
  p.sink.directory(release, { out = "dist/release" })
end)
```

Deploy with:

```bash
dist/release/bin/server
```

`dist/server` is only the local development binary from `moon run build`.
