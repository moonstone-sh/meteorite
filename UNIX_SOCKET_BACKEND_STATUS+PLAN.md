# Legacy Meteorite Unix Socket Backend Status + Plan

> **Legacy / superseded.** This mixed `unix_socket` plan is retained for historical context only. The architecture is now split into two explicit backend plans:
>
> - `IPC_UNIXSOCKET_NATIVE_STATUS+PLAN.md` — native Meteorite IPC over Unix domain sockets.
> - `IPC_UNIXSOCKET_HTTP_STATUS+PLAN.md` — HTTP/1.1 over Unix domain sockets.
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
- [ ] Map IPC frames into the shared request without pretending IPC metadata is raw HTTP headers.
- [x] Preserve existing response helpers while making `ctx:text`, `ctx:json`, and `ctx:bytes` portable.
- [x] Add backend capability facts for `http_headers`, `cookies`, `cors`, `redirects`, `ipc_metadata`, `peer_credentials`, and `static_files`.

Annotation: this phase should reduce HTTP assumptions without a risky full rewrite. HTTP backends can continue to expose HTTP features, but portable handler execution should start depending on shared request/response concepts.

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

- [ ] Ensure portable APIs work under all backends: `ctx:param`, `ctx:query`, `ctx:body`, `ctx:json_body`, `ctx:text`, `ctx:json`, `ctx:bytes`, `ctx:set`, `ctx:get`, `ctx:log`, and `ctx:request_id`.
- [ ] Add `ctx:message()` or equivalent portable access to the native message name.
- [ ] Add `ctx:metadata(name)` or equivalent IPC-safe metadata accessor.
- [ ] Keep `ctx:header` and `ctx:headers` HTTP-specific unless an explicit metadata bridge is requested.
- [ ] Make CORS, cookies, redirects, secure headers, static file helpers, ETag helpers, and conditional request helpers fail clearly under `unix_socket`.
- [ ] Prefer compile-time diagnostics for statically detectable backend-incompatible helpers.
- [ ] Use deterministic runtime errors for dynamic helper usage that cannot be proven at graph-build time.

Annotation: the compatibility promise is “portable Meteorite routes run unchanged,” not “all HTTP features magically become IPC features.”

## Phase U8 — Middleware, Hooks, Error Boundary, And Validation

- [ ] Run scoped middleware and hooks for IPC requests through the same pipeline contract as HTTP.
- [ ] Preserve before/after ordering, short-circuit behavior, post-handler mutation, and error boundaries.
- [ ] Extend resource contracts with IPC resources: `request.message`, `request.metadata`, `request.peer`, `response.result`, and `response.metadata`.
- [ ] Preserve existing HTTP resource contracts without weakening them.
- [ ] Reuse params, query, body, JSON body, and schema validation where applicable.
- [ ] Add metadata/envelope validation only where it is explicitly represented in graph metadata.
- [ ] Map validation failures to `validation_error` with structured response metadata.
- [ ] Include validator coverage and backend capability facts in graph JSON and build reports.

Annotation: middleware should be graph/pipeline behavior, not HTTP-backend behavior. HTTP-only middleware should fail clearly or require explicit backend gating.

## Phase U9 — Observability And Benchmark Honesty

- [ ] Count accepted connections and completed messages separately.
- [ ] Count active connections, inflight messages, queue depth, max queue depth, worker queue max, and budget rejections.
- [ ] Count backpressure, dropped connections, connection errors, malformed frames, oversized frames, protocol errors, and unauthorized peers.
- [ ] Count bytes read and written at the IPC transport layer.
- [ ] Add IPC-safe equivalents of bench metadata and bench stats without requiring HTTP endpoints.
- [ ] Add CLI or control-message access for `meteorite ipc stats` and `meteorite ipc inspect`.
- [ ] Ensure benchmark rows can distinguish throughput from admission failures, malformed messages, and backpressure.
- [ ] Update benchmark claim audits to label IPC rows separately from HTTP rows.

Annotation: IPC performance claims are only valid if the counters expose queueing, rejection, and protocol-error behavior. A high RPS number without admission and completion accounting is not acceptable.

## Phase U10 — IPC CLI Tooling

