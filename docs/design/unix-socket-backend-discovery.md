# Legacy Unix Socket Backend Discovery

> **Legacy / superseded.** This discovery note describes the original mixed `unix_socket` direction. The active architecture is split between `ipc_unixsocket` for native Meteorite IPC and `ipc_unixsocket_http` for HTTP/1.1 over Unix domain sockets. See `IPC_UNIXSOCKET_NATIVE_STATUS+PLAN.md` and `IPC_UNIXSOCKET_HTTP_STATUS+PLAN.md`.

Last reviewed: 2026-07-10

## 1. Current Backend Architecture Summary

Meteorite currently compiles one HTTP-oriented route graph into a Zig server and selects between two HTTP backends at build time.

- Backend selection starts in `build.zig`: `-Dbackend` defaults to `fast_http` and currently accepts only `std_http` or `fast_http`.
- `build.zig` writes generated `build_info.zig` with `backend`, `fast_http_strategy`, worker, queue, Lua runtime, hybrid profile, and router dispatch facts.
- `zig/main.zig` selects the backend module with a compile-time branch over `build_info.backend`; unknown values currently fall through to `std_http` behavior once build validation is bypassed.
- `zig/meteorite.zig` exposes `backends.std_http` and `backends.fast_http`, defines the shared `ListenConfig` as `{ host, port }`, compiles the graph against one backend, and calls `App.serve`.
- `zig/backends/std_http.zig` and `zig/backends/fast_http.zig` expose the same practical backend shape: `listen`, `accept`, `receiveHead`, `method`, `path`, `query`, `header`, `readBody`, response helpers, static response helpers, raw bench response, counters, and request lifecycle helpers.
- `zig/backends/protocol.zig` is named as shared HTTP protocol code and owns `Method`, `Header`, response-header validation, cookie helpers, redirect validation, reason phrases, and backend counters.
- `src/codegen/emitter.lua` writes `runtime.zon` and `capabilities.zon` with hardcoded `fast_http` backend facts, and writes `listen.zon` as host/port config.
- `src/codegen/report.lua` emits build reports that currently print `backend: fast_http` regardless of the actual build option.
- `src/cli/main.lua` builds project servers with `-Dbackend=std_http`, and graph output prints `backend: fast_http`.
- `src/ballad/release_tasks.lua` can pass `-Dbackend=<opts.backend or std_http>`, but release manifests do not yet record backend/protocol/transport in a first-class way.

The current design is a good starting point because both HTTP backends already share a concrete shape. The main risk is that the shared shape is still HTTP-shaped rather than transport-neutral.

## 2. HTTP-Coupled Modules And Functions

### Build, Config, And Metadata

- `build.zig` validates only HTTP backends and describes the option as `HTTP backend: fast_http or std_http`.
- `zig/main.zig` selects `fast_http` or `std_http`; there is no explicit unsupported-backend runtime branch.
- `zig/meteorite.zig` exposes only HTTP backends and defines `ListenConfig` as TCP host/port.
- `src/codegen/emitter.lua` hardcodes backend facts in `runtime.zon`, `capabilities.zon`, and partition runtime metadata.
- `src/codegen/report.lua` hardcodes backend and Lua-state lines in the human build report.
- `src/cli/main.lua` hardcodes `std_http` for `meteorite build` and `meteorite dev`, while graph output reports `fast_http`.

### Request Parsing And Dispatch

- `zig/backends/std_http.zig` and `zig/backends/fast_http.zig` parse HTTP request heads and expose request data as method, path, query, header, and body.
- `zig/meteorite.zig` `serveRequest` reads `backend.method`, `backend.path`, `backend.query`, and dispatches special HTTP paths such as `/__bench/meta`, `/__bench/counters`, `/__bench/stats`, `/__meteorite/info`, and `/__meteorite/reload-lua`.
- Route matching in `zig/meteorite.zig` is method/path centered: static fast-paths, method buckets, `matchPath`, and `matchRoutePathSpecialized` all consume HTTP method and path.
- `src/cli/hybrid.lua` in-process invocation also dispatches by `method` and `path`.

### Lua Context And Helpers

- `zig/meteorite.zig` `Context` exposes `method`, `path`, `param`, `query`, `header`, `requestId`, `body`, `text`, `json`, `bytes`, response headers, redirects, and cookies.
- Response helpers stage HTTP status, content type, headers, and body, then commit through backend HTTP response writers.
- Cookie, redirect, and response-header validation live in `zig/backends/protocol.zig`, which makes the shared layer HTTP-heavy.
- `src/cli/hybrid.lua` mirrors much of the HTTP request/response model for `meteorite invoke`.

