#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
MODE="release-static"
DURATION="30s"
CONCURRENCY="1,8,32,128,256,512"
HOST="127.0.0.1"
PORT="8080"
BIN="dist/server"
OUT=""
SERVER_PID=""
MEM_PID=""
KEEPALIVE="on"
QPS="2000"

usage() {
  cat <<USAGE
usage: bench/run.sh [options]

Options:
  --mode MODE             release-static or release-hybrid (default: release-static)
  --duration DURATION     oha/wrk duration, e.g. 30s (default: 30s)
  --concurrency LIST      comma-separated concurrency list (default: 1,8,32,128,256,512)
  --host HOST             server host (default: 127.0.0.1)
  --port PORT             server port (default: 8080)
  --bin PATH              server binary path (default: dist/server)
  --out DIR               result directory (default: bench/results/<timestamp>Z)
  --keepalive VAL         on or off (default: on)
  --qps VAL               target QPS for fixed-rate run (default: 2000)
  -h, --help              show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?missing value for --mode}"; shift 2 ;;
    --duration) DURATION="${2:?missing value for --duration}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:?missing value for --concurrency}"; shift 2 ;;
    --host) HOST="${2:?missing value for --host}"; shift 2 ;;
    --port) PORT="${2:?missing value for --port}"; shift 2 ;;
    --bin) BIN="${2:?missing value for --bin}"; shift 2 ;;
    --out) OUT="${2:?missing value for --out}"; shift 2 ;;
    --keepalive) KEEPALIVE="${2:?missing value for --keepalive}"; shift 2 ;;
    --qps) QPS="${2:?missing value for --qps}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  release-static|release-hybrid|hybrid|dev) ;;
  *) echo "unsupported mode: $MODE" >&2; exit 2 ;;
esac

if ! command -v oha >/dev/null 2>&1; then
  echo "error: oha is required for Meteorite benchmarks but was not found in PATH" >&2
  echo "install oha, then rerun: bench/run.sh --mode $MODE" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required for benchmark summarization" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required for server readiness checks" >&2
  exit 1
fi

if [[ -z "$OUT" ]]; then
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  OUT="$BENCH_DIR/results/$STAMP"
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

IFS=',' read -r -a CONCURRENCY_VALUES <<< "$CONCURRENCY"

warn() { echo "warning: $*" >&2; }

