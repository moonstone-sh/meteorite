#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
HOST="127.0.0.1"
PORT=8080
DURATION="10"
WARMUP="3"
CONCURRENCY="1,64,512,1024"
THREADS="10"
OUT="$BENCH_DIR/results/wrk-matrix-$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$OUT"
IFS=',' read -ra CONCURRENCY_VALUES <<<"$CONCURRENCY"

SCENARIOS=(
  "plain|GET|/__bench/plain"
  "typed-param|GET|/users/123"
  "hybrid-inline|GET|/__bench/hybrid-inline"
  "echo-1k|POST|/echo"
)

cat <<EOF >"$OUT/post.lua"
wrk.method = "POST"
wrk.body = string.rep("x", 1024)
EOF

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

get_descendants() {
  local pid=$1
  echo "$pid"
  pgrep -P "$pid" 2>/dev/null | while read -r child; do
    get_descendants "$child"
  done
}

start_stats_tracker() {
  local pid="$1"
  local log_file="$2"
  rm -f "$log_file"
  (while kill -0 "$pid" 2>/dev/null; do
    local all_pids
    all_pids=$(get_descendants "$pid" | paste -sd, -)
    if [[ -n "$all_pids" ]]; then
      local usage
      usage=$(ps -p "$all_pids" -o %cpu=,rss= 2>/dev/null | awk '{cpu+=$1; rss+=$2} END {print cpu, rss}')
      if [[ -n "$usage" ]]; then
        echo "$usage" >>"$log_file"
      fi
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
  local name="$1" method="$2" path="$3" label="$4" c="$5"
  local url="http://$HOST:$PORT$path"
  local out_file="$OUT/${label}-${name}-c${c}.log"
  local lg_stats="$OUT/loadgen-${label}-${name}-c${c}.log"
  
  local active_threads=$THREADS
  if (( c < active_threads )); then
    active_threads=$c
  fi
  
  if [[ "$method" == "POST" ]]; then
    wrk -t "$active_threads" -c "$c" -d "${DURATION}s" -s "$OUT/post.lua" --latency "$url" >"$out_file" 2>&1 &
  else
    wrk -t "$active_threads" -c "$c" -d "${DURATION}s" --latency "$url" >"$out_file" 2>&1 &
  fi
  
  LOADGEN_PID=$!
  start_stats_tracker "$LOADGEN_PID" "$lg_stats"
  wait "$LOADGEN_PID"
  
  local rps p99
  rps=$(grep "Requests/sec:" "$out_file" | awk '{print $2}' || echo "0")
  p99=$(grep "99%" "$out_file" | awk '{print $2}' || echo "0")
  
  local lg_cpu=$(awk '{if($1>max) max=$1} END {print max}' "$lg_stats" 2>/dev/null || echo "0")
  
  printf "  %-22s c=%-4s  RPS=%-10s  p99=%-8s lg_cpu=%s%%\n" "$name" "$c" "$rps" "$p99" "$lg_cpu"
}

run_matrix_for_variant() {
  local label="$1"
  echo "--- $label ---"
  for _ in 1 2 3; do curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1 || true; done
  
  for C in "${CONCURRENCY_VALUES[@]}"; do
    for scenario in "${SCENARIOS[@]}"; do
      IFS='|' read -r name method path <<<"$scenario"
      run_scenario "$name" "$method" "$path" "$label" "$C"
    done
  done
}

kill_server
start_meteorite "1"
run_matrix_for_variant "meteorite-1worker"

kill_server
start_meteorite "0"
run_matrix_for_variant "meteorite-auto"

kill_server
start_hono "single"
run_matrix_for_variant "hono-bun-single"

kill_server
start_hono "multiprocess"
run_matrix_for_variant "hono-bun-multiprocess"

kill_server

echo ""
echo "=== WRK Validation Matrix ==="
python3 <<PY
import os
import re
from pathlib import Path

out = Path("$OUT")
labels = ["meteorite-1worker", "meteorite-auto", "hono-bun-single", "hono-bun-multiprocess"]
concurrency = [1, 64, 512, 1024]
scenarios = ["plain", "typed-param", "hybrid-inline", "echo-1k"]

def parse_ms(val):
    if val.endswith('ms'): return float(val[:-2])
    if val.endswith('s'): return float(val[:-1]) * 1000
    if val.endswith('us'): return float(val[:-2]) / 1000
    return 0.0

def load_data(label, name, c):
    try:
        text = (out / f"{label}-{name}-c{c}.log").read_text()
        
        rps_match = re.search(r"Requests/sec:\s+([\d\.]+)", text)
        rps = float(rps_match.group(1)) if rps_match else 0
        
        p50_match = re.search(r"50%\s+([\d\.]+ms|[\d\.]+s|[\d\.]+us)", text)
        p50 = parse_ms(p50_match.group(1)) if p50_match else 0
        
        p99_match = re.search(r"99%\s+([\d\.]+ms|[\d\.]+s|[\d\.]+us)", text)
        p99 = parse_ms(p99_match.group(1)) if p99_match else 0
        
        err_match = re.search(r"Non-2xx or 3xx responses: (\d+)|Socket errors: .* (connect \d+, read \d+, write \d+, timeout \d+)", text)
        err = 1 if err_match else 0 # Rough error check for wrk
        
        srv_stats = out / f"{label}-stats.log"
        srv_cpu = max([float(l.split()[0]) for l in srv_stats.read_text().strip().split('\n') if l.strip()] + [0])
        srv_rss = max([float(l.split()[1]) for l in srv_stats.read_text().strip().split('\n') if l.strip()] + [0]) / 1024
        
        lg_stats = out / f"loadgen-{label}-{name}-c{c}.log"
        lg_cpu = max([float(l.split()[0]) for l in lg_stats.read_text().strip().split('\n') if l.strip()] + [0])
        
        return rps, p50, p99, err, srv_cpu, srv_rss, lg_cpu
    except Exception as e:
        return 0,0,0,0,0,0,0

for name in scenarios:
    print(f"\n## Scenario: {name}")
    print("| Variant | Concurrency | RPS | p50 (ms) | p99 (ms) | Srv CPU% | Srv RSS (MB) | Wrk CPU% |")
    print("|---|---|---|---|---|---|---|---|")
    for c in concurrency:
        for label in labels:
            rps, p50, p99, err, scpu, srss, lcpu = load_data(label, name, c)
            if rps > 0:
                print(f"| {label} | {c} | {rps:,.0f} | {p50:.2f} | {p99:.2f} | {scpu:.0f}% | {srss:.1f} | {lcpu:.0f}% |")
PY
echo "Done."
