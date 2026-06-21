# Pending: Meteorite Release Compiler Contract

Meteorite release export should be treated as a compiler contract over one normalized application graph. Lua may construct the graph in every release mode; the mode only changes which runtime execution nodes the final graph is allowed to retain and what target artifacts must be materialized.

## Contract Modes

### Static

`meteorite.release({ mode = "static" })` validates the graph as a Zig-only runtime artifact.

Allowed:

- Lua DSL code that runs on the host to produce the graph.
- Lua plugins/macros that expand entirely into graph facts or Zig/static references during graph construction.
- Generated Zig route tables, handler bindings, static route constants, and compile-time-known limits.

Forbidden:

- inline Lua route handlers retained in the emitted graph;
- `m.lua(...)` file/module route handlers retained in the emitted graph;
- scoped plugin runtime `execute` functions retained in the graph;
- plugin handlers that lower to Lua runtime handlers;
- any other runtime node that requires an embedded Lua interpreter after export.

Failure must list each retained Lua runtime node with source location and suggest either `mode = "hybrid"` or replacing the non-graphable Lua with Zig/graph-expanded equivalents.

### Hybrid

`meteorite.release({ mode = "hybrid" })` validates the same graph as a mixed Zig + Lua runtime artifact.

Allowed:

- all static-mode graph construction behavior;
- retained inline Lua route handlers;
- retained Lua file/module handlers;
- retained scoped Lua plugin execution nodes.

Required when Lua runtime nodes remain:

- materialize the target Lua runtime, not the developer machine's host runtime;
- materialize target-compatible pure Lua modules;
- rebuild/materialize target-compatible Lua C modules for the selected runtime ABI;
- emit artifact-local runtime metadata so the server can set `LUA_PATH` and `LUA_CPATH` without depending on the host `.moonstone/env`.

For same-host development exports, the current implementation can package the materialized `.moonstone/env` Lua module trees. For cross-target exports, the compiler must require Moonstone store facts for target runtime source/module source before building.

## API Shape

```lua
local release = meteorite.release({
  mode = "hybrid", -- or "static"
  target = "aarch64-linux-gnu", -- e.g. Raspberry Pi 5
  optimize = "ReleaseFast",
  output = "dist/server",
  runtime = {
    id = "lua@5.4.7",
    abi = "lua54",
    source_payload_path = "/store/.../lua-5.4.7.tar.gz",
  },
})
```

`mode` selects validation over the normalized graph. It should not select a separate graph builder.

## Moonstone/Ballad Store Contract

The Moonstone Ballad plugin should expose runtime and package facts from the Moonstone store:

- selected runtime identity, version, ABI, and target support;
- host runtime executable path used only for graph construction;
- runtime binary artifact path in the content-addressed store;
- runtime source payload path in the content-addressed store;
- runtime headers/libs metadata when materialized;
- pure Lua module payloads selected by the project lock;
- Lua C-module source payloads and ABI metadata selected by the project lock.

Meteorite consumes those facts as compiler inputs. Static mode may ignore target Lua materialization because the validated graph cannot retain Lua runtime nodes. Hybrid mode must fail if retained Lua nodes exist and the required target Lua facts are unavailable.

## Current Implementation Status

Implemented now:

- `meteorite.release` creates one normalized graph and validates it as `static` or `hybrid`.
- Static mode fails before Zig build when retained Lua runtime execution nodes are present.
- Hybrid mode records release-contract metadata in `meteorite-release.json`.
- Hybrid cross-target mode fails early when retained Lua runtime nodes exist but no Lua runtime source payload is supplied.
- Hybrid same-host mode packages lifted inline chunks, app Lua sources, and current Moonstone Lua module/C-module trees.

Still pending:

- Moonstone plugin API should pass runtime/package source payload facts directly to `meteorite.release`.
- Meteorite should compile PUC Lua from `source_payload_path` with `zig cc` for `opts.target`.
- Meteorite should rebuild Lua C modules from source for the selected target/ABI.
- LuaJIT support needs a separate target matrix and host `buildvm` stage.

## Target Hybrid Build Flow

1. Host Lua evaluates the Meteorite app and produces the normalized graph.
2. Meteorite validates the graph using the selected release mode.
3. If hybrid retains Lua nodes, Meteorite asks Moonstone/Ballad for target runtime and module source facts.
4. Meteorite builds target Lua with `zig cc` and selected Zig target flags.
5. Meteorite builds the server against the target Lua headers/library when needed.
6. Meteorite collects release files:
   - `bin/server`;
   - target-built `liblua` if dynamically linked;
   - lifted inline Lua chunks;
   - external Lua handler/plugin files;
   - pure Lua package modules;
   - target-built Lua C modules.
7. Meteorite emits artifact-local runtime metadata and uses it at startup for `LUA_PATH`/`LUA_CPATH`.

## Missing Runtime Source Diagnostic

Hybrid cross-target release should fail before build when retained Lua nodes require target Lua but Moonstone cannot provide source:

```text
meteorite.release({ mode = 'hybrid', target = 'aarch64-linux-gnu' }) failed the release compiler contract.

Hybrid mode may retain Lua runtime execution nodes, but cross-target release must materialize target Lua and target Lua modules.

Missing:
  source_payload_path

Hint: pass runtime = { source_payload_path = ... } from the Moonstone/Ballad plugin, set lua_source/runtime_source, or build static after replacing Lua runtime handlers/plugins.
```
