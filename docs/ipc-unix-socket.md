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
