#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Fair matchup: Meteorite (static + hybrid) vs Hono/Bun
# ============================================================
#
# Runs identical scenarios against both servers under the same
# conditions, then produces a side-by-side comparison table.
#
# Bun is tuned for maximum performance:
#   - BUN_GARBAGE_COLLECTOR_LEVEL=0 (less GC pressure)
#   - --smol is NOT used (we want full speed, not memory savings)
#   - NODE_ENV=production (disables dev-mode overhead)
#   - Bun.serve uses the native HTTP server (no Node compat layer)
#
# Meteorite is built in ReleaseFast with:
#   - fast_http backend (default) with threaded_probe strategy
#   - use --backend std_http to compare with Zig's std.http.Server
#   - param_matchers router dispatch
#   - optimized hybrid profile (for hybrid mode)
#
# Usage:
#   bash bench/run-fair-matchup.sh [options]
#
# Options:
#   --duration SECONDS   per-scenario duration (default: 10)
#   --concurrency LIST   comma-separated concurrency levels (default: 1,4,16,64,256,512)
#   --warmup SECONDS     warmup duration before measurement (default: 3)
#   --out DIR            output directory (default: bench/results/fair-matchup-<timestamp>)
#   --static-only        skip hybrid Meteorite runs
#   --hybrid-only        skip static Meteorite runs
#   --no-hono            skip Hono/Bun runs
#   --keepalive VAL      on or off (default: on)
#   --backend NAME       fast_http or std_http (default: fast_http)
#   --fast-http-strategy S  threaded_probe or pool (default: threaded_probe)
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
HOST="127.0.0.1"
PORT_METEORITE=8080
PORT_HONO=8081
DURATION="5"
WARMUP="3"
CONCURRENCY="1024"
OUT=""
KEEPALIVE="on"
BACKEND="fast_http"
FAST_HTTP_STRATEGY="threaded_probe"
RUN_STATIC=1
RUN_HYBRID=1
RUN_HONO=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="${2:?}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:?}"; shift 2 ;;
    --warmup) WARMUP="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --keepalive) KEEPALIVE="${2:?}"; shift 2 ;;
    --backend) BACKEND="${2:?}"; shift 2 ;;
    --fast-http-strategy) FAST_HTTP_STRATEGY="${2:?}"; shift 2 ;;
    --static-only) RUN_HYBRID=0; shift ;;
    --hybrid-only) RUN_STATIC=0; shift ;;
    --no-hono) RUN_HONO=0; shift ;;
    -h|--help)
      head -30 "$0" | tail -28
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! command -v oha >/dev/null 2>&1; then
  echo "error: oha is required" >&2; exit 1
fi

if [[ -z "$OUT" ]]; then
  OUT="$BENCH_DIR/results/fair-matchup-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$OUT"

IFS=',' read -ra CONCURRENCY_VALUES <<< "$CONCURRENCY"

KA_FLAG=""
if [[ "$KEEPALIVE" == "off" ]]; then
  KA_FLAG="--disable-keepalive"
fi

# ============================================================
# Scenarios: identical routes for all targets
# ============================================================
# Each scenario: name|method|path|body_file
# body_file is "-" for GET requests

SCENARIOS=(
  "health|GET|/health|-"
  "plain|GET|/__bench/plain|-"
  "raw|GET|/__bench/raw|-"
  "typed-param|GET|/users/123|-"
  "pattern-param|GET|/devices/router_01|-"
  "file-pattern|GET|/files/readme-01.txt|-"
  "hybrid-inline|GET|/__bench/hybrid-inline|-"
  "hybrid-inline-text|GET|/__bench/hybrid-inline-text-literal|-"
  "hybrid-inline-params|GET|/__bench/hybrid-inline-params/123|-"
)

# POST scenarios (body files created below)
printf 'hello meteorite' > "$OUT/body-small.txt"
dd if=/dev/zero bs=1024 count=1 2>/dev/null | tr '\0' 'x' > "$OUT/body-1k.txt"

POST_SCENARIOS=(
  "echo-small|POST|/echo|body-small.txt"
  "echo-1k|POST|/echo|body-1k.txt"
  "hybrid-inline-echo|POST|/__bench/hybrid-inline-echo|body-small.txt"
)

ALL_SCENARIOS=("${SCENARIOS[@]}" "${POST_SCENARIOS[@]}")

# ============================================================
# Server lifecycle
# ============================================================

source "$BENCH_DIR/../fixtures/tests/cleanup.sh"

# Ctrl+C should stop the entire benchmark, not just the current oha process
_INTERRUPTED=0
check_interrupted() {
  if [[ $_INTERRUPTED -eq 1 ]]; then
    echo ""
    echo "Benchmark interrupted, stopping..." >&2
    exit 130
  fi
}
trap '_INTERRUPTED=1' INT

