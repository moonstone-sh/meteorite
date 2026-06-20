# Meteorite

Meteorite is a Moonstone-native service compiler prototype.

```text
Lua declares.
Ballad materializes.
Zig compiles.
Meteorite lands.
```

## Package Shape

- `src/meteorite/` contains the Meteorite Lua DSL, normalizer, ZON emitter, and Ballad plugin surface.
- `src/app.lua` is the local acceptance app that exercises the DSL.
- `src/main.lua` returns the local app for graph materialization.
- `native/src/` contains handwritten Zig runtime behavior, handlers, validators, and the `std.http` backend implementation.
- `.meteorite/graph/current/` contains generated graph data and Zig bindings.
- `partiture.lua` exports Meteorite itself as a Moonstone source package for the registry.

## Local v0.1 Flow

```bash
moon run graph
moon run build
./dist/server
```

For development, run the partition-aware supervisor:

```bash
moon run dev
```

`moon run dev` regenerates the graph on source changes, rebuilds/restarts for route/native/build changes, and reloads inline Lua handler chunks in-process when only `lua_chunk` partitions changed. The dev loop uses `hybrid_dev`, `std_http`, and the optimized cached Lua runtime so Lua handler edits update without a Zig rebuild or server restart.

Generated route data is split into `.meteorite/graph/current/routes/<route_id>.zig` modules and DFA tables are split into `.meteorite/graph/current/patterns/<pattern_id>.zig` modules. Generated files are written only when content changes, so route-shape or pattern edits touch the affected module instead of rewriting every generated declaration.

Mounted route scopes are represented in the graph now. `app:mount("/orgs/:org_id", { params = { org_id = m.u64() } }, function(api) ... end)` prefixes child routes, inherits declared mount params/query/capabilities, and records a deterministic scope chain. Scope metadata includes `id`, `parent`, `path_prefix`, inherited plugin refs, and context refs, so later scoped plugins and route execution contexts can be wired without changing the route IR shape.

Nested mounts keep the deepest route scope while inheriting parent declarations:

```lua
app:mount("/orgs/:org_id", {
  id = "org",
  params = { org_id = m.u64() },
  plugins = { "auth" },
  context = { tenant = "org" },
}, function(org)
  org:mount("/projects/:project_id", {
    id = "project",
    params = { project_id = m.uuid() },
    plugins = { "quota" },
    context = { tenant = "project" },
  }, function(project)
    project:get("/users/:id", { params = { id = m.u64() } }, handler)
  end)
end)
```

The generated route becomes `/orgs/:org_id/projects/:project_id/users/:id`, carries all three param validators, and has a scope chain of `org -> project` for future per-scope plugin/context execution.

Smoke test:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/hello/max
```

Expected responses:

```text
ok
max
```

## Registry Export

`partiture.lua` uses Ballad's `registry.source_package` to create a source-built Moonstone package under `dist/registry/meteorite`.

```bash
moon exec ballad -- play partiture.lua
```

The emitted source package keeps generated graph files, build outputs, Moonstone env files, and VCS metadata out of the archive.

v0.1 intentionally generates graph data and bindings only; route matching and server behavior live in Zig.

## Demo Surface

`fixtures/demo/src/app.lua` shows the intended hybrid authoring feel: Lua handlers stay Hono-like, while outbound services and native helpers are declared as graph-visible capabilities.

```lua
local m = require("meteorite")

local app = m.app({ name = "demo" })

app:capability("http", {
  db = {
    base_url = "http://localhost:8888",
    timeout_ms = 1500,
    max_response_bytes = 65536,
  },
})

app:capability("zig", {
  data_cruncher = "native/src/helpers/data_cruncher.zig",
})

app:get("/devices/:device_id", {
  params = {
    device_id = m.pattern("^[a-z0-9_-]{1,64}$"),
  },
}, function(c)
  local cruncher = c:zig("data_cruncher")
  return c:json({ device = cruncher.device_name(c.params.device_id) })
end)
```

Meteorite separates state by lifetime:

- `c.state`, `c:set(key, value)`, and `c:get(key)` are request-local.
- `app.cache` and `c:cache(name)` are worker-local and explicit.
- `c:auth("db")`, `c:http("db")`, and `c:zig("data_cruncher")` access named capability-owned stores.

Cross-request mutable state belongs inside capabilities, not inside `c`.

The prototype hybrid runner can invoke inline Lua routes without starting the Zig server:

```bash
luajit src/meteorite/cli.lua invoke fixtures/demo/src/main.lua GET /devices/router_01
```

This runner exercises request-local state, declared HTTP/auth capability stubs, declared Zig helper stubs, typed params, and pattern validation. The native Zig runtime now has a bridge hook for inline/module Lua handlers; embedding a real Lua VM behind that hook is the next step.
