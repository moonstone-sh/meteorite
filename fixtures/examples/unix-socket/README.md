# Unix Socket Examples

These examples show native `ipc_unixsocket` authoring with `app:message(...)`.

Build any example from the repository root by pointing the graph input at its `src/main.lua`:

```bash
zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket \
  -Dgraph-input=fixtures/examples/unix-socket/hello/src/main.lua \
  -Dunix-socket-path=/tmp/meteorite-example.sock
```

Exercise a running server with:

```bash
meteorite ipc send --socket /tmp/meteorite-example.sock --message health.get
meteorite ipc send --socket /tmp/meteorite-example.sock --route users/get --metadata id=42 --json
meteorite ipc stats --socket /tmp/meteorite-example.sock
```

Examples:

- `hello`: small text and JSON native messages.
- `json-api`: JSON body validation and `ctx:json_body()`.
- `middleware`: scoped plugins, metadata auth, request state, and body reads.
- `worker-rpc`: RPC-style message names and request logging.

Peer credential authorization is exercised by `fixtures/apps/ipc-native-service` via `peer.whoami`; these examples stay focused on message authoring patterns.
