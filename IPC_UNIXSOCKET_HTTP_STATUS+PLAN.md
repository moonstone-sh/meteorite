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
- [ ] Runtime info reports `backend = "ipc_unixsocket_http"`, `transport = "unix"`, `protocol = "http/1.1"`.
- [ ] Capabilities mirror HTTP backends: headers, CORS, cookies, redirects, static files, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow`.

Annotation: `ipc_unixsocket_http` is accepted by configuration/build metadata but intentionally fails at compile time until the HTTP/1.1-over-UDS adapter is implemented.

## Phase H1 — HTTP Adapter Over UDS

- [ ] Reuse the existing HTTP request parser/response writer path where possible.
- [ ] Replace TCP listen/accept with Unix domain socket listen/accept.
- [ ] Preserve method/path/query/header/body semantics exactly as HTTP backends do.
- [ ] Preserve response headers and status code behavior.
- [ ] Preserve keep-alive behavior where the HTTP parser supports it.

## Phase H2 — Compatibility Surface

- [ ] Existing `app:get`, `app:post`, `app:route`, `app:mount`, middleware, validators, static files, and response helpers work unchanged.
- [ ] CORS benchmark actually emits HTTP CORS headers over UDS.
- [ ] Cookie, redirect, secure-header, static-file, conditional request, and `HEAD` tests pass over UDS.
- [ ] `app:message` graph nodes are not dispatched by this backend unless a future explicit bridge is designed.

## Phase H3 — Tooling And Release

- [ ] CLI accepts `--backend ipc_unixsocket_http`.
- [ ] `meteorite doctor` validates socket config for this backend.
- [ ] Release manifests include backend, transport, protocol, safe socket config, and HTTP capabilities.
- [ ] Add local smoke tooling docs for `curl --unix-socket`.

## Acceptance Tests

- Existing HTTP fixtures pass through `ipc_unixsocket_http` using `curl --unix-socket`.
- CORS, cookies, redirects, static files, conditional requests, `HEAD`, `OPTIONS`, and `405 Allow` match `std_http` behavior.
- Native IPC frames are rejected because the wire protocol is HTTP/1.1.
- `std_http`, `fast_http`, and `ipc_unixsocket` remain unaffected.
