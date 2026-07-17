# Release Candidate Audit — 2026-07-17

Purpose: record the v0.1 GA gate after repository-hygiene cleanup and Linux
cross-target matrix certification.

## Result

Status: **pass for the declared v0.1 release gate; ready to tag once release
notes and artifact checksums are prepared**.

The audit ran from the Meteorite checkout at `fde0649` (`Harden v0.1 GA release
gate`). Zig version: `0.16.0`.

## Checks Run

| Check | Result | Notes |
| --- | --- | --- |
| `bash tests/repository-hygiene.sh` | Pass | No generated benchmark or compiler workspace artifacts remain tracked. |
| `bash tests/registry-export.sh` | Pass | Source package contains required public docs and excludes generated root artifacts. |
| `bash tests/run-all.sh` | Pass | 20 Lua unit/integration test files passed. |
| `bash fixtures/tests/web-standards.sh` | Pass | HTTP/web standards fixture passed. |
| `bash fixtures/tests/ipc-backends.sh` | Pass | Native IPC and HTTP-over-Unix-socket backends passed. |
| `bash fixtures/tests/basic-service.sh` | Pass | Black-box routing, validation, body-limit, capability, and Zig-handler coverage passed. |
| `bash fixtures/tests/release-smoke.sh` | Pass | Copied static release execution and no-source-leak checks passed. |
| `bash tests/release-reproducibility.sh` | Pass | Two static releases retained identical graph hash, contract, and static manifest entries. |
| `bash fixtures/tests/ipc-release-smoke.sh` | Pass | IPC release manifest/release smoke path passed. |
| `zig build` | Pass | Root showcase-service build passed. |
| `METEORITE_CROSS_TARGET=aarch64-linux-gnu bash fixtures/tests/cross-target.sh` | Pass | PUC Lua hybrid release, source provenance, and synthetic C-module rebuild passed. |
| `METEORITE_CROSS_TARGET=x86_64-linux-gnu bash fixtures/tests/cross-target.sh` | Pass | PUC Lua hybrid release, source provenance, and synthetic C-module rebuild passed. |
| `bash tests/release-gate.sh` | Pass | Aggregate command reran every gate above. |

## Certified v0.1 Matrix

- Static: native, `aarch64-linux-gnu`, and `x86_64-linux-gnu`.
- Hybrid: PUC Lua 5.4 on native, `aarch64-linux-gnu`, and `x86_64-linux-gnu`,
  subject to Moonstone runtime source provenance.
- Hybrid Lua C modules: supported only with package source and rockspec
  provenance and a successful target rebuild.

## Known Boundaries

- LuaJIT cross-target hybrid remains unsupported.
- Cross-target hybrid must fail when runtime or C-module provenance is absent;
  it must not reuse host binaries.
- WebSockets, multipart route parsing, streaming responses, trusted-proxy IP
  canonicalization, and serverless/edge adapters remain explicit non-goals for
  v0.1.
- Fixture releases intentionally print strict-documentation diagnostics for
  undocumented fixture routes; those are expected negative coverage and not
  audit failures.

## Tag Preparation

- Prepare release notes that state the support matrix and known boundaries.
- Build registry/release artifacts from the tag commit and publish checksums.
- Preserve this audit with the final tag and artifact identifiers if they differ
  from the audited commit.
