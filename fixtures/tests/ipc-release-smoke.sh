#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/ballad_plugin/?.lua;${ROOT}/src/ballad_plugin/?/init.lua;${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

cd "$ROOT"
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
export MOONSTONE_HOME="$ROOT/.moonstone-home"

LUA_BIN="$ROOT/.moonstone/env/bin/lua"
if [[ ! -x "$LUA_BIN" ]]; then
  echo "missing Lua runtime at $LUA_BIN; run moon sync first" >&2
  exit 1
fi

SOCK="/tmp/meteorite-ipc-native-release.sock"
RELEASE_ROOT="fixtures/apps/ipc-native-service/dist/release"
BUILD_LOG="/tmp/meteorite-ipc-native-release-ballad.log"
SERVER_LOG="/tmp/meteorite-ipc-native-release-server.log"

rm -rf fixtures/apps/ipc-native-service/dist fixtures/apps/ipc-native-service/.meteorite/release fixtures/apps/ipc-native-service/.meteorite/graph/ipc-native-release
rm -f "$SOCK" "$BUILD_LOG" "$SERVER_LOG"
moon orbit sync ipc-native-service --update >/tmp/meteorite-ipc-native-release-sync.log
(
  cd "$ROOT/fixtures/apps/ipc-native-service"
  LUA_PATH="$LUA_PROJECT_PATH" luajit "$ROOT/../ballad/src/main.lua" play partiture.lua
) >"$BUILD_LOG" 2>&1 || {
  cat "$BUILD_LOG" >&2
  exit 1
}

if [[ ! -x "$RELEASE_ROOT/bin/server" || ! -f "$RELEASE_ROOT/meteorite-release.json" ]]; then
  cat "$BUILD_LOG" >&2
  exit 1
fi
python3 - "$RELEASE_ROOT/meteorite-release.json" "$ROOT" <<'PY'
import json
import sys
manifest_text = open(sys.argv[1], encoding="utf-8").read()
manifest = json.loads(manifest_text)
root = sys.argv[2]
assert manifest["format"] == "meteorite.release.v0", manifest
assert manifest["mode"] == "hybrid", manifest
assert manifest["backend"]["name"] == "ipc_unixsocket", manifest["backend"]
assert manifest["backend"]["transport"] == "unix", manifest["backend"]
assert manifest["backend"]["protocol"] == "meteorite.ipc.v0", manifest["backend"]
assert manifest["backend"]["socket"]["mode"] == "0660", manifest["backend"]
assert manifest["backend"]["socket"]["unlink_stale"] is True, manifest["backend"]
assert manifest["messages"]["count"] >= 6, manifest["messages"]
assert "health.get" in manifest_text, manifest_text
assert "users.create" in manifest_text, manifest_text
assert root not in manifest_text, manifest_text
assert "/Users/" not in manifest_text, manifest_text
PY

deploy_root="$(mktemp -d /tmp/meteorite-ipc-release-deploy.XXXXXX)"
cp -R "$RELEASE_ROOT/." "$deploy_root/"
test -x "$deploy_root/bin/server"
test -f "$deploy_root/meteorite-release.json"

hidden_src_parent="$(mktemp -d /tmp/meteorite-ipc-release-source-hidden.XXXXXX)"
hidden_src="$hidden_src_parent/src"
restore_source() {
  if [[ -d "$hidden_src" && ! -e fixtures/apps/ipc-native-service/src ]]; then
    mv "$hidden_src" fixtures/apps/ipc-native-service/src
  fi
}
trap 'restore_source; cleanup_all' EXIT INT TERM HUP
mv fixtures/apps/ipc-native-service/src "$hidden_src"
test ! -e fixtures/apps/ipc-native-service/src

(
  cd "$deploy_root"
  "$deploy_root/bin/server" >"$SERVER_LOG" 2>&1
) &
server_pid=$!
register_pid "$server_pid"

for _ in $(seq 1 100); do
  if [[ -S "$SOCK" ]]; then break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "IPC release server exited before socket was ready" >&2
    cat "$SERVER_LOG" >&2 || true
    exit 1
  fi
  sleep 0.1
done
if [[ ! -S "$SOCK" ]]; then
  echo "IPC release server did not create $SOCK" >&2
  cat "$SERVER_LOG" >&2 || true
  exit 1
fi

health=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$SOCK" --message health.get)
case "$health" in
  *$'ok\ttext/plain; charset=utf-8\tok:health.get'*) ;;
  *) echo "unexpected release health output: $health" >&2; exit 1 ;;
esac

user=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$SOCK" --message users.get --metadata id=9 --json)
case "$user" in
  *'"result_name":"ok"'*'users.get'*) ;;
  *) echo "unexpected release user output: $user" >&2; exit 1 ;;
esac

stats=$("$LUA_BIN" src/cli/main.lua ipc stats --socket "$SOCK")
case "$stats" in
  *'"result_name":"ok"'*'accepted_total'*) ;;
  *) echo "unexpected release stats output: $stats" >&2; exit 1 ;;
esac

peer=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$SOCK" --message peer.whoami --json)
case "$peer" in
  *'"result_name":"ok"'*'has_peer'*'true'*) ;;
  *) echo "unexpected release peer output: $peer" >&2; exit 1 ;;
esac

kill "$server_pid" 2>/dev/null || true
unregister_pid "$server_pid"
wait "$server_pid" 2>/dev/null || true
restore_source
rm -f "$SOCK"

echo "ipc release smoke: ok"
