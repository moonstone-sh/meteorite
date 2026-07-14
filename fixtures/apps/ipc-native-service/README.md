# IPC Native Service Fixture

Purpose: exercises the native `ipc_unixsocket` backend authoring model.

This fixture intentionally uses `app:message(...)` instead of HTTP routes. It covers:

- Exact native message names such as `health.get` and `users.create`.
- Canonical table-form message authoring such as `app:message({ name = "system.ping", handler = ... })`.
- IPC metadata validation via `metadata = { id = m.u64() }`.
- JSON body validation using `content_type=application/json` IPC metadata.
- Native context APIs: `ctx:message()`, `ctx:metadata()`, `ctx:request_id()`, `ctx:peer()`.
- HTTP separation: `ctx:header("id")` is expected to be nil under native IPC.

Useful commands from the repository root:

```bash
lua src/cli/main.lua graph fixtures/apps/ipc-native-service/src/main.lua .meteorite/graph/ipc-native-fixture release-hybrid ipc_unixsocket
zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket \
  -Dgraph-input=fixtures/apps/ipc-native-service/src/main.lua \
  -Dgraph-output=.meteorite/graph/ipc-native-fixture \
  -Dunix-socket-path=/tmp/meteorite-ipc-native-fixture.sock
```

Do not use this fixture to test HTTP compatibility; that belongs to `ipc-unixsocket-http-service`.
