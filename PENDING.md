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
- `meteorite.release({ project = moonstone.project(...) })` consumes Moonstone runtime/package store facts automatically.
- Cross-target hybrid release invokes `scripts/build-target-lua.sh` to build PUC Lua from `runtime.source_payload_path` with `zig cc` and passes the result to Zig via `-Dlua-root`.
- Cross-target hybrid release schedules per-package Lua C-module rebuilds through `scripts/build-lua-cmodule.sh` when C-module packages expose `source_payload_path` and `rockspec_payload_path`.

Cross-target PUC Lua compilation is now verified:

- `scripts/build-target-lua.sh` successfully cross-compiles PUC Lua 5.4.7 for `aarch64-linux-gnu` using `zig cc` from the upstream source archive.
- Static release cross-compilation (e.g. `zig build install-server -Dmode=release-static -Dtarget=aarch64-linux-gnu`) produces a statically linked ELF binary.
- Hybrid release cross-compilation with a target-built `liblua.a` produces a binary with the target Lua runtime linked in.
- The full chain works: Moonstone store source provenance (`source_kind = "puc_lua_source"`, `source_payload_path`) → Ballad `hydrate_runtime()` → Meteorite `release_contract.validate_target_lua()` → `build-target-lua.sh` → `zig build -Dlua-root=...`.
- Fixed `build-target-lua.sh` find depth: `-maxdepth 2` → `-maxdepth 3` so `lua-<ver>/src/lua.c` is discovered in standard upstream source archives.

Still pending:

- LuaJIT support needs a separate target matrix and host `buildvm` stage.
- Lua C-module rebuilds currently rely on package rockspecs and a local `luarocks` executable; packages without source/rockspec payloads fail with package-specific diagnostics.
- Moonstone runtime/package descriptors should consistently publish source payloads for all production-supported hybrid targets.
- `build.zig` `join()` does not handle absolute `-Dlua-root` paths; the Ballad release flow always uses relative paths so this is not a blocker for production releases.

## Responsibility-Structure Cleanup Checklist

Meteorite should be organized by compiler/runtime responsibility, not by historical growth. Large mixed-purpose files should be split until each module owns one clear concern.

- [x] Unroll Lua source into `src/{core,codegen,ballad,cli,utils}` with public Meteorite facades.
- [ ] Finish splitting `src/codegen/emitter.lua` into focused compiler modules:
  - [x] static asset compiler/scanner/manifest builder;
  - [ ] Zig graph type/table emitter;
  - [ ] handler binding/stub sync;
  - [x] partition hash/diff reporting;
  - [ ] build report/LSP aid generation.
- [ ] Finish splitting `src/meteorite.lua` into:
  - [ ] public DSL/app construction;
  - [x] route macros such as `m.site`;
  - [x] handler factories such as `m.file` and `m.dir`;
  - [ ] schema/validator exports.
- [x] Split `src/ballad/` into:
  - [x] release contract validation;
  - [x] release manifest generation;
  - [x] Moonstone runtime/package asset collection;
  - [x] zig task argument construction.
- [x] Move user-facing Zig project layout from `native/` to `zig/` and keep `native_task` wording only where Ballad/Moonstone APIs require it.
- [x] Keep Meteorite init templates execution-mode focused:
  - [x] minimal Lua-first hybrid app;
  - [x] static Zig-handler app;
  - [x] hybrid Lua + Zig app;
  - [x] CRUD moved to `EXAMPLES.md` instead of `meteorite init`.
- [x] Remove the Meteorite template from Moonstone; Meteorite owns Meteorite project scaffolding.
- [x] Add CLI discovery/readiness commands:
  - [x] `meteorite help` / `--help` and command-specific help;
  - [x] `meteorite doctor` readiness checks.
- [ ] Split `zig/bridge.zig` into Lua runtime responsibilities:
  - [ ] Lua state lifecycle;
  - [ ] cached inline handler refs and live reload epochs;
  - [ ] Lua context API bindings;
  - [ ] capability bridge calls;
  - [ ] debug/dev-only state.
- [ ] Split `zig/meteorite.zig` into server responsibilities:
  - [ ] request dispatch/router integration;
  - [ ] static file serving;
  - [ ] request validation/limits;
  - [ ] diagnostics/meta endpoints.
