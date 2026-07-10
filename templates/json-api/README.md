# {{name}}

A Meteorite JSON API starter with typed params, query validation, JSON body validation, response schema declarations, and local invoke checks.

## Try it

```bash
moon sync
meteorite invoke --json src/main.lua GET /api/todos/1
meteorite invoke --json -H "Content-Type: application/json" --body '{"title":"learn Meteorite"}' src/main.lua POST /api/todos
moon run dev
```

This is a Lua-first hybrid starter. Move hot paths to Zig handlers when profiling shows they matter.
