# Typed Route Contexts in the Editor

How `c` gets a specific type inside `app:get("/users/:id", function(c) ... end)`,
what that costs, and where it stops working.

> **Written 2026-09-10 to settle a question that had been answered wrongly.**
> An earlier research pass concluded that per-route context types "already
> exist in the generated file and are never reached", and proposed writing a
> LuaLS plugin — modelled on `clingy/luals/plugin.lua`'s `---@cast` injection
> — to bind them to real call sites. **That plugin is unnecessary. The
> binding already works.** This document records the mechanism and the
> evidence, so the same plugin is not proposed again.

## The mechanism

`src/codegen/luals_aids.lua` runs on every `meteorite graph` / `meteorite
build` (via `src/codegen/emitter.lua` → `report.emit_luals_aids`) and writes
into `.meteorite/aids/lua/`:

| File | Contents |
| :--- | :--- |
| `meteorite.lua`, `meteorite.meta.lua` | The generic `MeteoriteContext` class, the `Context:*` method stubs, and the `MeteoriteApp` class — **including the per-route overloads below**. |
| `routes.meta.lua` | `MeteoriteParams_<id>`, `MeteoriteQuery_<id>`, and `MeteoriteContext_<id> : MeteoriteContext` for every route. |
| `lfs.lua`, `luasql/sqlite3.lua` | Stubs for the embedded runtime libraries. |

The part that does the actual binding is `append_route_overloads`, which
emits one **path-literal overload** per route onto `MeteoriteApp`:

```lua
---@field get fun(self: MeteoriteApp, path: string, handler: MeteoriteHandler): table
---@field get fun(self: MeteoriteApp, path: "/users/:id", handler: fun(c: MeteoriteContext_get_user): any): table
```

When you write `app:get("/users/:id", function(c) ... end)`, LuaLS matches
the string-literal overload and types the callback's parameter as
`MeteoriteContext_get_user` — whose `params` field is
`MeteoriteParams_get_user`, whose `id` field is `integer`.

Note that the **generic `path: string` overload is emitted first** and still
matches every call. It does not shadow the specific ones: LuaLS prefers the
literal-type overload. This was the specific doubt that motivated checking,
so it is worth stating explicitly.

## Evidence

Real `textDocument/completion` requests against
`lua-language-server 3.18.2-dev`, driven headlessly over stdio, using the
real generated aids from `fixtures/apps/basic-service`:

| Call site | Request | Result |
| :--- | :--- | :--- |
| `app:get("/users/:id", function(c)` | completion at `c.params.` | **1 item: `id`** |
| `app:get("/search", function(c)` | completion at `c.query.` | **3 items: `exact`, `page`, `q`** |
| `app:get("/no/such/route/:zzz", function(c)` | completion at `c.params.` | no field completions — falls back to generic `MeteoriteContext` |

Corroborated by `--check` diagnostics on the same sources:

- `---@type string local bad = c.params.id` on `/users/:id` →
  `Cannot assign 'integer' to 'string'`. The type is genuinely `integer`,
  not `unknown`.
- `c.params.totally_bogus` on `/users/:id` → `undefined-field`. `params` is
  a sealed class, not `table<string, …>`.
- `---@type integer local n = c.params.zzz` on an **unknown** route →
  `Cannot assign 'string|number|true' to 'integer'` — i.e. the generic
  union. Unknown routes degrade correctly instead of getting a wrong type.

## The prerequisite everyone was missing

**The aids must be on LuaLS's path**, and in every real scaffolded project
checked on this machine they were not:

| Project | `.meteorite/aids/lua` on disk | On the LuaLS path |
| :--- | :--- | :--- |
| `hyd-verify` | yes | **no** |
| `hydronium/examples/quickstart` | yes | **no** |
| `hydronium/examples/meteorite_ssr` | yes | **no** — and `.meteorite` is in `workspace.ignoreDir`, which actively suppresses it |

