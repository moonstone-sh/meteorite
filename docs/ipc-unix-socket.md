# Meteorite IPC over Unix Sockets

Meteorite now has two Unix-socket backends with intentionally different semantics:

| Backend | Transport | Protocol | Authoring model |
|---|---|---|---|
| `ipc_unixsocket` | Unix domain stream socket | `meteorite.ipc.v0` | Native `app:message(...)` graph messages |
| `ipc_unixsocket_http` | Unix domain stream socket | HTTP/1.1 | Existing `app:get`, `app:post`, static files, CORS, cookies, redirects |

Use `ipc_unixsocket` for local IPC/message APIs. Use `ipc_unixsocket_http` when you need existing HTTP routes to remain HTTP-compatible while moving the listener from TCP to a Unix socket.

## Backend Selection

CLI build selection:

```bash
meteorite build --backend ipc_unixsocket \
  --unix-socket-path /tmp/meteorite.sock \
  --unix-socket-mode 0660

meteorite build --backend ipc_unixsocket_http \
  --unix-socket-path /tmp/meteorite-http.sock
```

Project manifest selection:

```toml
[server]
backend = "ipc_unixsocket"

[server.ipc_unixsocket]
path = "/tmp/meteorite.sock"
mode = "0660"
unlink_stale = true
```

`meteorite doctor` validates Unix socket paths and modes for both Unix backends. Socket paths must be absolute. Stale unlinking only removes an existing Unix-domain socket; regular files and other unsafe paths are rejected.

## Native Message Naming

Native IPC does not privately derive route identity inside the backend. Message identity is graph-owned:

```lua
local m = require("meteorite")
local app = m.app()

app:message("users.get", {
  metadata = { id = m.u64() },
}, function(ctx)
  return ctx:json({ id = tonumber(ctx:param("id")) })
end)

return app
```

Message names are dot-separated identifiers such as `users.get`, `cache.invalidate`, or `worker.render.thumbnail`. The CLI accepts slash form as local tooling sugar:

```bash
meteorite ipc send --socket /tmp/meteorite.sock --route users/get --metadata id=42
```

The slash form is normalized to `users.get` by the CLI. The native backend itself dispatches exact graph message names and does not treat `GET /users/42` as a native message unless an explicit compatibility path is used.

## IPC Frame Basics

`ipc_unixsocket` uses deterministic length-prefixed frames. Request frames are little-endian:

```text
u32 frame_len
u16 version
u16 flags
u64 request_id
u16 route_len
u16 meta_len
u32 body_len
route bytes
metadata bytes
body bytes
```

Response frames carry:

```text
request_id
result_code
content_type
metadata
body
```

Result codes are Meteorite IPC result codes, not raw HTTP status codes: `ok`, `not_found`, `method_not_allowed`, `validation_error`, `payload_too_large`, `malformed_message`, `unauthorized_peer`, `busy`, `timeout`, and `internal_error`.

## Portable Context APIs

These APIs are portable across HTTP and native IPC when the route/message provides the relevant data:

```lua
ctx:param(name)
ctx:query(name)
ctx:body()
ctx:json_body()
ctx:text(body_or_status, ...)
ctx:json(value, ...)
ctx:bytes(status, content_type, body, ...)
ctx:set(key, value)
ctx:get(key)
ctx:log(level, message, fields, opts)
ctx:request_id()
```

Native IPC also exposes:

```lua
ctx:message()        -- current graph message name
ctx:metadata(name)   -- IPC metadata value
```

