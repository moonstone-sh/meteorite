# Meteorite HTTP-over-Unix-Socket Backend Status + Plan

Purpose: make `ipc_unixsocket_http` the HTTP-compatible Unix domain socket backend. It is real HTTP/1.1 over a Unix socket, not Meteorite IPC frames.

Last reviewed: 2026-07-11

## Architecture Principle

`ipc_unixsocket_http` is an HTTP protocol adapter with a Unix domain socket transport:

```text
app:get('/users/:id', handler)
        ↓
HTTP route graph
        ↓
ipc_unixsocket_http = HTTP/1.1 parser/writer over Unix domain sockets
```

It must preserve HTTP semantics and existing route authoring. Users switch transport by configuration, not by rewriting routes.

## Phase H0 — Backend Identity And Config

- [x] Add canonical backend value `ipc_unixsocket_http`.
- [x] Reuse Unix socket config: `path`, `mode`, `unlink_stale`.
- [x] Runtime info reports `backend = "ipc_unixsocket_http"`, `transport = "unix"`, `protocol = "http/1.1"`.
- [x] Capabilities mirror HTTP backends: headers, CORS, cookies, redirects, static files, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow`.

Annotation: `ipc_unixsocket_http` now compiles and runs as an HTTP/1.1 adapter over a Unix domain socket. Runtime info and generated capability metadata report it as Unix transport with HTTP protocol semantics, not Meteorite native IPC frames.

## Phase H1 — HTTP Adapter Over UDS

- [x] Reuse the existing HTTP request parser/response writer path where possible.
- [x] Replace TCP listen/accept with Unix domain socket listen/accept.
- [x] Preserve method/path/query/header/body semantics exactly as HTTP backends do.
- [x] Preserve response headers and status code behavior.
- [x] Preserve keep-alive behavior where the HTTP parser supports it.

Annotation: the first implementation is intentionally conservative: `zig/backends/unix_socket_http.zig` mirrors `std_http` request parsing and response writing, while swapping only the listener/accept transport for a Unix domain socket with the same socket path/mode/stale-unlink safety rules as native IPC.

## Phase H2 — Compatibility Surface

- [x] Existing `app:get`, `app:post`, validators, and response helpers work unchanged.
- [x] CORS/header smoke route emits HTTP headers over UDS.
- [ ] Cookie, redirect, secure-header, static-file, conditional request, and `HEAD` tests pass over UDS.
- [x] `app:message` graph nodes are not dispatched by this backend unless a future explicit bridge is designed.

Annotation: fixture coverage currently exercises normal HTTP routes, params, query parsing, JSON body validation, response headers, and runtime info over `curl --unix-socket`. Static files, middleware/mount breadth, cookies, redirects, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow` still need dedicated compatibility assertions.

## Phase H3 — Tooling And Release

- [x] CLI accepts `--backend ipc_unixsocket_http`.
- [x] `meteorite doctor` validates socket config for this backend.
- [x] Release manifests include backend, transport, protocol, safe socket config, and HTTP capabilities.
- [x] Add local smoke tooling docs for `curl --unix-socket`.

Annotation: build/doctor parsing already accepts `ipc_unixsocket_http` and validates Unix socket config. Release manifest unit coverage now asserts Unix transport with HTTP protocol and HTTP capabilities, while the fixture README documents local `curl --unix-socket` usage.

## Acceptance Tests

- Existing HTTP fixtures pass through `ipc_unixsocket_http` using `curl --unix-socket`.
- CORS, cookies, redirects, static files, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow` match `std_http` behavior.
- Native IPC frames are rejected because the wire protocol is HTTP/1.1.
- `std_http`, `fast_http`, and `ipc_unixsocket` remain unaffected.
