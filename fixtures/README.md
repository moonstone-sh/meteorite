# Meteorite Fixtures

Fixtures are small, purpose-built Meteorite apps used for demos, acceptance tests, release checks, and benchmarks. Each fixture should prove one distinct capability and should be safe to regenerate from source.

## Layout Standard

- App fixtures live under `fixtures/apps/<name>/`.
- App-specific partitures live beside the fixture as `partiture.lua`.
- Test runners live under `fixtures/tests/`.
- Every app fixture must have `src/main.lua` and usually `src/app.lua`.
- Add `zig/` only when the fixture intentionally exercises Zig handlers or zig helpers.
- Add fixture-local `README.md` explaining goal, what it touches, and the main command.
- Do not commit generated `.meteorite/`, `.zig-cache/`, `.moonstone/`, `.moonstone-home/`, `dist/`, logs, or benchmark output.

## Fixture Roles

- `apps/showcase-service` is the default local app for graph/build/dev scripts.
- `apps/basic-service` is the black-box acceptance fixture for routing, validators, body limits, memory reports, capabilities, and Zig handlers.
- `apps/hybrid-demo` exercises inline Lua handlers, graph-visible capabilities, and hybrid invoke behavior.
- `apps/scoped-plugins` isolates scoped mounts, plugins, and request-local state.
- `apps/static-site` exercises `m.file`, `m.dir`, `m.site`, and static release packaging.
- `apps/bench-service` contains benchmark-only endpoints consumed by `bench/run.sh` and related benchmark scripts.

## Publication Rule

A fixture deserves to exist only if deleting it would remove coverage for a distinct public behavior, release shape, or benchmark scenario. If two fixtures test the same behavior, merge them or make one a documented demo and the other a black-box test.
