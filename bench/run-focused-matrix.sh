#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
HOST="127.0.0.1"
PORT=8080
DURATION="10"
WARMUP="3"
CONCURRENCY="1,64,512,1024"
OUT="$BENCH_DIR/results/focused-matrix-$(date -u +%Y%m%dT%H%M%SZ)"
TOOL="oha"

mkdir -p "$OUT"
IFS=',' read -ra CONCURRENCY_VALUES <<<"$CONCURRENCY"

SCENARIOS=(
  "plain|GET|/__bench/plain|-"
  "typed-param|GET|/users/123|-"
  "hybrid-inline|GET|/__bench/hybrid-inline|-"
  "echo-1k|POST|/echo|body-1k.txt"
)

dd if=/dev/zero bs=1024 count=1 2>/dev/null | tr '\0' 'x' >"$OUT/body-1k.txt"

# State tracking
SERVER_PID=""
SERVER_STATS_FILE=""
LOADGEN_PID=""
LOADGEN_STATS_FILE=""

_INTERRUPTED=0
trap '_INTERRUPTED=1' INT

check_interrupted() {
  if [[ $_INTERRUPTED -eq 1 ]]; then echo "Interrupted!" >&2; exit 130; fi
}

kill_server() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -9 "$SERVER_PID" 2>/dev/null || true
    # For cluster, kill process group
    pkill -P "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  lsof -tiTCP:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
}
trap kill_server EXIT INT TERM HUP

