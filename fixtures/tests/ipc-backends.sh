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
HTTP_LOG="/tmp/meteorite-ipc-http-fixture-server.log"
HTTP_SOCK="/tmp/meteorite-ipc-http-fixture.sock"
NATIVE_LOG="/tmp/meteorite-ipc-native-fixture-server.log"
NATIVE_SOCK="/tmp/meteorite-ipc-native-fixture.sock"

rm -rf "$NATIVE_GRAPH" "$HTTP_GRAPH"
rm -f "$NATIVE_BIN" "$HTTP_BIN" "$NATIVE_BUILD_LOG" "$HTTP_BUILD_LOG" "$NATIVE_LOG" "$HTTP_LOG" "$NATIVE_SOCK" "$HTTP_SOCK"

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
grep -q 'middleware.state' "$NATIVE_GRAPH/messages.zon"
grep -q 'middleware.bytes' "$NATIVE_GRAPH/messages.zon"
grep -q 'middleware.error' "$NATIVE_GRAPH/messages.zon"

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
RESULT_MALFORMED_MESSAGE = 5
RESULT_INTERNAL_ERROR = 9

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

def send_bad_version(route, request_id=1):
    route_bytes = route.encode()
    frame_len = 20 + len(route_bytes)
    frame = struct.pack("<IHHQHHI", frame_len, 99, 0, request_id, len(route_bytes), 0, 0) + route_bytes
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(sock_path)
        client.sendall(frame)
        header = recv_all(client, 26)
        declared, version, flags, response_id, result, content_type_len, metadata_len, body_len = struct.unpack("<IHHQHHHI", header)
        payload = recv_all(client, content_type_len + metadata_len + body_len)
    return {
        "declared": declared,
        "version": version,
        "flags": flags,
        "request_id": response_id,
        "result": result,
        "content_type": payload[:content_type_len].decode(),
        "metadata": payload[content_type_len:content_type_len + metadata_len].decode(),
        "body": payload[content_type_len + metadata_len:].decode(),
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

user = send("users.get", "id=42\nquery=verbose=true\n", request_id=15)
assert_equal(user["result"], RESULT_OK, "user result")
user_body = json.loads(user["body"])
assert_equal(user_body["id"], 42, "user id")
assert_equal(user_body["param_id"], 42, "user param id")
assert_equal(user_body["query_verbose"], True, "user query verbose")
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

blocked = send("middleware.state", request_id=23)
assert_equal(blocked["result"], RESULT_OK, "middleware short-circuit result")
assert_equal(blocked["body"], "middleware:blocked", "middleware short-circuit body")

middleware_state = send("middleware.state", "allow=yes\n", request_id=24)
assert_equal(middleware_state["result"], RESULT_OK, "middleware state result")
middleware_body = json.loads(middleware_state["body"])
assert_equal(middleware_body["message"], "middleware.state", "middleware message")
assert_equal(middleware_body["state"], "ipc", "middleware state")
assert middleware_body["request_id"], "middleware request id present"

bytes_response = send("middleware.bytes", "allow=yes\n", b"abc\x00xyz", request_id=25)
assert_equal(bytes_response["result"], RESULT_OK, "bytes response result")
assert_equal(bytes_response["content_type"], "application/octet-stream", "bytes content type")
assert_equal(bytes_response["body"], "abc\x00xyz", "bytes response body")

middleware_error = send("middleware.error", request_id=26)
assert_equal(middleware_error["result"], RESULT_INTERNAL_ERROR, "middleware error boundary result")
assert_equal(middleware_error["body"], "internal server error", "middleware error body")

bad_version = send_bad_version("health.get", request_id=27)
assert_equal(bad_version["result"], RESULT_MALFORMED_MESSAGE, "bad version result")
assert_equal(bad_version["request_id"], 27, "bad version request correlation")

stats = send("meteorite.bench.stats", request_id=20)
assert_equal(stats["result"], RESULT_OK, "stats result")
stats_body = json.loads(stats["body"])
assert stats_body["accepted_total"] >= 8
assert stats_body["completed_total"] >= 7
assert stats_body["requests_served"] >= 8
assert stats_body["active_connections"] >= 1
assert stats_body["inflight_current"] >= 1
assert stats_body["bytes_read"] > 0
assert stats_body["bytes_written"] > 0
assert stats_body["protocol_errors"] >= 1
for counter in ["queue_depth", "max_queue_depth", "worker_queue_depth_max", "budget_rejections_total", "backpressure_total", "dropped_connections", "malformed_frames", "oversized_frames", "connection_errors"]:
    assert counter in stats_body, counter

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

zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=ipc_unixsocket_http \
  -Dgraph-input=fixtures/apps/ipc-unixsocket-http-service/src/main.lua \
  -Dgraph-output="$HTTP_GRAPH" \
  -Dunix-socket-path="$HTTP_SOCK" \
  -- "$HTTP_BIN" >"$HTTP_BUILD_LOG"

test -x "$HTTP_BIN"

"$HTTP_BIN" >"$HTTP_LOG" 2>&1 &
http_pid=$!
register_pid "$http_pid"

for _ in $(seq 1 100); do
  if [[ -S "$HTTP_SOCK" ]]; then break; fi
  if ! kill -0 "$http_pid" 2>/dev/null; then
    echo "HTTP-over-UDS fixture server exited before socket was ready" >&2
    cat "$HTTP_LOG" >&2 || true
    exit 1
  fi
  sleep 0.1
done
test -S "$HTTP_SOCK"

http_health=$(curl --unix-socket "$HTTP_SOCK" -fsS http://localhost/health)
test "$http_health" = "ok"

curl --unix-socket "$HTTP_SOCK" -fsS 'http://localhost/users/42?verbose=true' > /tmp/meteorite-ipc-http-users.json
python3 - /tmp/meteorite-ipc-http-users.json <<'PY'
import json, sys
body = json.load(open(sys.argv[1]))
assert body == {"id": 42, "verbose": True}, body
PY

curl --unix-socket "$HTTP_SOCK" -fsS \
  -H 'Content-Type: application/json' \
  -d '{"message":"hello"}' \
  http://localhost/echo > /tmp/meteorite-ipc-http-echo.json
python3 - /tmp/meteorite-ipc-http-echo.json <<'PY'
import json, sys
body = json.load(open(sys.argv[1]))
assert body == {"message": "hello"}, body
PY

curl --unix-socket "$HTTP_SOCK" -fsSI http://localhost/headers > /tmp/meteorite-ipc-http-headers.txt
grep -qi '^access-control-allow-origin: \*' /tmp/meteorite-ipc-http-headers.txt
grep -qi '^x-meteorite-fixture: ipc_unixsocket_http' /tmp/meteorite-ipc-http-headers.txt

curl --unix-socket "$HTTP_SOCK" -fsSI http://localhost/cookies/set > /tmp/meteorite-ipc-http-cookie.txt
grep -qi '^set-cookie: session=uds;' /tmp/meteorite-ipc-http-cookie.txt
grep -qi 'httponly' /tmp/meteorite-ipc-http-cookie.txt
grep -qi 'samesite=lax' /tmp/meteorite-ipc-http-cookie.txt

redirect_status=$(curl --unix-socket "$HTTP_SOCK" -sS -o /tmp/meteorite-ipc-http-redirect.body -w '%{http_code}' http://localhost/redirect)
test "$redirect_status" = "302"
curl --unix-socket "$HTTP_SOCK" -sSI http://localhost/redirect > /tmp/meteorite-ipc-http-redirect.txt
grep -qi '^location: /health' /tmp/meteorite-ipc-http-redirect.txt

curl --unix-socket "$HTTP_SOCK" -fsSI http://localhost/secure > /tmp/meteorite-ipc-http-secure.txt
grep -qi '^x-content-type-options: nosniff' /tmp/meteorite-ipc-http-secure.txt
grep -qi '^x-frame-options: DENY' /tmp/meteorite-ipc-http-secure.txt
grep -qi '^referrer-policy: no-referrer' /tmp/meteorite-ipc-http-secure.txt

curl --unix-socket "$HTTP_SOCK" -fsS http://localhost/static/hello.txt > /tmp/meteorite-ipc-http-static.txt
grep -q '^hello over uds$' /tmp/meteorite-ipc-http-static.txt
curl --unix-socket "$HTTP_SOCK" -fsSI http://localhost/static/hello.txt > /tmp/meteorite-ipc-http-static-headers.txt
static_etag=$(awk 'BEGIN{IGNORECASE=1} /^etag:/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' /tmp/meteorite-ipc-http-static-headers.txt)
test -n "$static_etag"
conditional_status=$(curl --unix-socket "$HTTP_SOCK" -sS -o /tmp/meteorite-ipc-http-conditional.body -w '%{http_code}' -H "If-None-Match: $static_etag" http://localhost/static/hello.txt)
test "$conditional_status" = "304"

curl --unix-socket "$HTTP_SOCK" -fsSI http://localhost/headable > /tmp/meteorite-ipc-http-head.txt
grep -qi '^x-meteorite-head: ok' /tmp/meteorite-ipc-http-head.txt
grep -qi '^content-length: 8' /tmp/meteorite-ipc-http-head.txt

curl --unix-socket "$HTTP_SOCK" -fsS http://localhost/__meteorite/info > /tmp/meteorite-ipc-http-info.json
python3 - /tmp/meteorite-ipc-http-info.json <<'PY'
import json, sys
info = json.load(open(sys.argv[1]))
assert info["backend"] == "ipc_unixsocket_http", info
assert info["transport"] == "unix", info
assert info["protocol"] == "http/1.1", info
cap = info["capabilities"]
assert cap["http_headers"] is True, cap
assert cap["cors"] is True, cap
assert cap["cookies"] is True, cap
assert cap["redirects"] is True, cap
assert cap["static_files"] is True, cap
PY

kill "$http_pid" 2>/dev/null || true

rm -rf "$NATIVE_GRAPH" "$HTTP_GRAPH"
rm -f "$NATIVE_BIN" "$HTTP_BIN" "$NATIVE_SOCK" "$HTTP_SOCK"

echo "ipc backend fixtures: ok"
