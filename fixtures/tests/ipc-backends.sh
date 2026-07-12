#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export MOONSTONE_HOME="$ROOT/.moonstone-home"
LUA_BIN="$ROOT/.moonstone/env/bin/lua"

if [[ ! -x "$LUA_BIN" ]]; then
  echo "missing Lua runtime at $LUA_BIN; run moon sync first" >&2
  exit 1
fi

NATIVE_GRAPH=".meteorite/graph/ipc-native-fixture"
HTTP_GRAPH=".meteorite/graph/ipc-http-fixture"
NATIVE_BIN="/tmp/meteorite-ipc-native-fixture-server"
HTTP_BIN="/tmp/meteorite-ipc-http-fixture-server"
NATIVE_BUILD_LOG="/tmp/meteorite-ipc-native-fixture-build.log"
HTTP_BUILD_LOG="/tmp/meteorite-ipc-http-fixture-build.log"
NATIVE_LOG="/tmp/meteorite-ipc-native-fixture-server.log"
NATIVE_SOCK="/tmp/meteorite-ipc-native-fixture.sock"

rm -rf "$NATIVE_GRAPH" "$HTTP_GRAPH"
rm -f "$NATIVE_BIN" "$HTTP_BIN" "$NATIVE_BUILD_LOG" "$HTTP_BUILD_LOG" "$NATIVE_LOG" "$NATIVE_SOCK"

"$LUA_BIN" src/cli/main.lua graph \
  fixtures/apps/ipc-native-service/src/main.lua \
  "$NATIVE_GRAPH" \
  release-hybrid \
  ipc_unixsocket >/tmp/meteorite-ipc-native-fixture-graph.log

test -f "$NATIVE_GRAPH/messages.zon"
grep -q 'health.get' "$NATIVE_GRAPH/messages.zon"
grep -q 'system.ping' "$NATIVE_GRAPH/messages.zon"
grep -q 'users.get' "$NATIVE_GRAPH/messages.zon"
grep -q 'users.create' "$NATIVE_GRAPH/messages.zon"

zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket \
  -Dgraph-input=fixtures/apps/ipc-native-service/src/main.lua \
  -Dgraph-output="$NATIVE_GRAPH" \
  -Dunix-socket-path="$NATIVE_SOCK" \
  -- "$NATIVE_BIN" >"$NATIVE_BUILD_LOG"

test -x "$NATIVE_BIN"

"$NATIVE_BIN" >"$NATIVE_LOG" 2>&1 &
server_pid=$!
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
register_pid "$server_pid"

for _ in $(seq 1 100); do
  if [[ -S "$NATIVE_SOCK" ]]; then break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "native IPC fixture server exited before socket was ready" >&2
    cat "$NATIVE_LOG" >&2 || true
    exit 1
  fi
  sleep 0.1
done
test -S "$NATIVE_SOCK"

python3 - "$NATIVE_SOCK" <<'PY'
import json
import socket
import struct
import sys

sock_path = sys.argv[1]

RESULT_OK = 0
RESULT_NOT_FOUND = 1
RESULT_VALIDATION_ERROR = 3

def recv_all(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RuntimeError("short read")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)

def send(route, metadata="", body=b"", request_id=1):
    route_bytes = route.encode()
    metadata_bytes = metadata.encode()
    if isinstance(body, str):
        body = body.encode()
    frame_len = 20 + len(route_bytes) + len(metadata_bytes) + len(body)
    frame = struct.pack("<IHHQHHI", frame_len, 0, 0, request_id, len(route_bytes), len(metadata_bytes), len(body)) + route_bytes + metadata_bytes + body
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(sock_path)
        client.sendall(frame)
        header = recv_all(client, 26)
        declared, version, flags, response_id, result, content_type_len, metadata_len, body_len = struct.unpack("<IHHQHHHI", header)
        payload = recv_all(client, content_type_len + metadata_len + body_len)
    content_type = payload[:content_type_len].decode()
    response_metadata = payload[content_type_len:content_type_len + metadata_len].decode()
    response_body = payload[content_type_len + metadata_len:].decode()
    return {
        "declared": declared,
        "version": version,
        "flags": flags,
        "request_id": response_id,
        "result": result,
        "content_type": content_type,
        "metadata": response_metadata,
        "body": response_body,
    }

def assert_equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

health = send("health.get", request_id=10)
assert_equal(health["result"], RESULT_OK, "health result")
assert_equal(health["body"], "ok:health.get", "health body")

alias = send("health/get", request_id=11)
assert_equal(alias["result"], RESULT_NOT_FOUND, "alias result")

ping = send("system.ping", request_id=12)
assert_equal(ping["result"], RESULT_OK, "canonical message result")
assert_equal(ping["body"], "pong:system.ping", "canonical message body")

missing = send("users.get", request_id=13)
assert_equal(missing["result"], RESULT_VALIDATION_ERROR, "missing metadata result")
assert "meteorite.validation.domain=metadata" in missing["metadata"]
assert "meteorite.validation.field=id" in missing["metadata"]
assert "meteorite.validation.reason=missing" in missing["metadata"]

invalid = send("users.get", "id=abc\n", request_id=14)
assert_equal(invalid["result"], RESULT_VALIDATION_ERROR, "invalid metadata result")
assert "meteorite.validation.reason=invalid" in invalid["metadata"]

user = send("users.get", "id=42\n", request_id=15)
assert_equal(user["result"], RESULT_OK, "user result")
user_body = json.loads(user["body"])
assert_equal(user_body["id"], 42, "user id")
assert_equal(user_body["message"], "users.get", "user message")
assert_equal(user_body["header_is_http_only"], True, "header separation")

