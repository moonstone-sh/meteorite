# IPC Unix Socket HTTP Service Fixture

Purpose: captures the planned `ipc_unixsocket_http` compatibility backend shape.

This fixture intentionally uses normal HTTP route authoring (`app:get`, `app:post`, params, query, headers, JSON body validation). It should eventually run unchanged over HTTP semantics transported by a Unix socket.

Current expected behavior:

- Graph generation accepts `backend = "ipc_unixsocket_http"`.
- Server compilation fails with the intentional compile gate until the backend is implemented.
- The fixture exists so that future implementation work has a stable app contract to unlock.

Useful commands from the repository root:

```bash
lua src/cli/main.lua graph fixtures/apps/ipc-unixsocket-http-service/src/main.lua .meteorite/graph/ipc-http-fixture release-hybrid ipc_unixsocket_http
zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket_http \
  -Dgraph-input=fixtures/apps/ipc-unixsocket-http-service/src/main.lua \
  -Dgraph-output=.meteorite/graph/ipc-http-fixture \
  -Dunix-socket-path=/tmp/meteorite-ipc-http-fixture.sock
```

When `ipc_unixsocket_http` is implemented, this fixture should become a runnable black-box compatibility test mirroring the same app under `std_http`/`fast_http`.
