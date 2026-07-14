# Legacy Unix Socket Backend Discovery

> **Legacy / superseded.** This discovery note describes the original mixed `unix_socket` direction. The active architecture is split between `ipc_unixsocket` for native Meteorite IPC and `ipc_unixsocket_http` for HTTP/1.1 over Unix domain sockets. See `docs/ipc-unix-socket.md` and `docs/roadmap/ipc-unix-socket-http.md`.

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


---

## Legacy Unix Socket Backend Status And Plan

> Migrated from the former legacy Unix-socket backend status document during docs stabilization. Retained as historical context for backend discovery.


> **Legacy / superseded.** This mixed `unix_socket` plan is retained for historical context only. The architecture is now split into two explicit backend plans:
>
> - `docs/ipc-unix-socket.md` — native Meteorite IPC over Unix domain sockets.
> - `docs/roadmap/ipc-unix-socket-http.md` — HTTP/1.1 over Unix domain sockets.
>
> Do not continue implementation against this document except to migrate completed work into one of the split plans.

Purpose: add `unix_socket` as a first-class Meteorite backend while moving the architecture from HTTP-only routes toward a compiled route/message graph runtime. This is a phased checklist, not a claim that the backend already exists.

Last reviewed: 2026-07-10

## Release Bar Definitions

- **U0 Design Ready:** backend seams, HTTP assumptions, native-message naming, protocol limits, compatibility risks, and test strategy are documented before implementation.
- **U1 Runnable IPC Backend:** `unix_socket` can bind a UNIX domain socket, parse deterministic Meteorite IPC frames, dispatch portable handlers, and expose honest counters.
- **U2 Serious IPC Runtime:** native message names, graph metadata, Lua context compatibility, middleware/hooks, validation, release manifests, CLI tooling, peer credentials, and docs are complete enough for release.

## Architecture Principle

Meteorite should be a compiled route/message graph runtime. `std_http` and `fast_http` are HTTP protocol adapters. `unix_socket` is a local IPC protocol adapter. Lua authoring targets the Meteorite graph, not one transport.

The identity pipeline is:

```text
User authoring shape
        ↓
Graph canonical route/message identity
        ↓
Protocol/backend projection
```

That means native IPC identity is not derived privately by the `unix_socket` backend at comptime. The graph owns canonical identity, and each backend consumes the projection that matches its protocol.

Native IPC messages are first-class. HTTP-style route identity may be used for compatibility, but the graph and backend must support canonical message names such as:

```text
users/get                 -> users.get
users/create              -> users.create
cache/invalidate          -> cache.invalidate
worker/render/thumbnail   -> worker.render.thumbnail
GET /users/:id            -> users.get when explicitly named or inferred safely
```

Graph metadata should represent both the HTTP projection and the native message projection when both exist:

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

Backend projection rule:

```text
fast_http    consumes http.method + http.path
std_http     consumes http.method + http.path
unix_socket  consumes message.name / message.pattern
tooling      consumes all graph identity and metadata
```

Do not fake HTTP semantics where IPC semantics differ. HTTP headers, CORS, cookies, redirects, static files, cache validators, and conditional request behavior remain HTTP capabilities unless a safe IPC mapping is explicitly designed and documented.

## Phase U0 — Discovery And Architecture Map

- [x] Create `docs/design/unix-socket-backend-discovery.md` before backend implementation.
- [x] Document where backend selection currently happens in build, CLI, generated graph files, release tasks, and runtime server startup.
- [x] Document where `std_http` and `fast_http` share protocol/counter/request/response code.
- [x] Inventory HTTP-coupled code paths: request parsing, method/path routing, query/header/cookie/body validation, response writers, info endpoints, benchmark endpoints, and Lua ctx helpers.
- [x] Inventory graph and IR files that currently assume method/path route identity instead of message identity.
- [x] Inventory benchmark counters and mark which ones are portable, HTTP-only, or IPC-only.
- [x] Inventory release manifest fields that must record backend, protocol, transport, capabilities, and safe socket config.
- [x] Answer explicitly: existing Lua routes are mostly portable over `unix_socket` when they use portable ctx APIs; HTTP-specific helpers require diagnostics or rejection.
- [x] Add a native-message naming section covering slash-to-dot normalization, explicit message names, collision handling, and future non-HTTP message declarations.

Annotation: this phase is the guardrail against accidentally creating a second framework. It should identify the smallest shared abstraction seam that lets IPC reuse the graph without pushing UNIX socket concerns into HTTP parser code.

