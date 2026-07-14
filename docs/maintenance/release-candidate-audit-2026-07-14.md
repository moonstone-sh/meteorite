# Release Candidate Audit — 2026-07-14

Purpose: record the current v0.1 service-layer release audit, the exact checks run, and the remaining known limits before tagging a release candidate.

## Result

Status: **pass for static and same-host hybrid service-layer release paths**.

The audit found and fixed one fixture-local build drift:

- `fixtures/apps/basic-service/build.zig` had stale generated `build_info` fields and stale runtime module imports after peer-credential and backend capability work.
- `fixtures/tests/basic-service.sh` still expected query validation failures to behave like path mismatch `404`s. Current request validation returns deterministic `400` with validation diagnostics for missing/invalid query values.
- The same test script had temp-copy path rewrites that did not cover the newer runtime Zig submodules used by `zig/meteorite.zig`.

## Checks Run

| Check | Result | Notes |
| --- | --- | --- |
| `bash tests/run-all.sh` | Pass | Lua unit/integration suite: 19 test files passed. |
| `bash fixtures/tests/web-standards.sh` | Pass | Required elevated Zig cache/std access in the local sandbox. |
| `bash fixtures/tests/ipc-backends.sh` | Pass | Native IPC and HTTP-over-Unix-socket backend fixture coverage. |
| `bash fixtures/tests/basic-service.sh` | Pass | Acceptance fixture after build-info/import/test-expectation fixes. |
| `bash fixtures/tests/release-smoke.sh` | Pass | Static release layout, copied release execution, no-source-leak checks. |
| `bash fixtures/tests/ipc-release-smoke.sh` | Pass | IPC release manifest/release smoke path. |
| `zig build` | Pass | Root showcase-service build sanity check. |
| `bash fixtures/tests/cross-target.sh` | Pass | Consumed Ballad/Moonstone project runtime facts, hydrated PUC Lua source from the Moonstone artifact manifest, and produced an `aarch64-linux-gnu` hybrid release. |

## Environment Notes

- Zig build commands needed access to Zig's standard library and global cache outside the workspace sandbox.
- Local cross-target Lua source archive was not present at `../moonstone-tools/scripts/runtime/src/lua-5.4.7.tar.gz`, but the Ballad/Moonstone project runtime fact points at a Moonstone artifact whose `manifest.toml` exposes `source_kind = "puc_lua_source"` and `sources/source.tar.gz`; Meteorite now hydrates that manifest provenance during release option normalization.
- Several fixture release builds intentionally print strict-doc diagnostics for undocumented fixture routes; those diagnostics are expected coverage, not audit failures.

## Current Supported Release Path

- Static releases are supported for graphs that retain no Lua runtime execution nodes.
- Same-host hybrid releases are supported for graphs that retain Lua handlers/plugins and package local Lua/module trees.
- HTTP TCP, native Unix-socket IPC, and HTTP-over-Unix-socket backend fixtures pass their current smoke/acceptance coverage.

## Still Not Release-Unlocked

- Cross-target hybrid remains conditional on Moonstone runtime/package source provenance. The local Moonstone store currently provides the upstream PUC Lua source archive for `moonstone/lua` 5.4.7.
- LuaJIT cross-target hybrid remains explicitly unsupported until a target matrix and host `buildvm` stage exist.
- Lua C-module cross-target rebuilds require source payloads, rockspec payloads, supported archive formats, and a host `luarocks` executable.
- WebSockets, multipart route parsing, streaming responses, trusted proxy IP canonicalization, and serverless/edge adapters remain explicit non-goals or P1/P2 work for this release line.

## Next Audit Step

Run the required cross-target audit:

```bash
moon run test-cross-target
```

If that passes, record the target triple, source archive, and produced binary/runtime facts here or in a follow-up dated audit note.