kill_server() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -- "-$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  # Kill anything still on our ports
  lsof -tiTCP:$PORT_METEORITE 2>/dev/null | xargs kill 2>/dev/null || true
  lsof -tiTCP:$PORT_HONO 2>/dev/null | xargs kill 2>/dev/null || true
  sleep 0.3
  lsof -tiTCP:$PORT_METEORITE 2>/dev/null | xargs kill -9 2>/dev/null || true
  lsof -tiTCP:$PORT_HONO 2>/dev/null | xargs kill -9 2>/dev/null || true
}

wait_for_server() {
  local port="$1"
  local name="$2"
  for _ in $(seq 1 100); do
    if curl -fsS "http://$HOST:$port/health" >/dev/null 2>&1; then
      echo "  $name ready on :$port"
      return 0
    fi
    sleep 0.05
  done
  echo "  $name did not become ready on :$port" >&2
  cat "$OUT/$(echo $name | tr '[:upper:]' '[:lower:]' | tr -d '/')-server.log" 2>/dev/null | tail -5 >&2 || true
  return 1
}

# Kill server on failure, don't hang
start_or_skip() {
  local start_fn="$1"
  local name="$2"
  if $start_fn; then
    return 0
  else
    echo "  WARNING: $name failed to start, skipping" >&2
    kill_server
    return 1
  fi
}

# ============================================================
# Load generation
# ============================================================