## Phase U1 — Backend Enum, Config, And Stub

- [x] Add `unix_socket` to the backend family everywhere valid backends are parsed or displayed.
- [x] Accept `meteorite build --backend unix_socket` and translate it to the Zig backend option.
- [x] Accept `[server] backend = "unix_socket"` and `[server.unix_socket]` config for `path`, `mode`, and `unlink_stale`.
- [x] Define config precedence as CLI flags, then project manifest, then defaults.
- [x] Emit backend metadata that can represent `backend = "unix_socket"`, `transport = "unix"`, and `protocol = "meteorite.ipc.v0"`.
- [x] Ensure diagnostics list `unix_socket`, `std_http`, and `fast_http` in a stable order.
- [x] Ensure `meteorite doctor` recognizes `unix_socket` config and reports unsafe socket paths before build.
- [x] Add a clear stub failure if `unix_socket` is selected before the listener exists.

Annotation: this phase should make `unix_socket` a valid configuration value without yet claiming it serves traffic. The correct temporary outcome is a precise “backend accepted but not implemented” diagnostic, not silent fallback to HTTP.

## Phase U2 — Native Message IR

- [x] Add graph-level route/message identity fields separate from HTTP method/path.
- [x] Make graph canonical identity the only source of truth for backend projections.
- [x] Prevent private backend-side derivation of message names from HTTP route strings.
- [x] Define canonical message names as dot-separated identifiers, for example `users.get`.
- [x] Normalize slash-style message names such as `users/get` to `users.get` at graph-build time.
- [x] Preserve HTTP route facts separately: `method`, `path`, params, query, headers, cookies, and HTTP capabilities.
- [x] Emit route records with stable `id`, `http`, `message`, `handler`, `validation`, and `capabilities` sections where applicable.
- [x] Allow explicit message identity on routes, for example a route declaration option equivalent to `message = "users.get"`.
- [x] Add safe inference for HTTP routes only when deterministic; unresolved names must remain explicit rather than guessed.
- [x] Detect message-name collisions across mounted scopes and routes with clear source diagnostics.
- [x] Include message identity in graph JSON, build reports, route inspection, and release metadata.
- [x] Ensure generated Zig route tables can dispatch by native message key as well as HTTP method/path.

Annotation: this is not just a backend convenience. Native messages are an IR concept. The backend should consume message keys from the graph rather than inventing `users.get` after dispatch has already been shaped around HTTP. Private derivation creates hidden identity drift between graph inspection, release manifests, docs, clients, and runtime behavior.

## Phase U3 — Backend-Neutral Request/Response Seam

- [x] Introduce or refine a shared request object with portable fields: `route_key`, `message`, `method`, `path`, `params`, `query`, `metadata`, `body`, `content_type`, `request_id`, and `peer`.
- [x] Introduce or refine a shared response object with portable fields: `result`, `status`, `content_type`, `metadata`, `headers`, `body`, and `close_policy`.
- [x] Keep HTTP headers and IPC metadata distinct in type names, graph metadata, and diagnostics.
- [x] Map HTTP requests into the shared request without changing existing `std_http` and `fast_http` behavior.
- [x] Map IPC frames into the shared request without pretending IPC metadata is raw HTTP headers.
- [x] Preserve existing response helpers while making `ctx:text`, `ctx:json`, and `ctx:bytes` portable.
- [x] Add backend capability facts for `http_headers`, `cookies`, `cors`, `redirects`, `ipc_metadata`, `peer_credentials`, and `static_files`.

Annotation: this phase should reduce HTTP assumptions without a risky full rewrite. HTTP backends can continue to expose HTTP features, but portable handler execution should start depending on shared request/response concepts.

Annotation: native IPC frames now populate backend-neutral request facts from message identity, metadata, body, content type, request ID, and counters. HTTP header helpers remain separate from IPC metadata; `ctx:metadata()` is the native accessor while `ctx:header()` remains HTTP-only.

## Phase U4 — Minimal UNIX Socket Listener

- [x] Add a `unix_socket` backend module that binds a UNIX domain stream socket.
- [x] Reject empty, relative-unsafe, or otherwise invalid socket paths with startup diagnostics.
- [x] Unlink stale sockets only when `unlink_stale = true` and the existing path is actually a socket.
- [x] Never unlink regular files, directories, symlinks that escape policy, or unknown filesystem objects.
- [x] Apply configured socket filesystem mode after bind.
- [x] Accept local stream connections and integrate with existing serve loop lifecycle.
- [x] Clean up the socket on shutdown where safe and document cases where cleanup is intentionally skipped.
- [x] Report safe runtime info: backend, transport, protocol, selected capabilities, and intentional socket config only.