file_size() {
  local path="$1"
  local sz
  sz="$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || wc -c < "$path" 2>/dev/null || echo "0")"
  echo "${sz//[!0-9]/}"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

stop_memory_sampler() {
  if [[ -n "${MEM_PID:-}" ]]; then
    kill "$MEM_PID" 2>/dev/null || true
    wait "$MEM_PID" 2>/dev/null || true
    MEM_PID=""
  fi
}

stop_server() {
  stop_memory_sampler
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}
trap stop_server EXIT

build_server() {
  cd "$ROOT"
  echo "Building Meteorite server ($MODE)..."
  local exit_code=0
  if command -v moon >/dev/null 2>&1 && moon build --help >/dev/null 2>&1; then
    moon build --mode "$MODE" 2>&1 | tee "$OUT/build.txt"
    exit_code=${PIPESTATUS[0]}
  else
    zig build install-server -Dmode="$MODE" 2>&1 | tee "$OUT/build.txt"
    exit_code=${PIPESTATUS[0]}
  fi
  cp -r .meteorite/graph/current/routes.zon "$OUT/" 2>/dev/null || true
  cp -r .meteorite/graph/current/build-report.txt "$OUT/" 2>/dev/null || true
  return $exit_code
}

record_binary() {
  cd "$ROOT"
  if [[ ! -x "$BIN" && -x "zig-out/bin/server" ]]; then
    BIN="zig-out/bin/server"
  fi
  if [[ ! -f "$BIN" ]]; then
    echo "error: server binary not found: $BIN" >&2
    exit 1
  fi
  local bytes file_info
  bytes="$(file_size "$BIN")"
  file_info="$(file "$BIN" 2>/dev/null || true)"
  cat > "$OUT/binary.json" <<JSON
{
  "path": "$BIN",
  "bytes": $bytes,
  "file": $(printf '%s' "$file_info" | json_escape)
}
JSON
  if command -v size >/dev/null 2>&1; then
    size "$BIN" > "$OUT/binary-sections.txt" 2> "$OUT/binary-sections.err" || warn "size failed; see $OUT/binary-sections.err"
  else
    warn "size not found; skipping binary section output"
    : > "$OUT/binary-sections.txt"
  fi
}

start_server() {
  cd "$ROOT"
  "$BIN" >"$OUT/server.log" 2>&1 &
  SERVER_PID=$!

  for _ in $(seq 1 100); do
    if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done

  echo "server did not become ready" >&2
  cat "$OUT/server.log" >&2 || true
  return 1
}

start_memory_sampler() {
  "$BENCH_DIR/collect_memory.sh" "$SERVER_PID" "$OUT/memory.csv" >"$OUT/memory.log" 2>&1 &
  MEM_PID=$!
  sleep 0.3
}

run_oha_get() {
  local name="$1" path="$2" c="$3"
  echo "oha GET $path c=$c"
  local ka_arg=()
  if [[ "$KEEPALIVE" == "off" ]]; then
    ka_arg=("--disable-keepalive")
  fi
  env -u NO_COLOR oha \
    --no-tui \
    "${ka_arg[@]:+${ka_arg[@]}}" \
    --output-format json \
    -o "$OUT/${name}-oha-c${c}.json" \
    -z "$DURATION" \
    -c "$c" \
    "http://$HOST:$PORT${path}" \
    > "$OUT/${name}-oha-c${c}.log" 2>&1 || warn "oha scenario failed: $name c=$c"
}

run_oha_post() {
  local name="$1" path="$2" body="$3" c="$4"
  echo "oha POST $path c=$c"
  local ka_arg=()
  if [[ "$KEEPALIVE" == "off" ]]; then
    ka_arg=("--disable-keepalive")
  fi
  env -u NO_COLOR oha \
    --no-tui \
    "${ka_arg[@]:+${ka_arg[@]}}" \
    --output-format json \
    -o "$OUT/${name}-oha-c${c}.json" \
    -z "$DURATION" \
    -c "$c" \
    -m POST \
    -T "text/plain" \
    -D "$body" \
    "http://$HOST:$PORT${path}" \
    > "$OUT/${name}-oha-c${c}.log" 2>&1 || warn "oha scenario failed: $name c=$c"
}

run_oha_fixed() {
  local name="$1" path="$2" c="$3" qps="$4"
  echo "oha GET $path c=$c (fixed QPS=$qps)"
  local ka_arg=()
  if [[ "$KEEPALIVE" == "off" ]]; then
    ka_arg=("--disable-keepalive")
  fi
  env -u NO_COLOR oha \
    --no-tui \
    "${ka_arg[@]:+${ka_arg[@]}}" \
    --output-format json \
    -o "$OUT/${name}-oha-c${c}-q${qps}.json" \
    -z "$DURATION" \
    -c "$c" \
    -q "$qps" \
    "http://$HOST:$PORT${path}" \
    > "$OUT/${name}-oha-c${c}-q${qps}.log" 2>&1 || warn "oha fixed-rate scenario failed: $name c=$c"
}

run_oha_matrix() {
  printf 'hello meteorite' > "$OUT/body-small.txt"
  dd if=/dev/zero bs=8192 count=1 2>/dev/null | tr '\0' 'x' > "$OUT/body-8k.txt"

  for C in "${CONCURRENCY_VALUES[@]}"; do
    run_oha_get "health" "/health" "$C"
    run_oha_get "typed-param" "/users/123" "$C"
    run_oha_get "pattern-param" "/devices/router_01" "$C"
    run_oha_get "file-pattern" "/files/readme-01.txt" "$C"
    run_oha_post "echo-small" "/echo" "$OUT/body-small.txt" "$C"
    run_oha_post "echo-8k" "/echo" "$OUT/body-8k.txt" "$C"
  done
}

run_wrk_checks() {
  if ! command -v wrk >/dev/null 2>&1; then
    warn "wrk not found; skipping wrk sanity checks"
    return 0
  fi
  local wrk_ka_flag=()
  if [[ "$KEEPALIVE" == "off" ]]; then
    wrk_ka_flag=("-H" "Connection: close")
  fi
  wrk -t8 -c256 -d"$DURATION" --latency "${wrk_ka_flag[@]:+${wrk_ka_flag[@]}}" \
    "http://$HOST:$PORT/health" \
    | tee "$OUT/wrk-health-c256.txt" || true

  wrk -t8 -c256 -d"$DURATION" --latency "${wrk_ka_flag[@]:+${wrk_ka_flag[@]}}" \
    -s "$BENCH_DIR/wrk/echo.lua" \
    "http://$HOST:$PORT/echo" \
    | tee "$OUT/wrk-echo-c256.txt" || true
}

run_perf_check() {
  if ! command -v perf >/dev/null 2>&1; then
    warn "perf not found; skipping CPU counters"
    return 0
  fi
  perf stat \
    -e task-clock,context-switches,cpu-migrations,page-faults,cycles,instructions,branches,branch-misses \
    -p "$SERVER_PID" \
    -o "$OUT/perf-c256.txt" \
    -- sleep 30 > "$OUT/perf-run.log" 2>&1 &
  local perf_pid=$!

  local ka_arg=()
  if [[ "$KEEPALIVE" == "off" ]]; then
    ka_arg=("--disable-keepalive")
  fi
  env -u NO_COLOR oha \
    --no-tui \
    "${ka_arg[@]:+${ka_arg[@]}}" \
    --output-format json \
    -o "$OUT/perf-load-oha-c256.json" \
    -z 30s \
    -c 256 \
    "http://$HOST:$PORT/health" \
    > "$OUT/perf-load-oha-c256.log" 2>&1 || true

  wait "$perf_pid" || {
    warn "perf failed or permission denied; see $OUT/perf-c256.txt and $OUT/perf-run.log"
    cat "$OUT/perf-run.log" >> "$OUT/perf-c256.txt" 2>/dev/null || true
  }
}

write_bench_json() {
  cat > "$OUT/bench.json" <<JSON
{
  "mode": "$MODE",
  "duration": "$DURATION",
  "concurrency": "$CONCURRENCY",
  "host": "$HOST",
  "port": "$PORT",
  "binary": "$BIN",
  "keepalive": "$KEEPALIVE",
  "qps": "$QPS"
}
JSON
}

cd "$ROOT"
"$BENCH_DIR/collect_env.sh" "$OUT/env.json"
write_bench_json
build_server
record_binary
start_server
start_memory_sampler
run_oha_matrix
run_oha_fixed "health-fixed" "/health" "64" "$QPS"
run_wrk_checks
run_perf_check
stop_memory_sampler
stop_server

python3 "$BENCH_DIR/summarize.py" "$OUT" > "$OUT/summary.md"

cat <<DONE
Meteorite benchmark complete

Results:
  ${OUT#$ROOT/}

Summary:
  ${OUT#$ROOT/}/summary.md

Raw oha JSON:
  ${OUT#$ROOT/}/*-oha-*.json
DONE