run_scenario() {
  check_interrupted
  local name="$1" method="$2" path="$3" body_file="$4" port="$5" label="$6" duration="$7" c="$8"
  local url="http://$HOST:$port$path"
  local out_file="$OUT/${label}-${name}-c${c}.json"
  local log_file="$OUT/${label}-${name}-c${c}.log"

  if [[ "$method" == "POST" ]]; then
    local body_path="$OUT/$body_file"
    env -u NO_COLOR oha --no-tui --output-format json \
      -z "${duration}s" -c "$c" $KA_FLAG \
      -d "$body_path" \
      -o "$out_file" \
      "$url" > "$log_file" 2>&1 || true
  else
    env -u NO_COLOR oha --no-tui --output-format json \
      -z "${duration}s" -c "$c" $KA_FLAG \
      -o "$out_file" \
      "$url" > "$log_file" 2>&1 || true
  fi

  # Extract RPS and latency
  local rps p99
  rps=$(python3 -c "
import json
try:
  d=json.load(open('$out_file'))
  s=d.get('summary',{})
  print(f\"{s.get('requestsPerSec',0):.1f}\")
except: print('0')
" 2>/dev/null || echo "0")
  p99=$(python3 -c "
import json
try:
  d=json.load(open('$out_file'))
  lp=d.get('latencyPercentiles',{})
  print(f\"{lp.get('p99',0)*1000:.3f}\")
except: print('0')
" 2>/dev/null || echo "0")

  printf "  %-28s c=%-4s  RPS=%-10.1f  p99=%.3fms\n" "$name" "$c" "$rps" "$p99"
}

run_warmup() {
  check_interrupted
  local port="$1" label="$2"
  echo "  warming up $label..."
  for _ in $(seq 1 3); do
    curl -fsS "http://$HOST:$port/health" >/dev/null 2>&1 || true
  done
  env -u NO_COLOR oha --no-tui -z "${WARMUP}s" -c 64 \
    "http://$HOST:$port/health" >/dev/null 2>&1 || true
  env -u NO_COLOR oha --no-tui -z "${WARMUP}s" -c 64 \
    "http://$HOST:$port/__bench/plain" >/dev/null 2>&1 || true
}

run_all_scenarios() {
  check_interrupted
  local port="$1" label="$2" duration="$3"

  for C in "${CONCURRENCY_VALUES[@]}"; do
    echo ""
    echo "  --- $label @ c=$C ---"
    for scenario in "${ALL_SCENARIOS[@]}"; do
      IFS='|' read -r name method path body_file <<< "$scenario"
      # Skip hybrid routes for static builds
      if [[ "$label" == "meteorite-static" ]] && [[ "$name" == hybrid* ]]; then
        # Static build has Zig handlers for these routes, still test them
        :
      fi
      run_scenario "$name" "$method" "$path" "$body_file" "$port" "$label" "$duration" "$C"
    done
  done
}

# ============================================================
# Build Meteorite
# ============================================================

build_meteorite() {
  check_interrupted
  local mode="$1"
  local label="$2"
  echo ""
  echo "=== Building Meteorite ($label) ==="
  cd "$ROOT"

  local zig_cache="/tmp/zig-cache-fair-matchup"
  local extra_flags=""

  if [[ "$mode" == "release-hybrid" ]]; then
    extra_flags="-Dhybrid-profile=optimized"
  fi

  # std_http ignores fast-http-strategy; pass it only for fast_http
  local strategy_flags=""
  if [[ "$BACKEND" == "fast_http" ]]; then
    strategy_flags="-Dfast-http-strategy=$FAST_HTTP_STRATEGY"
  fi

  ZIG_GLOBAL_CACHE_DIR="$zig_cache" \
    zig build install-server \
      -Dmode="$mode" \
      -Dbackend="$BACKEND" \
      $strategy_flags \
      -Drouter-dispatch=param_matchers \
      $extra_flags \
      -- dist/server 2>&1 | tail -5

  echo "  Binary: $(file -b dist/server | cut -d, -f1)"
}

# ============================================================
# Start servers
# ============================================================

start_meteorite() {
  cd "$ROOT"
  ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache-fair-matchup" \
    ./dist/server > "$OUT/meteorite-server.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
}

start_hono_bun() {
  cd "$BENCH_DIR/competitors/hono"
  NODE_ENV=production \
  BUN_GARBAGE_COLLECTOR_LEVEL=0 \
    bun server.ts --port="$PORT_HONO" > "$OUT/hono-server.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
}

# ============================================================
# Capture environment
# ============================================================

capture_env() {
  {
    echo "=== Fair Matchup Environment ==="
    echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Host: $(hostname)"
    echo "OS: $(uname -srm)"
    echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'n/a')"
    echo "Cores: $(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 'n/a')"
    echo "Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB\n", $1/1024/1024/1024}' || echo 'n/a')"
    echo ""
    echo "=== Load Generator ==="
    oha --version 2>/dev/null || echo "oha version unknown"
    echo ""
    echo "=== Bun ==="
    bun --version 2>/dev/null || echo "bun not found"
    echo "BUN_GARBAGE_COLLECTOR_LEVEL=0"
    echo "NODE_ENV=production"
    echo ""
    echo "=== Zig ==="
    zig version 2>/dev/null || echo "zig not found"
    echo ""
    echo "=== Meteorite Build ==="
    echo "Mode: $1"
    echo "Backend: $BACKEND"
    if [[ "$BACKEND" == "fast_http" ]]; then
      echo "Strategy: $FAST_HTTP_STRATEGY"
    fi
    echo "Router: param_matchers"
    if [[ "$1" == "release-hybrid" ]]; then
      echo "Hybrid profile: optimized"
    fi
    echo ""
    echo "=== Scenarios ==="
    echo "Duration: ${DURATION}s per scenario"
    echo "Warmup: ${WARMUP}s"
    echo "Concurrency: $CONCURRENCY"
    echo "Keep-alive: $KEEPALIVE"
  } > "$OUT/environment.txt"
  cat "$OUT/environment.txt"
}

# ============================================================
# Main
# ============================================================

echo "============================================================"
echo "  Fair Matchup: Meteorite vs Hono/Bun"
echo "============================================================"

# Kill any existing processes on our ports
lsof -tiTCP:$PORT_METEORITE 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -tiTCP:$PORT_HONO 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 0.5

capture_env "multiple"

# --- Hono/Bun ---
if [[ "$RUN_HONO" == "1" ]]; then
  if command -v bun >/dev/null 2>&1; then
    start_hono_bun
    if wait_for_server "$PORT_HONO" "Hono/Bun"; then
          run_warmup "$PORT_HONO" "hono-bun"
      run_all_scenarios "$PORT_HONO" "hono-bun" "$DURATION"
      kill_server
      sleep 0.5
    else
      echo "WARNING: Hono/Bun failed to start, skipping" >&2
      kill_server
    fi
  else
    echo "WARNING: bun not found, skipping Hono/Bun" >&2
  fi
fi

# --- Meteorite Static ---
if [[ "$RUN_STATIC" == "1" ]]; then
  build_meteorite "release-static" "static"
  start_meteorite
  if wait_for_server "$PORT_METEORITE" "Meteorite"; then
    trap kill_server EXIT INT TERM HUP
    run_warmup "$PORT_METEORITE" "meteorite-static"
    run_all_scenarios "$PORT_METEORITE" "meteorite-static" "$DURATION"
    curl -fsS "http://$HOST:$PORT_METEORITE/__bench/counters" > "$OUT/meteorite-static-counters.json" 2>/dev/null || true
  else
    echo "WARNING: Meteorite static failed to start" >&2
  fi
  kill_server
fi

# --- Meteorite Hybrid ---
if [[ "$RUN_HYBRID" == "1" ]]; then
  build_meteorite "release-hybrid" "hybrid"
  start_meteorite
  if wait_for_server "$PORT_METEORITE" "Meteorite"; then
    trap kill_server EXIT INT TERM HUP
    run_warmup "$PORT_METEORITE" "meteorite-hybrid"
    run_all_scenarios "$PORT_METEORITE" "meteorite-hybrid" "$DURATION"
    curl -fsS "http://$HOST:$PORT_METEORITE/__bench/counters" > "$OUT/meteorite-hybrid-counters.json" 2>/dev/null || true
  else
    echo "WARNING: Meteorite hybrid failed to start" >&2
  fi
  kill_server
fi

# ============================================================
# Generate comparison table
# ============================================================

echo ""
echo "============================================================"
# Ensure all servers are stopped before generating comparison
kill_server

echo "  Comparison Summary"
echo "============================================================"
echo ""

python3 << PY
import json
from pathlib import Path

out = Path("$OUT")
concurrency = [int(x) for x in "$CONCURRENCY".split(",")]
labels = []
if $RUN_STATIC: labels.append("meteorite-static")
if $RUN_HYBRID: labels.append("meteorite-hybrid")
# Only include hono-bun if it actually ran (files exist)
import os
hono_files = [f for f in os.listdir(out) if f.startswith("hono-bun-")]
if $RUN_HONO and hono_files: labels.append("hono-bun")

scenarios = [
    ("health", "GET", "/health"),
    ("plain", "GET", "/__bench/plain"),
    ("raw", "GET", "/__bench/raw"),
    ("typed-param", "GET", "/users/123"),
    ("pattern-param", "GET", "/devices/router_01"),
    ("file-pattern", "GET", "/files/readme-01.txt"),
    ("hybrid-inline", "GET", "/__bench/hybrid-inline"),
    ("hybrid-inline-text", "GET", "/__bench/hybrid-inline-text-literal"),
    ("hybrid-inline-params", "GET", "/__bench/hybrid-inline-params/123"),
    ("echo-small", "POST", "/echo"),
    ("echo-1k", "POST", "/echo"),
    ("hybrid-inline-echo", "POST", "/__bench/hybrid-inline-echo"),
]

def load_rps(label, name, c):
    f = out / f"{label}-{name}-c{c}.json"
    try:
        d = json.loads(f.read_text())
        return d.get("summary", {}).get("requestsPerSec", 0)
    except Exception:
        return None

def load_p99(label, name, c):
    f = out / f"{label}-{name}-c{c}.json"
    try:
        d = json.loads(f.read_text())
        lp = d.get("latencyPercentiles", {})
        return lp.get("p99", 0)
    except Exception:
        return None

# Print RPS table
print("=== Requests/sec ===")
print()
header = f"{'scenario':<28s}"
for c in concurrency:
    for label in labels:
        short = label.replace("meteorite-", "m-").replace("hono-bun", "hono")
        header += f" {short}-c{c:>10}"
print(header)
print("-" * len(header))

for name, method, path in scenarios:
    row = f"{name:<28s}"
    for c in concurrency:
        for label in labels:
            rps = load_rps(label, name, c)
            if rps is not None:
                row += f" {rps:>12.0f}"
            else:
                row += f" {'—':>12s}"
    print(row)

# Print p99 latency table
print()
print("=== p99 Latency (ms) ===")
print()
header = f"{'scenario':<28s}"
for c in concurrency:
    for label in labels:
        short = label.replace("meteorite-", "m-").replace("hono-bun", "hono")
        header += f" {short}-c{c:>10}"
print(header)
print("-" * len(header))

for name, method, path in scenarios:
    row = f"{name:<28s}"
    for c in concurrency:
        for label in labels:
            p99 = load_p99(label, name, c)
            if p99 is not None:
                row += f" {p99 * 1000:>12.3f}"
            else:
                row += f" {'—':>12s}"
    print(row)

# Print ratios vs Hono/Bun
if "hono-bun" in labels and any((out / f"hono-bun-{name}-c{c}.json").exists() for name, _, _ in scenarios for c in concurrency):
    print()
    print("=== Meteorite/Hono ratio (RPS, >1.0 = Meteorite wins) ===")
    print()
    header = f"{'scenario':<28s}"
    for c in concurrency:
        header += f" {'c' + str(c):>12s}"
    print(header)
    print("-" * len(header))

    for name, method, path in scenarios:
        for mlabel in ["meteorite-static", "meteorite-hybrid"]:
            if mlabel not in labels:
                continue
            row = f"{name + ' (' + mlabel.replace('meteorite-', '') + ')':<28s}"
            for c in concurrency:
                m_rps = load_rps(mlabel, name, c)
                h_rps = load_rps("hono-bun", name, c)
                if m_rps and h_rps and h_rps > 0:
                    ratio = m_rps / h_rps
                    row += f" {ratio:>12.2f}"
                else:
                    row += f" {'—':>12s}"
            print(row)

print()
print(f"Full results: {out}")
PY

echo ""
echo "Done."