- [ ] Replace shell-based static scanning with a portable Lua/Zig filesystem walker.
- [ ] Replace manually concatenated JSON release manifests with the local JSON encoder.
- [ ] Add scenario tests for:
  - [x] `meteorite init` minimal/static/hybrid local developer flow;
  - [x] `meteorite help` and `meteorite doctor` smoke coverage;
  - [ ] inline Lua live reload with two or more edits;
  - [ ] static release export after deleting source `site/dist`;
  - [x] native hybrid release packaging pure Lua modules;
  - [x] native hybrid release packaging Lua C modules;
  - [x] cross-target hybrid release with target Lua source provenance (`fixtures/tests/cross-target.sh`);
  - [ ] cross-target hybrid release with rebuilt Lua C modules;
  - [ ] no host absolute paths or `.moonstone/env` leaks in static release text metadata.
- [x] Ensure Moonstone Lua runtime packages expose upstream source provenance, not prebuilt runtime blobs, so Meteorite can cross-build transportable hybrid releases such as `aarch64-linux-musl`.
- [x] Document the dev workflow and release ownership boundary (`meteorite dev`, Ballad-owned release via `meteorite.ballad`).
- [ ] Document the stable v0.1 deploy layout contract as a concise contract section.

## Fixture Publication Checklist

Fixtures should be shaped like small public examples, not incidental local scratch projects. Each fixture needs a distinct goal, a stable command surface, and no committed generated artifacts.

- [x] Move app fixtures under `fixtures/apps/<name>` with fixture-local `partiture.lua` files.
- [x] Add `fixtures/README.md` with fixture goals, standards, and publication rules.
- [x] Add fixture-local READMEs documenting purpose, coverage, and ownership.
- [x] Split benchmark routes into `fixtures/apps/bench-service` so showcase stays demo-focused.
- [x] Update benchmark scripts and root `moon run bench*` commands to use `bench-service`.
- [x] Remove committed fixture build outputs and ignore only fixture-root generated artifacts.

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

## Contract Standardization

The route declaration system is being standardized around a single
graph-readable contract. See `src/core/contract.lua` for the implementation.

### Completed

- [x] Define canonical `RouteContract` with method, route, id, name, policy, pipeline, hooks, meta
- [x] Implement `PipelineBuilder` with `ctx:transform()`, `ctx:handle()`, `ctx:hook()`
- [x] Define `StageContract` with kind (transform|handle|hook), strat (inline_lua|lua|zig|rust)
- [x] Lower legacy `opts.handler` to pipeline stage (sugar)
- [x] Add strict route declaration validation (missing route, conflicting fields, duplicate ids)
- [x] Add Rust strategy rejection with clear message
- [x] Add hook phase model (pre_tree, post_match, pre_handler, post_handler, observe, error)
- [x] Add graph serialization for inspection (`contract.serialize()`)
- [x] Wire `contract.build()` into `meteorite.lua` `add_route`
- [x] Canonical table form works in static and hybrid modes
- [x] Legacy form compatibility preserved
- [x] Add `meteorite routes` command for graph inspection
- [x] Add `meteorite routes --graph` JSON output
- [x] Add migration hints for legacy route signatures
- [x] Tests: contract parser (23 tests, 73 assertions)

### Still pending

- [ ] Transformer semantics: runtime execution model for pipeline stages
- [ ] Handler semantics: pipeline with no explicit handler, transform-only pipeline
- [x] Hook phase enforcement: phase permissions at graph validation ()
- [x] Plugin model: `PluginContract`, graph mutation API ()
- [x] First-party plugin: cache ()
- [x] First-party plugin: idempotency ()
- [ ] First-party plugin: cache (`meteorite.plugins.cache`)
- [ ] First-party plugin: idempotency (`meteorite.plugins.idempotency`)
- [ ] Pipeline stage representation in Zig graph types
- [ ] Native stage compilation contract for Zig stages
- [ ] Diagnostics: pipeline failure with route id, stage id, kind, strat, path, owner
- [ ] Dev endpoint `/__meteorite/graph` for runtime graph inspection
- [ ] Graph JSON snapshot tests
- [ ] Documentation: canonical route contract, pipeline declaration, transform notation