### Validation And Resources

- Normalized routes preserve HTTP request domains: params, query, headers, cookies, JSON body, and form body.
- Runtime validators in `zig/meteorite.zig` validate query, headers, cookies, JSON body, and form body through backend HTTP accessors.
- Hook/resource contracts already model phases and reads/writes, but resource names are still heavily HTTP-flavored: request method/path/query/headers and response status/headers/body.

### Static, Bench, And Runtime Info

- Static file serving is HTTP-specific and depends on path traversal rules, ETag/cache headers, conditional behavior, and `HEAD` body suppression.
- Bench support is exposed as HTTP routes under `/__bench/*` and returns HTTP JSON from `metaJson`, `countersJson`, and `buildInfoJson`.
- Bench tooling such as `bench/lib/verify.sh` expects HTTP endpoints and validates `fast_http_workers` from `/__bench/meta`.
- Runtime safe info currently reports HTTP/backend build facts and is path-addressed as `/__meteorite/info`.

### Release Metadata

- `src/ballad/release_manifest.lua` records release mode, graph hash, retained Lua nodes, static assets, runtime source, and target Lua facts.
- Static asset entries are route strings like `GET /path`, which are HTTP projection facts.
- Backend, transport, protocol, socket config, backend capabilities, and native message names are not yet manifest-level fields.

## 3. Proposed Shared Abstractions

The implementation should introduce a graph-centered identity model before the socket transport dispatches real traffic.

```text
User authoring shape
        ↓
Graph canonical route/message identity
        ↓
Protocol/backend projection
```

Graph route records should carry separate projections when both apply:

```json
{
  "id": "route.users.get",
  "http": {
    "method": "GET",
    "path": "/users/:id"
  },
  "message": {
    "name": "users.get",
    "pattern": "users.get",
    "params": ["id"]
  },
  "handler": "...",
  "validation": "...",
  "capabilities": "..."
}
```

Backend projection rules:

- `fast_http` consumes `http.method` and `http.path`.
- `std_http` consumes `http.method` and `http.path`.
- `unix_socket` consumes `message.name` and `message.pattern`.
- Tooling consumes all graph identity and metadata.

Native message identity must be graph-owned. The `unix_socket` backend must not privately derive `users.get` from `GET /users/:id` at comptime because private derivation creates hidden identity drift across graph inspection, release manifests, OpenAPI/client generation, docs, benches, and runtime behavior.

Suggested shared runtime concepts:

- `MeteoriteRequest`: `route_key`, `message`, `method?`, `path?`, `params`, `query`, `metadata`, `body`, `content_type`, `request_id`, and `peer`.
- `MeteoriteResponse`: `result`, `status?`, `content_type`, `metadata`, `headers?`, `body`, and `close_policy`.
- `MeteoriteBackend`: protocol adapter that accepts connections/messages and projects into `MeteoriteRequest`.
- `MeteoriteTransport`: TCP HTTP, UNIX stream IPC, and future transports.

HTTP headers and IPC metadata should remain separate type concepts even if the first implementation uses adapter glue to reduce churn.

## 4. Proposed Unix Socket Protocol Shape

`unix_socket` should implement Meteorite IPC over UNIX domain stream sockets, not HTTP over UNIX sockets. A future `http_unix_socket` backend can be designed separately if needed.

### Frame Defaults

- Protocol: `meteorite.ipc.v0`.
- Endianness: little-endian.
- Request frame layout: `u32 frame_len`, `u16 version`, `u16 flags`, `u64 request_id`, `u16 route_len`, `u16 meta_len`, `u32 body_len`, then route bytes, metadata bytes, and body bytes.
- Response frame layout: same prefix, then result code, content type length, metadata length, body length, content type bytes, metadata bytes, and body bytes.
- `frame_len` excludes the four bytes of `frame_len` itself.
- Max frame size: `16 MiB`.
- Max route/message bytes: `4 KiB`.
- Max metadata bytes: `64 KiB`.
- Max body size: bounded by route body limits and max frame size.
- Metadata encoding: UTF-8 key/value lines inside the metadata field, with percent-encoding for `%`, `=`, CR, LF, and NUL.
- Multiple frames per connection are allowed serially; v0 does not require pipelined concurrent responses on one connection.

### Route And Message Identity