Annotation: this phase proves the transport can start and stop safely. It does not dispatch application routes until frame parsing and request mapping are in place; the U4 listener accepts streams and closes them until U5 implements IPC frames.

## Phase U5 — Meteorite IPC Frame Parser And Writer

- [x] Implement little-endian request and response frames for `meteorite.ipc.v0`.
- [x] Define request frame layout: `u32 frame_len`, `u16 version`, `u16 flags`, `u64 request_id`, `u16 route_len`, `u16 meta_len`, `u32 body_len`, route bytes, metadata bytes, body bytes.
- [x] Define response frame layout with `request_id`, result code, content type, metadata, and body.
- [x] Enforce max frame size, route length, metadata length, body length, and version.
- [x] Support partial reads without delimiter-based parsing.
- [x] Support multiple serial request frames on one connection.
- [x] Return deterministic error frames when `request_id` is available.
- [x] Close connections safely when malformed input prevents correlation.
- [x] Count malformed frames, oversized frames, protocol errors, early closes, bytes read, and bytes written.

Annotation: the protocol is intentionally simple and deterministic. The U5 parser/writer module has unit coverage for valid frames, partial frames, oversized routes, unsupported versions, unsupported flags, and response encoding. The unix socket backend can receive serial IPC frames on one connection, return correlated error frames when the `request_id` can be recovered, close safely on uncorrelatable malformed input, and expose protocol audit counters for benchmark honesty.

## Phase U6 — Native Message Dispatch

- [x] Dispatch IPC requests by native message key first.
- [x] Support v0 compatibility mapping from route bytes such as `users/get` to graph message `users.get` only through graph-owned normalization metadata.
- [x] Support explicit compatibility mapping from `GET /users/123` only through graph metadata, not ad hoc backend parsing or backend-private inference.
- [x] Populate params from graph route patterns when an IPC message is backed by an HTTP-style route.
- [x] Populate query from explicit IPC metadata or a compatibility HTTP target string when present.
- [x] Return `not_found` for unknown message keys.
- [x] Return `method_not_allowed` only for HTTP compatibility requests where method/path semantics are actually present.
- [x] Preserve request/reply correlation with `request_id` in all success and error responses.

Annotation: IPC dispatch now prefers graph-owned native message identity (`users.get`) and only accepts slash aliases (`users/get`) through the graph message projection. `METHOD /path` is a compatibility projection handled in the shared graph dispatcher, not in the Unix socket backend. Unknown native messages return `not_found`; `method_not_allowed` is reserved for compatibility targets with method/path semantics.

## Phase U7 — Lua Context Compatibility And Diagnostics

- [x] Ensure portable APIs work under all backends: `ctx:param`, `ctx:query`, `ctx:body`, `ctx:json_body`, `ctx:text`, `ctx:json`, `ctx:bytes`, `ctx:set`, `ctx:get`, `ctx:log`, and `ctx:request_id`.
- [x] Add `ctx:message()` or equivalent portable access to the native message name.
- [x] Add `ctx:metadata(name)` or equivalent IPC-safe metadata accessor.
- [x] Keep `ctx:header` and `ctx:headers` HTTP-specific unless an explicit metadata bridge is requested.
- [x] Make CORS, cookies, redirects, secure headers, static file helpers, ETag helpers, and conditional request helpers fail clearly under `unix_socket`.
- [x] Prefer compile-time diagnostics for statically detectable backend-incompatible helpers.
- [x] Use deterministic runtime errors for dynamic helper usage that cannot be proven at graph-build time.

Annotation: the compatibility promise is “portable Meteorite routes run unchanged,” not “all HTTP features magically become IPC features.”

Annotation: native IPC fixture coverage now exercises message/metadata accessors, JSON/body helpers, binary bytes responses, request IDs, scoped plugin state via `ctx:set`/`ctx:get`, logging, and HTTP helper separation. Dynamic HTTP-only helper use is still reported through deterministic backend capability errors at the route boundary. Statically annotated hook resources now fail during graph normalization for `ipc_unixsocket` when they declare HTTP-only resources such as `request.headers` or `response.headers`.

## Phase U8 — Middleware, Hooks, Error Boundary, And Validation