wait_for_server() {
  for _ in $(seq 1 100); do
    if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

# --- STATS TRACKING ---
# We track CPU sum across the process group and RSS sum.
start_stats_tracker() {
  local pid="$1"
  local log_file="$2"
  rm -f "$log_file"
  (while kill -0 "$pid" 2>/dev/null; do
    # Get total CPU and RSS for pid and its children
    # -o %cpu,rss
    local usage
    usage=$(ps -o %cpu=,rss= -g "$pid" 2>/dev/null | awk '{cpu+=$1; rss+=$2} END {print cpu, rss}')
    if [[ -n "$usage" ]]; then
      echo "$usage" >>"$log_file"
    fi
    sleep 0.5
  done) &
}

# --- VARIANTS ---
start_meteorite() {
  local workers="$1"
  echo "Building meteorite (workers=$workers)..."
  ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache-fair-matchup" \
    zig build install-server -Dmode=release-hybrid -Dfast-http-workers="$workers" -- dist/server >/dev/null 2>&1
  
  ./dist/server >"$OUT/meteorite-workers-${workers}.log" 2>&1 &
  SERVER_PID=$!
  wait_for_server
  SERVER_STATS_FILE="$OUT/meteorite-workers-${workers}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_hono() {
  local mode="$1"
  echo "Starting Hono/Bun ($mode)..."
  cd "$BENCH_DIR/competitors/hono"
  if [[ "$mode" == "single" ]]; then
    NODE_ENV=production BUN_GARBAGE_COLLECTOR_LEVEL=0 bun server.ts --port=$PORT >"$OUT/hono-single.log" 2>&1 &
  else
    NODE_ENV=production BUN_GARBAGE_COLLECTOR_LEVEL=0 bun server-cluster.ts --port=$PORT >"$OUT/hono-multiprocess.log" 2>&1 &
  fi
  SERVER_PID=$!
  cd "$ROOT"
  wait_for_server
  SERVER_STATS_FILE="$OUT/hono-${mode}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

run_scenario() {
  check_interrupted
  local name="$1" method="$2" path="$3" body_file="$4" label="$5" c="$6"
  local url="http://$HOST:$PORT$path"
  local out_file="$OUT/${label}-${name}-c${c}.json"
  local lg_stats="$OUT/loadgen-${label}-${name}-c${c}.log"
  
  if [[ "$method" == "POST" ]]; then
    local body_path="$OUT/$body_file"
    env -u NO_COLOR oha --no-tui --output-format json -z "${DURATION}s" -c "$c" -d "$body_path" -o "$out_file" "$url" >/dev/null 2>&1 &
  else
    env -u NO_COLOR oha --no-tui --output-format json -z "${DURATION}s" -c "$c" -o "$out_file" "$url" >/dev/null 2>&1 &
  fi
  
  LOADGEN_PID=$!
  start_stats_tracker "$LOADGEN_PID" "$lg_stats"
  wait "$LOADGEN_PID"
  
  local rps p99
  rps=$(python3 -c "import json; d=json.load(open('$out_file')); print(f\"{d.get('summary',{}).get('requestsPerSec',0):.1f}\")" 2>/dev/null || echo "0")
  p99=$(python3 -c "import json; d=json.load(open('$out_file')); print(f\"{d.get('latencyPercentiles',{}).get('p99',0)*1000:.3f}\")" 2>/dev/null || echo "0")
  
  # Load gen max CPU
  local lg_cpu=$(awk '{if($1>max) max=$1} END {print max}' "$lg_stats" 2>/dev/null || echo "0")
  
  printf "  %-22s c=%-4s  RPS=%-10.1f  p99=%-8.3f lg_cpu=%s%%\n" "$name" "$c" "$rps" "$p99" "$lg_cpu"
}

run_matrix_for_variant() {
  local label="$1"
  echo "--- $label ---"
  for _ in 1 2 3; do curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1 || true; done
  
  for C in "${CONCURRENCY_VALUES[@]}"; do
    for scenario in "${SCENARIOS[@]}"; do
      IFS='|' read -r name method path body_file <<<"$scenario"
      run_scenario "$name" "$method" "$path" "$body_file" "$label" "$C"
    done
  done
}

# 1. Meteorite 1-worker
kill_server
start_meteorite "1"
run_matrix_for_variant "meteorite-1worker"

# 2. Meteorite auto-workers
kill_server
start_meteorite "0"
run_matrix_for_variant "meteorite-auto"

# 3. Hono Bun Single
kill_server
start_hono "single"
run_matrix_for_variant "hono-bun-single"

# 4. Hono Bun Multiprocess
kill_server
start_hono "multiprocess"
run_matrix_for_variant "hono-bun-multiprocess"

kill_server

# ============================================================
# Generate Markdown Report
# ============================================================
echo ""
echo "=== Focused Validation Matrix ==="
python3 <<PY
import json
import os
from pathlib import Path

out = Path("$OUT")
labels = ["meteorite-1worker", "meteorite-auto", "hono-bun-single", "hono-bun-multiprocess"]
concurrency = [1, 64, 512, 1024]
scenarios = ["plain", "typed-param", "hybrid-inline", "echo-1k"]

def load_data(label, name, c):
    try:
        d = json.loads((out / f"{label}-{name}-c{c}.json").read_text())
        rps = d.get('summary', {}).get('requestsPerSec', 0)
        p50 = d.get('latencyPercentiles', {}).get('p50', 0) * 1000
        p99 = d.get('latencyPercentiles', {}).get('p99', 0) * 1000
        errors = sum(d.get('errorDistribution', {}).values()) if isinstance(d.get('errorDistribution'), dict) else d.get('errorDistribution', {}).get('errors', 0)
        
        # CPU tracking
        srv_stats = out / f"{label}-stats.log"
        srv_cpu = max([float(l.split()[0]) for l in srv_stats.read_text().strip().split('\n') if l.strip()]) if srv_stats.exists() else 0
        srv_rss = max([float(l.split()[1]) for l in srv_stats.read_text().strip().split('\n') if l.strip()]) / 1024 if srv_stats.exists() else 0
        
        lg_stats = out / f"loadgen-{label}-{name}-c{c}.log"
        lg_cpu = max([float(l.split()[0]) for l in lg_stats.read_text().strip().split('\n') if l.strip()]) if lg_stats.exists() else 0
        
        return rps, p50, p99, errors, srv_cpu, srv_rss, lg_cpu
    except Exception as e:
        return 0,0,0,0,0,0,0

for name in scenarios:
    print(f"\n## Scenario: {name}")
    print("| Variant | Concurrency | RPS | p50 (ms) | p99 (ms) | Err | Srv CPU% | Srv RSS (MB) | Oha CPU% |")
    print("|---|---|---|---|---|---|---|---|---|")
    for c in concurrency:
        for label in labels:
            rps, p50, p99, err, scpu, srss, lcpu = load_data(label, name, c)
            if rps > 0:
                print(f"| {label} | {c} | {rps:,.0f} | {p50:.2f} | {p99:.2f} | {err} | {scpu:.0f}% | {srss:.1f} | {lcpu:.0f}% |")
PY
echo "Done."
