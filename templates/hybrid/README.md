# {{name}}

A hybrid Meteorite service with both inline Lua handlers and transportable Zig
handlers.

## Commands

```bash
moon sync
moon run dev       # live reloads inline Lua edits where possible
moon run build     # local dev binary at dist/server
moon run run       # runs dist/server
moon run release   # same-host hybrid deploy directory at dist/release
```

Deploy with `dist/release/bin/server`. Cross-target hybrid release is not fully unlocked until Moonstone provides upstream Lua runtime/package source provenance.