- [x] Run scoped middleware and hooks for IPC requests through the same pipeline contract as HTTP.
- [x] Preserve before/after ordering, short-circuit behavior, post-handler mutation, and error boundaries.
- [x] Extend resource contracts with IPC resources: `request.message`, `request.metadata`, `request.peer`, `response.result`, and `response.metadata`.
- [x] Preserve existing HTTP resource contracts without weakening them.
- [x] Reuse params, query, body, JSON body, and schema validation where applicable.
- [x] Add metadata/envelope validation only where it is explicitly represented in graph metadata.
- [x] Map validation failures to `validation_error` with structured response metadata.
- [x] Include validator coverage and backend capability facts in graph JSON and build reports.

Annotation: middleware should be graph/pipeline behavior, not HTTP-backend behavior. HTTP-only middleware should fail clearly or require explicit backend gating.

Annotation: native IPC middleware coverage verifies scoped plugin state, plugin short-circuit responses, bytes/body handling through middleware-gated messages, and plugin error-boundary mapping to deterministic `internal_error` IPC responses. Metadata and JSON-body validation failures are asserted as structured `meteorite.validation.*` response metadata.

## Phase U9 — Observability And Benchmark Honesty

- [x] Count accepted connections and completed messages separately.
- [x] Count active connections, inflight messages, queue depth, max queue depth, worker queue max, and budget rejections.
- [x] Count backpressure, dropped connections, connection errors, malformed frames, oversized frames, protocol errors, and unauthorized peers.
- [x] Count bytes read and written at the IPC transport layer.
- [x] Add IPC-safe equivalents of bench metadata and bench stats without requiring HTTP endpoints.
- [x] Add CLI or control-message access for `meteorite ipc stats` and `meteorite ipc inspect`.
- [x] Ensure benchmark rows can distinguish throughput from admission failures, malformed messages, and backpressure.
- [x] Update benchmark claim audits to label IPC rows separately from HTTP rows.

Annotation: IPC performance claims are only valid if the counters expose queueing, rejection, and protocol-error behavior. A high RPS number without admission and completion accounting is not acceptable.

Annotation: native IPC fixture coverage now asserts stats/meta control messages over IPC, CLI `stats`/`inspect`, accepted/completed/request counters, active/inflight counters, queue/admission/backpressure fields, byte counters, and correlated protocol-error accounting from an unsupported-version frame.

Annotation: benchmark summary claim classes now derive IPC-specific labels from row metadata: `native-ipc` for `ipc_unixsocket` / `meteorite.ipc.v0` rows and `http-over-uds` for `ipc_unixsocket_http` rows. Meteorite benchmark rows also persist backend, transport, and protocol metadata when `/__bench/meta` is available.

## Phase U10 — IPC CLI Tooling

- [x] Add `meteorite ipc send --socket <path> --message users.get`.
- [x] Add compatibility send mode: `meteorite ipc send --socket <path> --route users/get` normalized to `users.get`.
- [x] Add HTTP-compat send mode: `meteorite ipc send --socket <path> --method GET --path /users/123` only for graph routes with compatibility metadata.
- [x] Add `--content-type`, `--body`, `--metadata key=value`, and `--json` output support.
- [x] Add `meteorite ipc stats --socket <path>`.
- [x] Add `meteorite ipc inspect --socket <path>` for backend/protocol/capability metadata.
- [x] Ensure CLI diagnostics distinguish unknown message, malformed response, protocol mismatch, and socket connection failure.

Annotation: `meteorite ipc` now provides a Python-backed local Unix socket client from the Lua CLI. It supports exact native messages, slash-to-dot local route normalization, explicit method/path compatibility targets, metadata/body/content-type flags, JSON output, and bench stats/meta control messages. The IPC fixture exercises send, route normalization, JSON body send, stats, and inspect against a live `ipc_unixsocket` server.

Annotation: the CLI is the developer bridge for IPC. Users should not need custom scripts to test a native-message route.

## Phase U11 — Release And Deployment

- [x] Add `backend = "ipc_unixsocket"` to release manifest output.
- [x] Include `transport = "unix"`, `protocol = "meteorite.ipc.v0"`, socket config, and backend capabilities.
- [x] Include native message names in release graph metadata without leaking source paths.
- [x] Preserve static and hybrid release validation gates.
- [x] Add copied-release smoke tests for `ipc_unixsocket` with source tree removed.
- [x] Verify copied releases can bind a configured socket and serve native-message requests.
- [x] Verify shutdown cleanup behavior matches `unlink_stale` and does not remove unsafe paths.
- [x] Add systemd, launchd, and supervisor notes for socket paths and permissions.

