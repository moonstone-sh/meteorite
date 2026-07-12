# IPC Unix Socket HTTP Service Fixture

Purpose: exercises the `ipc_unixsocket_http` compatibility backend shape.

This fixture intentionally uses normal HTTP route authoring (`app:get`, `app:post`, params, query, headers, JSON body validation). It should eventually run unchanged over HTTP semantics transported by a Unix socket.

Expected behavior:

- Graph generation accepts `backend = "ipc_unixsocket_http"`.
- Server compilation succeeds with HTTP/1.1 semantics over a Unix domain socket.
- Requests can be exercised with `curl --unix-socket` using normal HTTP routes, query strings, headers, and bodies.

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

This fixture is intentionally separate from `ipc-native-service`: it must not dispatch `app:message` nodes or Meteorite IPC frames.
