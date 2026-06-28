#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
FAST_HTTP_WORKERS="${FAST_HTTP_WORKERS:-2}"
FAST_HTTP_QUEUE="${FAST_HTTP_QUEUE:-1024}"
BIN="${BIN:-dist/server}"
SERVER_PID=""

source "$ROOT/fixtures/tests/cleanup.sh"

cd "$ROOT"
zig build install-server \
  -Dmode=release-hybrid \
  -Dbackend=fast_http \
  -Dfast-http-strategy=pool \
  -Dfast-http-workers="$FAST_HTTP_WORKERS" \
  -Dfast-http-queue="$FAST_HTTP_QUEUE" \
  -Dhybrid-profile=optimized

"$BIN" > /tmp/meteorite-lua-state-correctness.log 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 100); do
  if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
curl -fsS "http://$HOST:$PORT/health" >/dev/null

python3 - "$HOST" "$PORT" <<'PY'
import concurrent.futures
import json
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])

def one(path):
    with socket.create_connection((host, port), timeout=2) as sock:
        sock.sendall(f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
        return read_response(sock)

def keepalive(paths):
    out = []
    with socket.create_connection((host, port), timeout=2) as sock:
        for index, path in enumerate(paths):
            connection = "close" if index == len(paths) - 1 else "keep-alive"
            sock.sendall(f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: {connection}\r\n\r\n".encode())
            out.append(read_response(sock))
    return out

def read_response(sock):
    sock.settimeout(2)
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise AssertionError("connection closed before headers")
        data += chunk
    headers, rest = data.split(b"\r\n\r\n", 1)
    header_text = headers.decode("latin1")
    status = header_text.split("\r\n", 1)[0]
    if " 200 " not in status:
        raise AssertionError(f"unexpected status {status!r}")
    length = None
    for line in header_text.split("\r\n")[1:]:
        name, _, value = line.partition(":")
        if name.lower() == "content-length":
            length = int(value.strip())
            break
    if length is None:
        raise AssertionError("missing content-length")
    while len(rest) < length:
        chunk = sock.recv(4096)
        if not chunk:
            raise AssertionError("connection closed before body")
        rest += chunk
    return rest[:length].decode()

state_id = one("/__bench/lua-debug-state")
if not state_id or state_id == "unknown":
    raise AssertionError(f"bad lua state id: {state_id!r}")

leak_results = keepalive(["/__bench/lua-state-leak"] * 8)
if leak_results != ["clean"] * 8:
    raise AssertionError(f"c.state leaked across keepalive requests: {leak_results!r}")

shared_a = int(one("/__bench/lua-shared-store"))
shared_b = int(one("/__bench/lua-shared-store"))
if shared_b <= shared_a:
    raise AssertionError(f"shared capability store did not increase globally: {shared_a}, {shared_b}")

worker_values = keepalive(["/__bench/lua-worker-store"] * 4)
worker_pairs = [value.split(":", 1) for value in worker_values]
if len({pair[0] for pair in worker_pairs}) != 1:
    raise AssertionError(f"same keepalive connection changed Lua state: {worker_values!r}")
worker_counts = [int(pair[1]) for pair in worker_pairs]
if worker_counts != sorted(worker_counts) or len(set(worker_counts)) != len(worker_counts):
    raise AssertionError(f"worker-local counter is not monotonic per state: {worker_values!r}")

require_values = keepalive(["/__bench/lua-require-cache"] * 4)
require_pairs = [value.split(":", 1) for value in require_values]
if len({pair[0] for pair in require_pairs}) != 1:
    raise AssertionError(f"same keepalive connection changed require-cache state: {require_values!r}")
require_counts = [int(pair[1]) for pair in require_pairs]
if require_counts != sorted(require_counts) or len(set(require_counts)) != len(require_counts):
    raise AssertionError(f"require cache did not persist per Lua state: {require_values!r}")

with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    global_values = list(executor.map(lambda _: one("/__bench/lua-global-counter"), range(64)))
by_state = {}
for value in global_values:
    state, count = value.split(":", 1)
    by_state.setdefault(state, []).append(int(count))
if len(by_state) < 2:
    raise AssertionError(f"expected at least two Lua states with workers=2, saw {by_state!r}")
for state, counts in by_state.items():
    ordered = sorted(counts)
    if ordered[0] < 1 or len(set(counts)) != len(counts):
        raise AssertionError(f"global counter reuse invalid for {state}: {counts!r}")

counters = json.loads(one("/__bench/counters"))
if counters.get("lua_errors") != 0:
    raise AssertionError(f"lua_errors > 0: {counters}")
if counters.get("lua_states_created", 0) > counters.get("threads_spawned", 0):
    raise AssertionError(f"lua state count exceeded worker threads: {counters}")
print(json.dumps({
    "state_id": state_id,
    "shared_counter_delta": shared_b - shared_a,
    "states_seen": len(by_state),
    "lua_states_created": counters.get("lua_states_created"),
    "lua_handler_calls": counters.get("lua_handler_calls"),
}, indent=2))
PY

curl -fsS "http://$HOST:$PORT/__bench/meta" | python3 -m json.tool