Annotation: releases should make IPC deployment auditable. Manifest metadata may include intentional socket config, but must not leak project roots, build directories, or host-only source paths.

Annotation: release manifest unit coverage now verifies `ipc_unixsocket` backend metadata, Unix transport/protocol facts, safe socket config, native message entries, and native capabilities. The aggregate plan uses the canonical backend spelling `ipc_unixsocket`; legacy `unix_socket` remains historical terminology only.

Annotation: `fixtures/tests/ipc-release-smoke.sh` now builds a hybrid native IPC release, copies it to a temporary deploy root, hides the source tree, starts the copied binary, exercises native messages through `meteorite ipc`, and verifies manifest/socket facts. Hybrid release asset collection now includes Lua chunks from `graph.messages`, not just HTTP routes.

## Phase U12 — Peer Credentials And Local Authorization

- [ ] Read peer credentials where the platform supports them.
- [ ] Expose safe peer facts through `ctx:peer()` and backend metadata.
- [ ] Add config for `require_peer_credentials`, `allow_uid`, and `allow_gid`.
- [ ] Fail startup when peer credentials are required but unsupported on the target platform.
- [ ] Reject unauthorized peers with deterministic `unauthorized_peer` result code.
- [ ] Count unauthorized peer attempts separately from malformed protocol errors.
- [x] Document platform differences for Linux, macOS, and unsupported targets.

Annotation: UNIX sockets have local security semantics that HTTP does not. Meteorite should expose them as IPC capabilities, not as fake headers.

## Phase U13 — Documentation And Examples

- [x] Add an IPC hello example using `users.get`-style native messages.
- [x] Add JSON API, middleware, and worker RPC examples.
- [ ] Add peer-auth example after peer credential support lands.
- [x] Document backend selection by CLI and project manifest.
- [x] Document native message naming, including slash-to-dot normalization and collision rules.
- [x] Document IPC frame basics and compatibility boundaries.
- [x] Document portable ctx APIs versus HTTP-only helpers.
- [x] Document benchmark methodology for IPC and required counters.
- [x] Document deployment with socket permissions and process supervisors.

Annotation: IPC docs now live in `docs/ipc-unix-socket.md`; native examples live under `fixtures/examples/unix-socket/`. Peer-auth remains intentionally pending until the backend exposes peer credentials and authorization policy.

Annotation: docs should teach users that changing backend is configuration, while changing from HTTP concepts to native IPC messages is an intentional graph-level capability.

## Suggested Test Matrix

- [x] `portable`: text response, JSON response, params, query, body read, JSON body validation, middleware state, short-circuit, error boundary, logging, request id.
- [x] `native_message`: explicit `users.get`, slash input `users/get`, mounted-scope normalization, collision diagnostics, route inspection, release metadata.
- [x] `http_compat`: `GET /users/:id` mapped to native message through graph metadata, query string compatibility, method mismatch behavior.
- [x] `http_only`: CORS, cookies, redirects, secure headers, raw headers, static files, conditional requests, `HEAD`, and `405 Allow`.
- [ ] `ipc_only`: frame parsing, malformed frame, oversized frame, protocol mismatch, socket permissions, stale socket unlink, request ID correlation, multiple frames, IPC metadata, peer credentials.
- [x] `benchmark`: accepted/completed, active/inflight, queue depth, budget rejections, backpressure, malformed frame count, bytes read/written, and inflight max.
- [x] `release`: static copied release, hybrid copied release, no source leaks, safe manifest socket metadata, socket cleanup behavior.

Annotation: the remaining `ipc_only` matrix gap is peer credentials. All non-peer protocol, metadata, stale socket, request-correlation, multi-frame, and malformed-frame cases are covered by `fixtures/tests/ipc-backends.sh` and `fixtures/tests/ipc-release-smoke.sh`.

## Compatibility Statement

Portable Meteorite routes should run on `std_http`, `fast_http`, or `unix_socket` without source changes when they use portable ctx APIs. Native IPC routes should use graph-level message names such as `users.get`; compatibility inputs such as `users/get` normalize to those names before backend dispatch. HTTP-only helpers remain backend-specific and must be explicit, validated, documented, and observable.

## Recommended First Sprint

- [x] Complete U0 discovery note.
- [x] Add backend enum/config stub for `unix_socket`.
- [x] Add native message identity to graph metadata and route inspection.
- [x] Define slash-to-dot normalization and collision diagnostics.
- [x] Add protocol parser/writer design tests before listener dispatch.