malformed_json = send("users.create", "content_type=application/json\n", '{"id":', request_id=16)
assert_equal(malformed_json["result"], RESULT_VALIDATION_ERROR, "malformed json validation result")
assert "meteorite.validation.domain=json_body" in malformed_json["metadata"]
assert "meteorite.validation.field=body" in malformed_json["metadata"]
assert "meteorite.validation.reason=invalid" in malformed_json["metadata"]

bad_json = send("users.create", "content_type=application/json\n", '{"id":1}', request_id=17)
assert_equal(bad_json["result"], RESULT_VALIDATION_ERROR, "json missing field validation result")
assert "meteorite.validation.domain=json_body" in bad_json["metadata"]
assert "meteorite.validation.field=name" in bad_json["metadata"]
assert "meteorite.validation.reason=missing" in bad_json["metadata"]

invalid_json_field = send("users.create", "content_type=application/json\n", '{"id":"7","name":"alice"}', request_id=18)
assert_equal(invalid_json_field["result"], RESULT_VALIDATION_ERROR, "json invalid field validation result")
assert "meteorite.validation.domain=json_body" in invalid_json_field["metadata"]
assert "meteorite.validation.field=id" in invalid_json_field["metadata"]
assert "meteorite.validation.reason=invalid" in invalid_json_field["metadata"]

created = send("users.create", "content_type=application/json\n", '{"id":7,"name":"alice"}', request_id=19)
assert_equal(created["result"], RESULT_OK, "json create result")
created_body = json.loads(created["body"])
assert_equal(created_body["id"], 7, "created id")
assert_equal(created_body["name"], "alice", "created name")
assert_equal(created_body["message"], "users.create", "created message from ctx:json_body handler")

stats = send("meteorite.bench.stats", request_id=20)
assert_equal(stats["result"], RESULT_OK, "stats result")
stats_body = json.loads(stats["body"])
assert stats_body["accepted_total"] >= 8
assert stats_body["completed_total"] >= 7
assert stats_body["requests_served"] >= 8

reset = send("meteorite.bench.stats.reset", request_id=21)
assert_equal(reset["result"], RESULT_OK, "reset result")

meta = send("meteorite.bench.meta", request_id=22)
assert_equal(meta["result"], RESULT_OK, "meta result")
meta_body = json.loads(meta["body"])
assert_equal(meta_body["backend"], "ipc_unixsocket", "meta backend")
assert_equal(meta_body["protocol"], "meteorite.ipc.v0", "meta protocol")
PY

cli_health=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$NATIVE_SOCK" --message health.get)
case "$cli_health" in
  *$'ok	text/plain; charset=utf-8	ok:health.get'*) ;;
  *) echo "unexpected ipc cli health output: $cli_health" >&2; exit 1 ;;
esac

cli_route=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$NATIVE_SOCK" --route users/get --metadata id=42 --json)
case "$cli_route" in
  *'"result_name":"ok"'*'users.get'*) ;;
  *) echo "unexpected ipc cli route output: $cli_route" >&2; exit 1 ;;
esac

cli_created=$("$LUA_BIN" src/cli/main.lua ipc send --socket "$NATIVE_SOCK" --message users.create --content-type application/json --body '{"id":8,"name":"bob"}' --json)
case "$cli_created" in
  *'"result_name":"ok"'*'bob'*) ;;
  *) echo "unexpected ipc cli json body output: $cli_created" >&2; exit 1 ;;
esac

cli_stats=$("$LUA_BIN" src/cli/main.lua ipc stats --socket "$NATIVE_SOCK")
case "$cli_stats" in
  *'"result_name":"ok"'*'accepted_total'*) ;;
  *) echo "unexpected ipc cli stats output: $cli_stats" >&2; exit 1 ;;
esac

cli_inspect=$("$LUA_BIN" src/cli/main.lua ipc inspect --socket "$NATIVE_SOCK")
case "$cli_inspect" in
  *'"result_name":"ok"'*'ipc_unixsocket'*) ;;
  *) echo "unexpected ipc cli inspect output: $cli_inspect" >&2; exit 1 ;;
esac

kill "$server_pid" 2>/dev/null || true

"$LUA_BIN" src/cli/main.lua graph \
  fixtures/apps/ipc-unixsocket-http-service/src/main.lua \
  "$HTTP_GRAPH" \
  release-hybrid \
  ipc_unixsocket_http >/tmp/meteorite-ipc-http-fixture-graph.log

test -f "$HTTP_GRAPH/routes.zon"
grep -q '/health' "$HTTP_GRAPH/routes.zon"
grep -q '/users/:id' "$HTTP_GRAPH/routes.zon"
grep -q '/echo' "$HTTP_GRAPH/routes.zon"

set +e
zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket_http \
  -Dgraph-input=fixtures/apps/ipc-unixsocket-http-service/src/main.lua \
  -Dgraph-output="$HTTP_GRAPH" \
  -Dunix-socket-path=/tmp/meteorite-ipc-http-fixture.sock \
  -- "$HTTP_BIN" >"$HTTP_BUILD_LOG" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "expected ipc_unixsocket_http build to fail until backend implementation lands" >&2
  exit 1
fi

grep -q 'ipc_unixsocket_http is planned but not implemented' "$HTTP_BUILD_LOG"

rm -rf "$NATIVE_GRAPH" "$HTTP_GRAPH"
rm -f "$NATIVE_BIN" "$HTTP_BIN" "$NATIVE_SOCK"

echo "ipc backend fixtures: ok"