HTTP-only helpers remain HTTP-only under `ipc_unixsocket`: CORS, cookies, redirects, secure headers, raw HTTP headers, static files, ETag/cache helpers, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow`. Use `ipc_unixsocket_http` when those semantics are required.

## Manual Testing

Native IPC:

```bash
meteorite ipc send --socket /tmp/meteorite.sock --message health.get
meteorite ipc send --socket /tmp/meteorite.sock --message users.get --metadata id=42 --json
meteorite ipc stats --socket /tmp/meteorite.sock
meteorite ipc inspect --socket /tmp/meteorite.sock
```

HTTP over Unix socket:

```bash
curl --unix-socket /tmp/meteorite-http.sock http://localhost/health
curl --unix-socket /tmp/meteorite-http.sock -I http://localhost/static/hello.txt
```

## Benchmark Requirements

IPC benchmark rows must report more than throughput. Claim-grade rows need accepted/completed counters, active/inflight counts, queue depth, max queue depth, worker queue max, budget rejections, backpressure, malformed/oversized/protocol errors, dropped/connection errors, and bytes read/written.

`ipc_unixsocket` exposes safe control messages for metadata and stats:

```text
meteorite.bench.meta
meteorite.bench.stats
meteorite.bench.stats.reset
```

The CLI wraps these as `meteorite ipc inspect` and `meteorite ipc stats` so native IPC benchmarks do not require HTTP endpoints.

## Deployment Notes

For systemd, launchd, or another supervisor:

- Put sockets in a supervisor-managed runtime directory such as `/run/meteorite/meteorite.sock` on Linux or a controlled app runtime directory on macOS.
- Use `mode = "0660"` and group ownership to limit local clients.
- Enable `unlink_stale = true` only for the intended socket path.
- Do not place sockets inside source/build directories.
- Treat `ipc_unixsocket_http` as HTTP from an application-security perspective, even though the transport is local.

Peer credential authorization is planned separately. Until that lands, use filesystem permissions, process supervision, and OS user/group ownership as the local access boundary.

## Peer Credential Portability

Peer credentials are platform-specific and remain a planned IPC capability, not a current authorization boundary:

- Linux exposes Unix-socket peer credentials through `SO_PEERCRED` (`pid`, `uid`, `gid`).
- macOS and BSD-family systems expose similar but not identical local peer facts through platform-specific socket APIs such as `LOCAL_PEERCRED`/`getpeereid`.
- Unsupported targets must fail startup if peer credentials are required by config, rather than silently allowing all peers.
- `-Drequire-peer-credentials=true` is already fail-closed: because peer credential reading is not implemented yet, startup returns `PeerCredentialsUnsupported` instead of serving unauthenticated peers.
- Release manifests record planned peer policy fields (`require_peer_credentials`, `peer_allow_uid`, `peer_allow_gid`) under backend socket metadata for auditability.
- Until Meteorite exposes `ctx:peer()` and enforces `allow_uid` / `allow_gid`, deploy with filesystem permissions and supervisor-owned runtime directories.


---

## Native IPC Status And Plan

> Migrated from the former native IPC status document during docs stabilization.


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
- [x] Add canonical table form `app:message({ name = "users.get", metadata = ..., body = ..., pipeline = ... })`.
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

Annotation: canonical table-form messages now lower through the canonical route contract with an internal message route projection, preserving metadata/body/pipeline fields while still landing in `graph.messages` instead of HTTP route buckets.

## Phase N3 — Native Dispatch And Context

- [x] Dispatch IPC frames only by exact `message.name`.
- [x] Populate `ctx:message()` from the matched message graph node.
- [x] Populate `ctx:metadata(name)` from IPC metadata.
- [x] Keep portable response/body helpers routed through the shared context vtable: `ctx:body`, `ctx:text`, `ctx:json`, `ctx:bytes`, `ctx:set`, `ctx:get`, `ctx:log`, `ctx:request_id`.
- [x] Gate HTTP response headers, cookies, and redirects with backend capability diagnostics.
- [x] Keep `ctx:header(name)` HTTP-only; native IPC uses `ctx:metadata(name)` instead.
- [x] Add IPC-specific coverage for `ctx:json_body` and richer metadata/body validation failures.

Annotation: N3 now has a native message-only dispatch path. `health.get` matches only `message.name = "health.get"`; slash aliases such as `health/get` and HTTP route text such as `GET /health` return `not_found`. Lua handlers can read `ctx:message()` and `ctx:metadata("id")`; `ctx:header("id")` returns nil on `ipc_unixsocket`. HTTP-only response headers, cookies, and redirects are rejected through backend capabilities; Lua pcall failures currently surface as deterministic `internal_error` IPC responses with the specific capability error logged by the route boundary.

Annotation: IPC fixture coverage now asserts malformed JSON, missing JSON fields, invalid JSON field types, successful `ctx:json_body()` parsing, and structured `meteorite.validation.*` response metadata for native IPC messages.

## Phase N4 — Validation And Observability

- [x] Validate message metadata through message schemas.
- [x] Map metadata validation failures to `validation_error` with IPC diagnostic metadata.
- [x] Count accepted/completed messages, malformed frames, oversized frames, protocol errors, early closes, bytes read/written, active connections, and inflight messages.
- [x] Provide IPC-safe stats/control messages without requiring HTTP.
- [x] Validate JSON/body domains through message schemas with IPC diagnostic metadata.

Annotation: message metadata validators now run before handler dispatch. Missing/invalid metadata emits validation diagnostics as IPC metadata keys (`meteorite.validation.domain`, `meteorite.validation.field`, `meteorite.validation.reason`) and maps to the IPC `validation_error` result code, while HTTP backends keep their existing `400` + `X-Meteorite-Validation-*` contract.

Annotation: IPC observability now uses request/message-level `accepted_total`, `completed_total`, `requests_served`, active/inflight counters, byte counters, malformed/oversized/protocol/early-close counters, and resettable audit counters. Native control messages `meteorite.bench.meta`, `meteorite.bench.stats`, and `meteorite.bench.stats.reset` expose the existing safe JSON metadata/stats path over IPC without requiring an HTTP endpoint.

Annotation: IPC JSON validation accepts `content_type=application/json` metadata as the transport-native equivalent of HTTP `Content-Type`. JSON body validation keeps the HTTP `json` validation domain for HTTP backends and emits `json_body` in IPC diagnostic metadata.

## Acceptance Tests

- [x] `app:message("health.get", ...)` serves over `ipc_unixsocket`.
- [x] Slash-style aliases such as `health/get` return `not_found` under `ipc_unixsocket`.
- [x] Missing/invalid metadata returns `validation_error` with IPC diagnostic metadata.
- [x] JSON body validation returns `validation_error` with `json_body` diagnostic metadata.
- [x] Native control messages expose stats/meta/reset over IPC.
- [x] `ipc_unixsocket_http` fixture remains graph-valid and compile-gated until implementation lands.

Annotation: `fixtures/tests/ipc-backends.sh` now builds and runs `fixtures/apps/ipc-native-service`, sends real `meteorite.ipc.v0` frames over a Unix socket, verifies message dispatch/validation/control-message behavior, and verifies the planned `ipc_unixsocket_http` fixture still reaches the intentional compile gate.