The cause is two generators writing the same file. Meteorite's own
`sync_luarc` (`src/codegen/handler_sync.lua`, run only by `meteorite sync`)
does include `.meteorite/aids/lua`; Hydronium's `create` scaffolder writes
its own `.luarc.json` and, until 2026-09-10, did not. Whichever ran last
won, and for Hydronium-scaffolded projects that was Hydronium.

Measured effect in a real scaffolded project, completion at `c.params.`
inside `app:get("/hydronium-src/:path*", function(c)`:

- before: **100 items**, all buffer word-completions, zero type information
- after adding `.meteorite/aids/lua` to `workspace.library` and
  `.meteorite/aids/lua/?.lua` + `/?/init.lua` to `runtime.path`:
  **1 item — `path`**

Both entries are required: `workspace.library` makes LuaLS load the class
declarations, `runtime.path` makes `require("meteorite")` resolve to the
generated stub that carries the overloads.

Hydronium's scaffolder was fixed for this (`create/src/create/luals.lua`,
gated on a per-template `meteorite` tooling flag). **Meteorite's
`sync_luarc` still overwrites `.luarc.json` wholesale** rather than merging,
so running `meteorite sync` in a Hydronium-scaffolded project will drop
Hydronium's `runtime.plugin` entry for LuaX. That is a separate, real bug;
`clingy/src/clingy/cli/init.lua` (which appends via `alter` and refuses on a
type conflict) is the reference implementation for fixing it.

## Limitations

These are honest and mostly structural — do not read the above as "route
typing always works".

1. **The path must be a string literal at the call site.** A path built
   from a variable, a concatenation, or a loop matches only the generic
   `path: string` overload, so `c` stays `MeteoriteContext`. This is the
   same class of limitation `clingy`'s plugin documents for
   dynamically-declared commands, and it is not worth solving generally.
2. **Route ids are frequently positional.** `route.id`
   (`src/core/route.lua`) falls back to `"route_" .. index` unless the
   route declares an explicit `id`, is a message route, or has a Zig
   handler symbol. In Hydronium-scaffolded apps every id is an ordinal, so
   the generated classes are `MeteoriteContext_route_1` … `_route_8` and
   **the class names shift when routes are inserted or reordered**. The
   *typing* stays correct — the overload is keyed by path, not by name —
   but the names carry no meaning and are unstable. Declaring explicit
   route ids is what buys readable names.
3. **Two routes sharing a path across methods** are disambiguated only by
   which `MeteoriteApp` field (`get`/`post`/…) is called. That is
   sufficient today, but there is no mechanism finer than the method.
4. **The aids can be stale.** They are regenerated by `graph`/`build`, not
   by editing a source file, so a route added since the last build has no
   overload yet and its handler's `c` is generic until you rebuild.
5. **`duplicate-doc-field` warnings.** `meteorite.lua` and
   `meteorite.meta.lua` are byte-identical and both land on the library
   path, and `luals_aids.lua` emits `MeteoriteContext_<id>` twice for
   routes that have both params and query. Harmless to resolution, noisy in
   diagnostics.

## Why no LuaLS plugin

A `---@cast`-injecting plugin in the style of `clingy/luals/plugin.lua`
would, at best, reproduce a result LuaLS already produces from ordinary
type annotations — while adding a text-rewriting hook that runs on every
keystroke, shifts every source offset after the first match, and has to
re-derive route ids that the generated overloads already encode. Clingy
needs that technique because it has no equivalent of a path literal to key
an overload on: its `c.run(function(ctx) ... end)` call sites are structurally
identical to each other, and the distinguishing information lives in a
surrounding `c.node(...)` tree rather than in an argument. Meteorite's
routes carry their discriminator — the path — directly in the call.

If a future change makes overload resolution insufficient (say, per-method
disambiguation stops being enough, or route declaration moves behind a
helper), revisit this. Until then the correct fix for "my route params
aren't typed" is to check that `.meteorite/aids/lua` is on the LuaLS path
and that the graph has been rebuilt.
