# Pending: Production Hybrid Runtime Builds

Meteorite's production release path should split host graph construction from target runtime execution.

## Desired Release Model

`meteorite.release({ mode = "static" })` should produce a Zig-only server and fail if any runtime Lua remains in the emitted graph.

`meteorite.release({ mode = "hybrid" })` should build and ship the Lua runtime for the requested target alongside the Meteorite server. The Lua runtime should not be copied from the developer machine's current `.moonstone/env`; it should be built from source with `zig cc` for the release target.

Example API shape:

```lua
local release = meteorite.release({
  mode = "hybrid", -- or "static"
  target = "aarch64-linux-gnu", -- e.g. Raspberry Pi 5
  optimize = "ReleaseFast",
  output = "dist/server",
})
```

## Ownership

The Moonstone Ballad plugin should expose runtime/store facts:

- selected runtime identity, version, ABI, and target support;
- host runtime executable path for graph construction;
- runtime artifact path in the local content-addressed store;
- runtime source payload path in the store;
- runtime headers/libs metadata when materialized;
- package source payloads for Lua C modules.

The Meteorite Ballad plugin should consume those facts:

- static release: validate no Lua refs remain in the runtime graph;
- hybrid release: build target Lua with `zig cc`, build the server against it, collect Lua files/packages, and compile Lua C modules for the same target/ABI.

## Hybrid Build Flow

1. Use host Lua from Moonstone env to evaluate `src/main.lua` and emit the graph.
2. Ask Moonstone for the selected runtime source payload and ABI metadata.
3. Build PUC Lua with `zig cc` for `opts.target`.
4. Build Meteorite server against the target-built Lua headers/library.
5. Collect release files:
   - `bin/server`;
   - target-built `liblua` if dynamically linked;
   - lifted inline Lua chunks;
   - external Lua handler/plugin files;
   - pure Lua package modules;
   - target-built Lua C modules.
6. Generate artifact-local runtime metadata and package paths:
   - `LUA_PATH` for shipped Lua files/modules;
   - `LUA_CPATH` for target-built C modules.

## Static Mode Validation

Static mode should allow Lua that runs only during graph construction. It should fail only for Lua that remains in the emitted runtime graph, including:

- inline Lua route handlers;
- `m.lua(...)` file/module route handlers;
- scoped Lua plugins with runtime `execute` functions;
- plugin handlers that compile to Lua runtime handlers.

The error should include every source location and suggest either `mode = "hybrid"` or replacing non-graphable Lua with Zig/graph-expanded handlers/plugins.

## Missing Runtime Source

Hybrid cross-target release should fail early if Moonstone cannot provide runtime source:

```text
meteorite.release({ mode = "hybrid", target = "aarch64-linux-gnu" }) requires Lua runtime source.

Runtime:
  lua@5.4.7

Missing:
  source_payload_path

Hint:
  run moon sync with source artifacts enabled, or install a runtime package that includes source.
```

## Staging

1. Support PUC Lua 5.4 source builds with `zig cc`.
2. Rebuild Lua C modules from source for the target ABI.
3. Add LuaJIT later with an explicit target support matrix, because LuaJIT cross-compilation needs a host `buildvm` stage and target-specific flags.