- Preferred IPC route bytes are native graph message names such as `users.get`.
- Slash-style input such as `users/get` normalizes to `users.get` only through graph-owned normalization metadata.
- HTTP compatibility input such as `GET /users/123` is allowed only when graph metadata declares a corresponding HTTP projection and message mapping.
- Unknown message keys return `not_found`.
- `method_not_allowed` is meaningful only for HTTP compatibility requests where method/path semantics are present.

### Result Codes

- `ok`
- `not_found`
- `method_not_allowed`
- `validation_error`
- `payload_too_large`
- `malformed_message`
- `unauthorized_peer`
- `busy`
- `timeout`
- `internal_error`

### Error Behavior

- Unsupported protocol versions, non-zero unsupported flags, impossible lengths, oversized fields, and malformed metadata are protocol errors.
- If `request_id` is available, return a deterministic error response.
- If `request_id` is not safely available, close the connection and increment malformed/protocol counters.
- Partial reads continue until the frame is complete or EOF; EOF before completion increments early-close/malformed counters.
- v0 reserves `timeout` but does not require protocol-level deadline enforcement in the first listener; supervisor- or backend-level deadlines can be added later.

## 5. Compatibility Risks

- Hidden identity drift if native message names are derived only inside `unix_socket` instead of graph metadata.
- Overfitting the shared backend contract to HTTP headers/status codes, which would make IPC look like fake HTTP.
- Breaking HTTP correctness while extracting shared request/response concepts.
- Treating CORS, cookies, redirects, static files, ETags, `HEAD`, and `405 Allow` as portable when they are HTTP capabilities.
- Relying on `/__bench/*` HTTP endpoints for IPC observability, which would make IPC benchmarks unverifiable without HTTP.
- Leaking host/project source paths through socket config, runtime info, or release manifests.
- Unsafe stale socket cleanup if unlink behavior is not restricted to socket files.
- Platform differences in peer credentials: Linux, macOS, and unsupported targets need distinct capability behavior.

## 6. Test Plan

### Discovery And Config

- Verify `-Dbackend=unix_socket` is accepted only after explicit enum/config work and never falls through to `std_http`.
- Verify CLI and manifest config precedence: CLI, manifest, defaults.
- Verify graph/build reports expose backend, transport, protocol, and capabilities accurately.

### Native Message IR

- Verify explicit `message = "users.get"` route metadata.
- Verify slash-style `users/get` normalizes to `users.get` at graph build time.
- Verify collision diagnostics across mounts/scopes.
- Verify graph JSON, route inspection, build reports, and release manifests include `id`, `http`, and `message` projections.

### Protocol And Listener

- Valid frame receives correlated valid response.
- Partial frame completes correctly.
- Oversized frame returns or records `payload_too_large`.
- Malformed version/flags/lengths return or record `malformed_message`.
- Early close increments early-close/malformed counters.
- Multiple serial frames on one connection receive matching responses.
- Socket path validation, mode setting, stale unlink, and shutdown cleanup are covered.

### Portable Runtime Behavior

- Text, JSON, bytes, params, query, body, JSON body, request ID, logging, state, middleware, hooks, and error boundaries run under `std_http`, `fast_http`, and `unix_socket`.
- HTTP-only helpers fail clearly under `unix_socket`: CORS, cookies, redirects, secure headers, raw HTTP headers, static files, cache validators, conditional requests, and `HEAD` behavior.

### Observability And Release

- IPC counters distinguish accepted connections, completed messages, malformed frames, oversized frames, protocol errors, queue depth, backpressure, unauthorized peers, bytes read, and bytes written.
- IPC stats are accessible without HTTP through CLI or control messages.
- Static and hybrid copied releases can bind a socket and serve native message requests with source trees removed.

## 7. Migration / No-Migration Statement

Can an existing Lua route be served through `unix_socket` without source changes?

Mostly yes for request/response routes that use portable ctx APIs such as params, query, body, JSON body, text/json/bytes responses, request ID, state, logging, middleware, validation, and error boundaries.

No for routes that depend on HTTP-specific concepts such as CORS, cookies, redirects, raw HTTP headers, static files, ETags/cache validators, conditional requests, `HEAD`, or `405 Allow`, unless those are explicitly mapped or rejected with clear diagnostics.

The desired long-term user model is no migration for portable Meteorite routes, plus explicit graph-level native messages for IPC-first APIs. Backend selection is configuration. Protocol-specific behavior is a graph/release/runtime capability, not hidden backend behavior.
