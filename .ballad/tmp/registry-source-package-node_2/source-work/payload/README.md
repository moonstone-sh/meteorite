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
