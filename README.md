# Meteorite

Meteorite is a Moonstone-zig service compiler prototype.

```text
Lua declares.
Ballad materializes.
Zig compiles.
Meteorite lands.
```

## Package Shape

- `src/` contains Meteorite Lua implementation modules grouped by responsibility: `core`, `codegen`, `ballad`, `cli`, and `utils`.
- `src/meteorite.lua` is the public `require("meteorite")` facade.
- `fixtures/apps/showcase-service/` is the local acceptance app used by default graph/build scripts.
- `zig/` contains handwritten Zig runtime behavior, handlers, validators, and the `std.http` backend implementation.
- `.meteorite/graph/current/` contains generated graph data and Zig bindings.
- `partiture.lua` exports Meteorite itself as a Moonstone source package for the registry.

## Local v0.1 Flow

For a new app, keep Meteorite-specific project shape in Meteorite's CLI:

```bash
meteorite init my-app              # minimal Lua-first hybrid app
meteorite init my-app --static     # pure Zig handlers; no Lua runtime in output
meteorite init my-app --hybrid     # mixed Lua + Zig handlers
meteorite help                     # list commands and examples
meteorite doctor                   # check local project/tool readiness
```

App examples live in `docs/examples.md`; they are intentionally not init templates. Native Unix-socket IPC notes live in `docs/ipc-unix-socket.md`; runnable Unix-socket examples live in `fixtures/examples/unix-socket/`.

```bash
moon run generate-graph       # writes .meteorite/graph/current
moon run build                # local dev binary at dist/server
./dist/server
```

For development, run the partition-aware supervisor:

```bash
moon run dev
```

`moon run dev` regenerates the graph on source changes, rebuilds/restarts for route/zig/build changes, and reloads inline Lua handler chunks in-process when only `lua_chunk` partitions changed. The dev loop uses `hybrid_dev`, `std_http`, and the optimized cached Lua runtime so Lua handler edits update without a Zig rebuild or server restart.

The dev command runs through `scripts/guard.sh`, which cleans stale `moon run dev` supervisors and `dist/server` listeners before handoff. If a session is interrupted or port `8080` looks stuck, run `scripts/guard.sh status` or `scripts/guard.sh handoff` from the repo root.

For deployable output, use the app's Ballad partiture instead of `dist/server`:

```bash
moon run release
dist/release/bin/server
```

`dist/server` is a local development binary. `dist/release/` is the self-contained deploy directory with `bin/server`, `meteorite-release.json`, static assets, and any same-host hybrid Lua/module trees needed by the app.

Generated route data is split into `.meteorite/graph/current/routes/<route_id>.zig` modules and DFA tables are split into `.meteorite/graph/current/patterns/<pattern_id>.zig` modules. Generated files are written only when content changes, so route-shape or pattern edits touch the affected module instead of rewriting every generated declaration.

Mounted route scopes are represented in the graph and executed at runtime. `app:mount("/orgs/:org_id", { params = { org_id = m.u64() } }, function(api) ... end)` prefixes child routes, inherits declared mount params/query/capabilities, and records a deterministic scope chain. Scope metadata includes `id`, `parent`, `path_prefix`, inherited plugin refs, and context refs. Plugins registered via `app:use(plugin)` or mount `plugins = { ... }` now execute in scope order before the route handler, and a short-circuiting plugin response skips the handler. Handlers read merged scope context values through the read-only `ctx.scope.<key>` view in both the Lua hybrid runner and the Zig server.

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

The generated route becomes `/orgs/:org_id/projects/:project_id/users/:id`, carries all three param validators, and has a scope chain of `org -> project`; plugins in the chain execute root-to-leaf and the merged context view is available to the handler.

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

## Production Release Export

Meteorite owns production service exports through its Ballad plugin on a per-app basis. Use `meteorite.release({ mode = "static" })` for Zig-only servers or `meteorite.release({ mode = "hybrid" })` when inline/module Lua handlers or scoped Lua plugins are part of the app:

```lua
local ballad = require("ballad")

return ballad.partiture(function(p)
  local moonstone = p:use(ballad.plugins.moonstone)
  local meteorite = p:use("meteorite.ballad")
  local project = moonstone.project({ root = "." })

  local release = meteorite.release({
    project = project,
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    mode = "hybrid", -- or "static"
    target = "aarch64-linux-gnu", -- optional cross target
    bin = "bin/server",
    backend = "std_http",
    router_dispatch = "param_matchers",
  })

  p.sink.directory(release, { out = "dist/release", file_graph = true })
end)
```

Run it with `moon run release`; deploy or copy only `dist/release/`, then start the app with `dist/release/bin/server`.

Static and hybrid are release compiler validation modes over the same normalized graph. Lua may build the graph in either mode; static fails if the graph retains Lua runtime execution nodes. Hybrid may retain Lua handlers/plugins, records the retained-node contract in `meteorite-release.json`, and materializes target Lua plus target Lua modules for cross-target releases when Moonstone provides runtime/package source payloads. Same-host hybrid exports include the server binary, lifted inline chunks, external Lua handlers, and deploy-local `lua/<abi>` plus `lib/<abi>` package trees so `require(...)` works from inline isolates in the exported layout.

For v0.1, same-host hybrid and static releases are the supported deploy path. Cross-target hybrid is intentionally treated as not fully unlocked until Moonstone consistently exposes upstream Lua runtime and Lua package source provenance.

Static sites are declared with handler factories and graph-visible route macros, not app-level fallback methods:

```lua
local m = require("meteorite")
local app = m.app()

m.site(app, {
  root = "./site/dist",
  html = {
    ["/"] = "index.html",
    ["/docs/:route*"] = "index.html",
  },
  files = {
    ["/benchmarks.json"] = { file = "benchmarks.json", content_type = "application/json; charset=utf-8" },
  },
  assets = {
    ["/assets/:path*"] = { dir = "assets", param = "path", immutable = true, compressed = { gzip = true, br = true } },
  },
})

return app
```

`meteorite.release({ mode = "static" })` exports a deployable directory with `bin/server`, `static/`, and `meteorite-release.json`. Static assets are frozen into the release asset graph, listed in the manifest with content type, content length, ETag, cache policy, and precompressed variants, and are served without runtime Lua. Symlinks in static roots are rejected during graph generation; path traversal and malformed percent-encoding return `404` at runtime.

v0.1 intentionally generates graph data and bindings only; route matching and server behavior live in Zig.

## Demo Surface

`fixtures/apps/hybrid-demo/src/app.lua` shows the intended hybrid authoring feel: Lua handlers stay Hono-like, while outbound services and zig helpers are declared as graph-visible capabilities.

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
  data_cruncher = "zig/helpers/data_cruncher.zig",
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
luajit src/cli/main.lua invoke fixtures/apps/hybrid-demo/src/main.lua GET /devices/router_01
```

This runner exercises request-local state, declared HTTP/auth capability stubs, declared Zig helper stubs, typed params, and pattern validation. The zig Zig runtime now has a bridge hook for inline/module Lua handlers; embedding a real Lua VM behind that hook is the next step.
