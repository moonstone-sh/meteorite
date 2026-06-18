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
