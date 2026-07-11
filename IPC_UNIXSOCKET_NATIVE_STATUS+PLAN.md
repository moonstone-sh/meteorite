# Meteorite Native IPC Unix Socket Backend Status + Plan

Purpose: make `ipc_unixsocket` the native Meteorite message backend. It is not HTTP over a Unix socket and must not dispatch HTTP routes by method/path. It consumes first-class graph messages declared with `app:message`.

Last reviewed: 2026-07-11

## Architecture Principle

Meteorite has separate graph projections:

```text
HTTP authoring:     app:get('/users/:id', handler)       -> HTTP route graph -> std_http | fast_http | ipc_unixsocket_http
Message authoring:  app:message('users.get', handler)    -> message graph    -> ipc_unixsocket
```

`ipc_unixsocket` owns native IPC semantics:

- Wire protocol: `meteorite.ipc.v0` length-prefixed frames.
- Dispatch identity: exact graph message name such as `users.get`.
- Parameters: explicit IPC metadata validated by the message graph.
- Query: explicit IPC metadata, not HTTP query syntax unless a future message schema names it.
- Result codes: Meteorite IPC result codes, not raw HTTP status semantics.

HTTP semantics are intentionally unavailable here: CORS, cookies, redirects, static files, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow` are HTTP backend responsibilities.

## Phase N0 — Split Cleanup

- [x] Rename canonical backend value from legacy `unix_socket` to `ipc_unixsocket`.
- [x] Remove HTTP compatibility dispatch (`GET /path`) from native IPC.
- [x] Keep IPC frame parsing/writing and Unix socket binding work under `ipc_unixsocket`.
- [x] Runtime info reports `backend = "ipc_unixsocket"`, `transport = "unix"`, `protocol = "meteorite.ipc.v0"`.
- [x] Release manifests and build reports use `ipc_unixsocket`.

## Phase N1 — Message Authoring API

- [x] Add `app:message(name, handler)` and `app:message(name, options, handler)`.
- [ ] Add canonical table form `app:message({ name = "users.get", metadata = ..., body = ..., pipeline = ... })`.
- [x] Validate message names as dot-separated identifiers.
- [x] Store message graph nodes separately from HTTP routes.
- [x] Preserve existing handler strategies: inline Lua, Lua file/module, Zig symbol/file, and pipeline stages.

## Phase N2 — Message Graph IR

- [x] Add generated message graph arrays/types distinct from route arrays/types.
- [x] Include message metadata validators, body validators, capabilities, runtime class, source location, and handler/pipeline.
- [x] Detect duplicate message names independently from HTTP route IDs.
- [x] Graph inspection reports `messages` separately from `routes`.
- [x] Release manifests include message entries without inventing HTTP projections.

Annotation: messages are now normalized into `graph.messages`, generated as `pub const messages`, emitted into `messages.zon`, and dispatched by native IPC without entering HTTP route buckets. Shared handler/codegen paths still reuse the route-shaped Zig node type internally until a deeper type rename is worthwhile.

## Phase N3 — Native Dispatch And Context

- [x] Dispatch IPC frames only by exact `message.name`.
- [x] Populate `ctx:message()` from the matched message graph node.
- [x] Populate `ctx:metadata(name)` from IPC metadata.
- [x] Keep portable response/body helpers routed through the shared context vtable: `ctx:body`, `ctx:text`, `ctx:json`, `ctx:bytes`, `ctx:set`, `ctx:get`, `ctx:log`, `ctx:request_id`.
- [x] Gate HTTP response headers, cookies, and redirects with backend capability diagnostics.
- [x] Keep `ctx:header(name)` HTTP-only; native IPC uses `ctx:metadata(name)` instead.
- [ ] Add IPC-specific coverage for `ctx:json_body` and richer metadata/body validation failures.

Annotation: N3 now has a native message-only dispatch path. `health.get` matches only `message.name = "health.get"`; slash aliases such as `health/get` and HTTP route text such as `GET /health` return `not_found`. Lua handlers can read `ctx:message()` and `ctx:metadata("id")`; `ctx:header("id")` returns nil on `ipc_unixsocket`. HTTP-only response headers, cookies, and redirects are rejected through backend capabilities; Lua pcall failures currently surface as deterministic `internal_error` IPC responses with the specific capability error logged by the route boundary.

## Phase N4 — Validation And Observability

- [x] Validate message metadata through message schemas.
- [x] Map metadata validation failures to `validation_error` with IPC diagnostic metadata.
- [ ] Count accepted/completed messages, malformed frames, oversized frames, protocol errors, early closes, bytes read/written, active connections, and inflight messages.
- [ ] Provide IPC-safe stats/control messages without requiring HTTP.
- [ ] Validate JSON/body domains through message schemas with IPC diagnostic metadata.

Annotation: message metadata validators now run before handler dispatch. Missing/invalid metadata emits validation diagnostics as IPC metadata keys (`meteorite.validation.domain`, `meteorite.validation.field`, `meteorite.validation.reason`) and maps to the IPC `validation_error` result code, while HTTP backends keep their existing `400` + `X-Meteorite-Validation-*` contract.

## Acceptance Tests

- `app:message("health.get", ...)` serves over `ipc_unixsocket`.
- `app:get("/health", ...)` does not serve over `ipc_unixsocket`.
- IPC route bytes `GET /health` return `not_found` under `ipc_unixsocket`.
- Unknown message names return `not_found`.
- Missing/invalid metadata returns `validation_error`.
- `std_http`, `fast_http`, and `ipc_unixsocket_http` remain unaffected.
