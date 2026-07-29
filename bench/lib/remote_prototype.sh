#!/usr/bin/env bash
# Minimal Prototype: Remote Thunderbolt Benchmark Runner
# Usage: bench/lib/remote_prototype.sh [--server-host=HOST] [--server-ip=IP] [--port=8080] [--duration=5s] [--concurrency=32]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
PORT="${PORT:-8080}"
DURATION="${DURATION:-5s}"
CONCURRENCY="${CONCURRENCY:-32}"
OUT_DIR="$ROOT/bench/results/remote-prototype-$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUT_DIR/client" "$OUT_DIR/server"

echo "=== Thunderbolt Remote Benchmark Prototype ==="
echo "Client Host: $(hostname)"
echo "Server Host: $SERVER_HOST ($SERVER_IP)"
echo "Target Port: $PORT"
echo "Output Dir:  $OUT_DIR"
echo "----------------------------------------------"

# Helper for remote command execution if SERVER_HOST is not local
remote_run() {
  if [[ "$SERVER_HOST" == "127.0.0.1" || "$SERVER_HOST" == "localhost" ]]; then
    eval "$@"
  else
    ssh "$SERVER_HOST" "$@"
  fi
}

cleanup() {
  echo "Cleaning up server processes..."
  remote_run "pkill -f 'dist/server' || true; lsof -tiTCP:$PORT | xargs kill -9 2>/dev/null || true"
}
trap cleanup EXIT INT TERM

# 1. Build and start Meteorite server on remote target
echo "[1/4] Building and launching Meteorite server on $SERVER_HOST..."
remote_run "cd '$ROOT' && PATH=\"\$HOME/.moonstone/env/bin:\$PATH\" ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache-bench zig build install-server -Dgraph-input=\"fixtures/apps/bench-service/src/main.lua\" -Dgraph-output=\".meteorite/graph/bench\" -Dmode=release-hybrid -Dhybrid-profile=optimized -Dbenchmark-instrumentation=true -Dfast-http-strategy=pool -Dfast-http-workers=0 -- dist/server"

remote_run "cd '$ROOT' && ./dist/server >/tmp/meteorite-proto-server.log 2>&1 &"

# Wait for server readiness
echo "Waiting for server at http://$SERVER_IP:$PORT/health..."
for i in $(seq 1 100); do
  if curl -fsS "http://$SERVER_IP:$PORT/health" >/dev/null 2>&1; then
    echo "Server ready!"
    break
  fi
  sleep 0.1
done

# 2. Execute oha load generator on client
echo "[2/4] Executing oha load generator from client..."
RAW_JSON="$OUT_DIR/client/meteorite_plain_c${CONCURRENCY}.json"
oha --no-tui --output-format json -c "$CONCURRENCY" -z "$DURATION" -H "Connection: keep-alive" "http://$SERVER_IP:$PORT/__bench/plain" > "$RAW_JSON"

# 3. Stop server and collect logs
cleanup

# 4. Parse and display results using Python
echo "[3/4] Parsing raw benchmark results..."
python3 - "$RAW_JSON" <<'PY'
import json, sys

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

def first(*names, default=0):
    wanted = {name.lower() for name in names}
    for d in walk(data):
        for key, value in d.items():
            if str(key).lower() in wanted and isinstance(value, (int, float)):
                return value
    return default

def duration_us(value):
    if value is None: return 0
    if isinstance(value, str):
        s = value.strip()
        try:
            if s.endswith('ms'): return float(s[:-2]) * 1000
            if s.endswith('us') or s.endswith('µs'): return float(s[:-2])
            if s.endswith('s'): return float(s[:-1]) * 1_000_000
            return float(s) * 1_000_000
        except Exception: return 0
    if isinstance(value, (int, float)): return float(value) * 1_000_000
    return 0

def percentile(name):
    wanted = {name, name.upper(), name.lower(), name.replace('p', ''), name.replace('p', '') + '.0'}
    for d in walk(data):
        for key, value in d.items():
            if str(key) in wanted:
                return duration_us(value)
    return 0

try:
    data = json.loads(open(sys.argv[1]).read())
except Exception:
    data = {}

rps = float(first('requestsPerSec', 'requests_per_sec', 'requestPerSec', 'rps', default=0))
p50 = percentile('p50') / 1000.0
p95 = percentile('p95') / 1000.0
p99 = percentile('p99') / 1000.0

print(f"\n=== Prototype Benchmark Result ===")
print(f"Scenario:  plain-zig (GET /__bench/plain)")
print(f"Req/sec:   {rps:.2f}")
print(f"p50:       {p50:.3f} ms")
print(f"p95:       {p95:.3f} ms")
print(f"p99:       {p99:.3f} ms")
PY

echo "[4/4] Prototype completed successfully. Results saved in $OUT_DIR"
