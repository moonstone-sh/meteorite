# Meteorite Docs

Meteorite's root `README.md` is the public landing page. The guided
documentation and API reference live at
[meteorite.moonstone.sh](https://meteorite.moonstone.sh). This directory owns
durable product docs, design notes, roadmaps, maintenance records, and
historical archive material.

## Product Docs

- `examples.md` — copyable route and app shapes; not init templates.
- `deployment.md` — release layout, deployment model, and non-goals.
- `benchmarks.md` — benchmark methodology, scripts, and result interpretation.
- `ipc-unix-socket.md` — Unix-socket IPC status and usage notes.
- `typed-route-contexts.md` — how route handlers get a specific `c` type in the editor, the `.luarc.json` prerequisite, and why no LuaLS plugin is needed.
- `release-compiler-contract.md` — release compiler contract, validation gates, and implementation checklist.
- `release-process.md` — tag preparation, source-package verification, checksum, and publishing sequence.
- `release-notes/` — versioned user-facing release notes.

## Architecture And Design Notes

- `architecture/composition-lifecycle-decisions.md` — canonical scope, pipeline, plugin, and lifecycle decisions.
- `design/route-contract.md` — canonical route contract and pipeline lowering model.
- `design/openapi.md` — OpenAPI 3.1 generation design.
- `design/unix-socket-backend-discovery.md` — Unix-socket backend discovery and migration notes.
- `design/stateful-hmr-supervisor.md` — stateful live-reload supervisor design.

## Roadmaps

- `roadmap/v0.1-ga.md` — v0.1 support matrix, release gates, CI runner contract, and deferred scope.
- `roadmap/web-standards.md` — HTTP/web standards coverage and future work.
- `roadmap/hono-parity.md` — Hono comparison and parity roadmap.
- `roadmap/ipc-unix-socket-http.md` — HTTP-over-Unix-socket roadmap.

## Maintenance And Archive

- `maintenance/composition-lifecycle-implementation-audit.md` — scope and lifecycle implementation audit record.
- `maintenance/composition-lifecycle-doc-review.md` — public composition guide verification matrix.
- `maintenance/release-candidate-audit-2026-07-17.md` — current v0.1 GA gate audit.
- `maintenance/release-candidate-audit-2026-07-14.md` — latest v0.1 service-layer release audit result.
- `maintenance/docs-stabilization.md` — docs tree stabilization record.
- `archive/` — historical validation, claim-safety, and framework-guidance artifacts.
