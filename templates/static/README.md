# {{name}}

A static Meteorite service: Lua declares the graph at build time, but request
handling is pure Zig and `moon run build` emits a server without the Lua runtime.

## Commands

```bash
moon sync
moon run generate-graph
moon run build     # local dev binary at dist/server
moon run run       # runs dist/server
moon run release   # static deploy directory at dist/release
```

Deploy with `dist/release/bin/server`. Static releases contain the server, manifest, and frozen static assets without a runtime `.moonstone/env` dependency.