- [ ] Add `meteorite ipc send --socket <path> --message users.get`.
- [ ] Add compatibility send mode: `meteorite ipc send --socket <path> --route users/get` normalized to `users.get`.
- [ ] Add HTTP-compat send mode: `meteorite ipc send --socket <path> --method GET --path /users/123` only for graph routes with compatibility metadata.
- [ ] Add `--content-type`, `--body`, `--metadata key=value`, and `--json` output support.
- [ ] Add `meteorite ipc stats --socket <path>`.
- [ ] Add `meteorite ipc inspect --socket <path>` for backend/protocol/capability metadata.
- [ ] Ensure CLI diagnostics distinguish unknown message, malformed response, protocol mismatch, and socket connection failure.

Annotation: the CLI is the developer bridge for IPC. Users should not need custom scripts to test a native-message route.

## Phase U11 — Release And Deployment

- [ ] Add `backend = "unix_socket"` to release manifest output.
- [ ] Include `transport = "unix"`, `protocol = "meteorite.ipc.v0"`, socket config, and backend capabilities.
- [ ] Include native message names in release graph metadata without leaking source paths.
- [ ] Preserve static and hybrid release validation gates.
- [ ] Add copied-release smoke tests for `unix_socket` with source tree removed.
- [ ] Verify copied releases can bind a configured socket and serve native-message requests.
- [ ] Verify shutdown cleanup behavior matches `unlink_stale` and does not remove unsafe paths.
- [ ] Add systemd, launchd, and supervisor notes for socket paths and permissions.

Annotation: releases should make IPC deployment auditable. Manifest metadata may include intentional socket config, but must not leak project roots, build directories, or host-only source paths.

## Phase U12 — Peer Credentials And Local Authorization

- [ ] Read peer credentials where the platform supports them.
- [ ] Expose safe peer facts through `ctx:peer()` and backend metadata.
- [ ] Add config for `require_peer_credentials`, `allow_uid`, and `allow_gid`.
- [ ] Fail startup when peer credentials are required but unsupported on the target platform.
- [ ] Reject unauthorized peers with deterministic `unauthorized_peer` result code.
- [ ] Count unauthorized peer attempts separately from malformed protocol errors.
- [ ] Document platform differences for Linux, macOS, and unsupported targets.

Annotation: UNIX sockets have local security semantics that HTTP does not. Meteorite should expose them as IPC capabilities, not as fake headers.

## Phase U13 — Documentation And Examples

- [ ] Add an IPC hello example using `users.get`-style native messages.
- [ ] Add JSON API, middleware, worker RPC, and peer-auth examples.
- [ ] Document backend selection by CLI and project manifest.
- [ ] Document native message naming, including slash-to-dot normalization and collision rules.
- [ ] Document IPC frame basics and compatibility boundaries.
- [ ] Document portable ctx APIs versus HTTP-only helpers.
- [ ] Document benchmark methodology for IPC and required counters.
- [ ] Document deployment with socket permissions and process supervisors.

Annotation: docs should teach users that changing backend is configuration, while changing from HTTP concepts to native IPC messages is an intentional graph-level capability.

## Suggested Test Matrix

- [ ] `portable`: text response, JSON response, params, query, body read, JSON body validation, middleware state, short-circuit, error boundary, logging, request id.
- [ ] `native_message`: explicit `users.get`, slash input `users/get`, mounted-scope normalization, collision diagnostics, route inspection, release metadata.
- [ ] `http_compat`: `GET /users/:id` mapped to native message through graph metadata, query string compatibility, method mismatch behavior.
- [ ] `http_only`: CORS, cookies, redirects, secure headers, raw headers, static files, conditional requests, `HEAD`, and `405 Allow`.
- [ ] `ipc_only`: frame parsing, malformed frame, oversized frame, protocol mismatch, socket permissions, stale socket unlink, request ID correlation, multiple frames, IPC metadata, peer credentials.
- [ ] `benchmark`: accepted/completed, active/inflight, queue depth, budget rejections, backpressure, malformed frame count, bytes read/written, and inflight max.
- [ ] `release`: static copied release, hybrid copied release, no source leaks, safe manifest socket metadata, socket cleanup behavior.

## Compatibility Statement

Portable Meteorite routes should run on `std_http`, `fast_http`, or `unix_socket` without source changes when they use portable ctx APIs. Native IPC routes should use graph-level message names such as `users.get`; compatibility inputs such as `users/get` normalize to those names before backend dispatch. HTTP-only helpers remain backend-specific and must be explicit, validated, documented, and observable.

## Recommended First Sprint

- [x] Complete U0 discovery note.
- [x] Add backend enum/config stub for `unix_socket`.
- [x] Add native message identity to graph metadata and route inspection.
- [x] Define slash-to-dot normalization and collision diagnostics.
- [ ] Add protocol parser/writer design tests before listener dispatch.
