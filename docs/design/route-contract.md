# Meteorite Route Contract

Meteorite normalizes every route declaration into one graph-readable route contract before code generation. The Lua DSL may use legacy convenience signatures or the canonical table form, but the compiler lowers both into the same internal shape so release validation, graph inspection, OpenAPI emission, and Zig code generation consume one contract.

## Canonical Route Shape

The canonical declaration is a table passed to an HTTP method helper:

```lua
app:get({
  route = "/orders/:id",
  id = "orders.show",
  name = "Show order",
  summary = "Fetch one order",
  params = { id = m.u64() },
  query = { verbose = m.bool({ optional = true }) },
  body = { max_bytes = 4096 },
  policy = { cache = true },
  responses = {
    [200] = { description = "OK" },
    [404] = { description = "Order not found" },
  },
  pipeline = function(ctx)
    ctx:transform({ id = "auth", strat = "zig", path = "zig/stages/auth.zig" })
    ctx:handle({ id = "show", strat = "zig", path = "handlers.show_order" })
    ctx:hook("post_handler", { id = "timing", strat = "zig", path = "zig/hooks/timing.zig" })
  end,
})
```

Required fields:

- `route` — raw path pattern, such as `/users/:id` or `/assets/:path*`.
- one `handle` stage, either explicit in `pipeline` or lowered from a legacy handler argument.

Common optional fields:

- `id` — stable route id for generated Zig context names and diagnostics.
- `name`, `summary`, `description`, `tags`, `responses` — documentation/OpenAPI metadata.
- `params`, `query`, `body` — validation and request limit metadata.
- `policy` — plugin-readable route policy.
- `capabilities` — declared runtime capability requirements.
- `memory` — route-local resource profile overrides.
- `meta` — tool-specific metadata that does not affect dispatch.

## Legacy Lowering

Legacy declarations remain supported and lower to the same contract:

```lua
app:get("/health", function(ctx)
  return ctx:text("ok")
end)

app:get("/users/:id", { params = { id = m.u64() } }, "handlers.show_user")
```

Lowering rules:

- inline Lua functions become one `handle` stage with `strat = "inline_lua"`.
- Lua file/module handlers become one `handle` stage with `strat = "lua"`.
- Zig handler strings become one `handle` stage with `strat = "zig"`.
- route options such as `params`, `query`, `body`, `responses`, and `policy` are copied onto the route contract.

## Pipeline Builder

The `pipeline = function(ctx) ... end` callback runs at graph-build time, not request time. The `ctx` value is a `PipelineBuilder` that records stages in order.

Supported builder methods:

```lua
ctx:transform({ id = "load", strat = "zig", path = "zig/stages/load.zig" })
ctx:transform("lua", "stages/load.lua")
ctx:transform(function(ctx) ctx.state.loaded = true end)

ctx:handle({ id = "show", strat = "zig", path = "handlers.show" })
ctx:handle("lua", "handlers/show.lua")
ctx:handle(function(ctx) return ctx:text("ok") end)

ctx:hook("post_handler", { id = "audit", strat = "lua", path = "hooks/audit.lua" })
```

Stage fields:

- `id` — stable stage id within the route.
- `kind` — `transform`, `handle`, or `hook`.
- `phase` — required for hook stages.
- `strat` — `inline_lua`, `lua`, `zig`, or rejected `rust` placeholder.
- `path` — external Lua/Zig module path or Zig symbol reference.
- `symbol` — optional Zig symbol name when separate from path.
- `reads`, `writes` — declared resource access for validation and plugin ordering.
- `may_short_circuit` — whether the stage may produce a response before the handler.
- `owner` — plugin id when injected by a plugin.
- `source` — source file/line captured for diagnostics.

## Hook Phases

Valid hook phases are:

- `pre_tree` — before route params exist; cannot read params or mutate responses.
- `post_match` — after route match; can inspect route facts.
- `pre_handler` — before the main handler.
- `post_handler` — after the handler; may mutate staged response headers.
- `observe` — read-only observation after handler work.
- `error` — error handling phase.

Ordering is validated around the first `handle` stage:

- `pre_tree`, `post_match`, and `pre_handler` hooks must appear before `handle`.
- `post_handler`, `observe`, and `error` hooks must appear after `handle`.
- transform stages are order-preserving middleware and may appear before or after `handle`.

## Runtime Status

For v0.1, the graph and code generation preserve full pipeline metadata. Handler execution is implemented. Transform and hook runtime execution are represented in the contract and generated graph, but full request-time transform/hook semantics remain a tracked follow-up unless the stage is compiled into existing plugin/runtime behavior.

Release-mode validation still applies to every retained stage:

- static release rejects retained Lua runtime execution stages.
- hybrid release packages retained Lua stages and the required Lua runtime artifacts.
- diagnostics should include route id, stage id, kind, strategy, path, owner, and source location when a pipeline stage fails validation or execution.

## Graph Inspection

Use the routes command to inspect the normalized contract:

```bash
meteorite routes src/main.lua
meteorite routes --graph src/main.lua
```

The JSON form emits `meteorite.routes.v0` and includes route metadata, validators, runtime requirements, scope/plugin ids, and pipeline stages. This output is the stable tooling surface for generated clients, documentation checks, and editor integrations.
