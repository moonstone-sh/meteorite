#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
TARGET="meteorite"
MODE="release-static"
BACKEND="std_http"
FAST_HTTP_STRATEGY="threaded_probe"
FAST_HTTP_WORKERS="0"
FAST_HTTP_QUEUE="1024"
ROUTER_DISPATCH="method_buckets"
HYBRID_PROFILE="default"
DURATION="30s"
CONCURRENCY="1,8,32,128,256,512"
STRICT_P99_BASELINE_MS="${STRICT_P99_BASELINE_MS:-}"
STRICT_P99_FACTOR="${STRICT_P99_FACTOR:-2.0}"
HOST="127.0.0.1"
PORT="8080"
BIN="dist/server"
OUT=""
SERVER_PID=""
MEM_PID=""
SAMPLE_PID=""
KEEPALIVE="on"
QPS="2000"
STRICT_BENCH=""
STRICT_FAIL_DIRTY=""

usage() {
  cat <<USAGE
usage: bench/run.sh [options]

Options:
  --target TARGET         meteorite | hono-bun | hono-node (default: meteorite)
  --mode MODE             release-static or release-hybrid, for Meteorite only (default: release-static)
  --backend BACKEND       std_http or fast_http, for Meteorite only (default: std_http)
  --fast-http-strategy S  threaded_probe or pool (default: threaded_probe)
  --fast-http-workers N   pool workers; 0 means CPU count (default: 0)
  --fast-http-queue N     pool queue limit (default: 1024)
  --router-dispatch MODE  method_buckets, static_fast_path, param_matchers, or legacy_scan (default: method_buckets)
  --hybrid-profile PROF   default | optimized, for Meteorite release-hybrid only (default: default)
  --duration DURATION     oha/wrk duration, e.g. 30s (default: 30s)
  --concurrency LIST      comma-separated concurrency list (default: 1,8,32,128,256,512)
  --host HOST             server host (default: 127.0.0.1)
  --port PORT             server port (default: 8080)
  --bin PATH              server binary path, for Meteorite only (default: dist/server)
  --out DIR               result directory (default: bench/results/<timestamp>Z)
  --keepalive VAL         on or off (default: on)
  --qps VAL               target QPS for fixed-rate run (default: 2000)
  --strict-bench          fail on Debug build or keepalive mismatch
  --strict-bench-fail-dirty  also fail if git working directory is dirty

Environment gates:
  STRICT_P99_BASELINE_MS  optional focused-baseline p99 threshold source, in ms
  STRICT_P99_FACTOR       max p99 factor over baseline (default: 2.0)
  -h, --help              show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:?missing value for --target}"; shift 2 ;;
    --mode) MODE="${2:?missing value for --mode}"; shift 2 ;;
    --backend) BACKEND="${2:?missing value for --backend}"; shift 2 ;;
    --fast-http-strategy) FAST_HTTP_STRATEGY="${2:?missing value for --fast-http-strategy}"; shift 2 ;;
    --fast-http-workers) FAST_HTTP_WORKERS="${2:?missing value for --fast-http-workers}"; shift 2 ;;
    --fast-http-queue) FAST_HTTP_QUEUE="${2:?missing value for --fast-http-queue}"; shift 2 ;;
    --router-dispatch) ROUTER_DISPATCH="${2:?missing value for --router-dispatch}"; shift 2 ;;
    --hybrid-profile) HYBRID_PROFILE="${2:?missing value for --hybrid-profile}"; shift 2 ;;
    --duration) DURATION="${2:?missing value for --duration}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:?missing value for --concurrency}"; shift 2 ;;
    --host) HOST="${2:?missing value for --host}"; shift 2 ;;
    --port) PORT="${2:?missing value for --port}"; shift 2 ;;
    --bin) BIN="${2:?missing value for --bin}"; shift 2 ;;
    --out) OUT="${2:?missing value for --out}"; shift 2 ;;
    --keepalive) KEEPALIVE="${2:?missing value for --keepalive}"; shift 2 ;;
    --qps) QPS="${2:?missing value for --qps}"; shift 2 ;;
    --strict-bench) STRICT_BENCH=1; shift ;;
    --strict-bench-fail-dirty) STRICT_BENCH=1; STRICT_FAIL_DIRTY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$TARGET" in
  meteorite|hono-bun|hono-node) ;;
  *) echo "unsupported target: $TARGET" >&2; usage >&2; exit 2 ;;
esac

case "$MODE" in
  release-static|release-hybrid|hybrid|dev) ;;
  *) echo "unsupported mode: $MODE" >&2; exit 2 ;;
esac

case "$HYBRID_PROFILE" in
  default|optimized|baseline|per-worker-lua) ;;
  *) echo "unsupported hybrid-profile: $HYBRID_PROFILE" >&2; exit 2 ;;
esac

case "$BACKEND" in
  std_http|fast_http) ;;
  *) echo "unsupported backend: $BACKEND" >&2; exit 2 ;;
esac

case "$FAST_HTTP_STRATEGY" in
  threaded_probe|pool) ;;
  *) echo "unsupported fast-http-strategy: $FAST_HTTP_STRATEGY" >&2; exit 2 ;;
esac

case "$ROUTER_DISPATCH" in
  method_buckets|static_fast_path|param_matchers|legacy_scan) ;;
  *) echo "unsupported router-dispatch: $ROUTER_DISPATCH" >&2; exit 2 ;;
esac

if ! command -v oha >/dev/null 2>&1; then
  echo "error: oha is required for benchmarks but was not found in PATH" >&2
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

stop_macos_sampler() {
  if [[ -n "${SAMPLE_PID:-}" ]]; then
    wait "$SAMPLE_PID" 2>/dev/null || true
    SAMPLE_PID=""
  fi
}

stop_server() {
  stop_macos_sampler
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
  if [[ "$TARGET" != meteorite ]]; then
    return 0
  fi
  echo "Building Meteorite server ($MODE, backend=$BACKEND, fast-http-strategy=$FAST_HTTP_STRATEGY, router-dispatch=$ROUTER_DISPATCH, hybrid-profile=$HYBRID_PROFILE)..."
  local exit_code=0
  if command -v zig >/dev/null 2>&1; then
    zig build install-server -Dgraph-input="fixtures/apps/bench-service/src/main.lua" -Dmode="$MODE" -Dbackend="$BACKEND" -Dfast-http-strategy="$FAST_HTTP_STRATEGY" -Dfast-http-workers="$FAST_HTTP_WORKERS" -Dfast-http-queue="$FAST_HTTP_QUEUE" -Drouter-dispatch="$ROUTER_DISPATCH" -Dhybrid-profile="$HYBRID_PROFILE" 2>&1 | tee "$OUT/build.txt"
    exit_code=${PIPESTATUS[0]}
  else
    echo "error: zig is required to build the server" >&2
    exit 1
  fi
  cp -r .meteorite/graph/current/routes.zon "$OUT/" 2>/dev/null || true
  cp -r .meteorite/graph/current/build-report.txt "$OUT/" 2>/dev/null || true
  return $exit_code
}

record_binary() {
  cd "$ROOT"
  if [[ "$TARGET" != meteorite ]]; then
    cat > "$OUT/binary.json" <<JSON
{
  "path": "n/a",
  "bytes": 0,
  "file": ""
}
JSON
    return 0
  fi
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
  local os_name
  os_name="$(uname -s)"
  stat -f%z "$BIN" > "$OUT/binary-file-size.txt" 2>/dev/null || stat -c%s "$BIN" > "$OUT/binary-file-size.txt" 2>/dev/null || true
  if command -v size >/dev/null 2>&1; then
    if [[ "$os_name" == "Darwin" ]]; then
      size -m "$BIN" > "$OUT/binary-size-raw.txt" 2> "$OUT/binary-size-raw.err" || true
    else
      size "$BIN" > "$OUT/binary-sections.txt" 2> "$OUT/binary-sections.err" || warn "size failed; see $OUT/binary-sections.err"
    fi
  else
    warn "size not found; skipping binary section output"
    : > "$OUT/binary-sections.txt"
  fi
}

start_server() {
  cd "$ROOT"
  if [[ "$TARGET" == meteorite ]]; then
    "$BIN" >"$OUT/server.log" 2>&1 &
    SERVER_PID=$!
  elif [[ "$TARGET" == hono-bun ]]; then
    cd "$BENCH_DIR/competitors/hono"
    bun server.ts --port="$PORT" >"$OUT/server.log" 2>&1 &
    SERVER_PID=$!
  elif [[ "$TARGET" == hono-node ]]; then
    cd "$BENCH_DIR/competitors/hono"
    node server-node.mjs --port="$PORT" >"$OUT/server.log" 2>&1 &
    SERVER_PID=$!
  fi

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

start_runtime_artifacts() {
  if [[ -z "${SERVER_PID:-}" ]]; then
    return 0
  fi
  ps -p "$SERVER_PID" -o pid,ppid,pcpu,rss,vsz,etime,command > "$OUT/ps-before.txt" 2>&1 || warn "ps before snapshot failed"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] && command -v sample >/dev/null 2>&1; then
    sample "$SERVER_PID" 5 -file "$OUT/sample-5s.txt" > "$OUT/sample-5s.log" 2>&1 &
    SAMPLE_PID=$!
  fi
}

capture_post_runtime_artifacts() {
  if [[ -z "${SERVER_PID:-}" ]]; then
    return 0
  fi
  ps -p "$SERVER_PID" -o pid,ppid,pcpu,rss,vsz,etime,command > "$OUT/ps-after.txt" 2>&1 || warn "ps after snapshot failed"
  curl -fsS "http://$HOST:$PORT/__bench/counters" > "$OUT/backend-counters.json" 2> "$OUT/backend-counters.log" || warn "could not capture backend counters"
}

sample_inline_route() {
  if [[ -z "${SERVER_PID:-}" ]]; then
    return 0
  fi
  if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]] || ! command -v sample >/dev/null 2>&1; then
    return 0
  fi
  sample "$SERVER_PID" 5 -file "$OUT/sample-hybrid-inline-5s.txt" > "$OUT/sample-hybrid-inline-5s.log" 2>&1 &
  local sample_pid=$!
  env -u NO_COLOR oha --no-tui --output-format json -o "$OUT/hybrid-inline-sample-oha-c256.json" -z 5s -c 256 "http://$HOST:$PORT/__bench/hybrid-inline" > "$OUT/hybrid-inline-sample-oha-c256.log" 2>&1 || warn "hybrid-inline sample load failed"
  wait "$sample_pid" 2>/dev/null || true
}

strict_fail() {
  echo "strict-bench failure: $*" >&2
  exit 3
}

probe_keepalive() {
  echo "Probing keep-alive behavior..."
  curl -v "http://$HOST:$PORT/health" > "$OUT/curl-health.txt" 2>&1 || warn "health probe curl failed"
  env -u NO_COLOR oha --no-tui -z 10s -c 128 --output-format json -o "$OUT/keepalive-on-smoke.json" "http://$HOST:$PORT/health" > "$OUT/keepalive-on-smoke.log" 2>&1 || warn "keepalive-on smoke failed"
  env -u NO_COLOR oha --no-tui -z 10s -c 128 --disable-keepalive --output-format json -o "$OUT/keepalive-off-smoke.json" "http://$HOST:$PORT/health" > "$OUT/keepalive-off-smoke.log" 2>&1 || warn "keepalive-off smoke failed"
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
    run_oha_get "plain-native" "/__bench/plain" "$C"
    run_oha_get "raw-native" "/__bench/raw" "$C"
    run_oha_get "plain-static" "/__bench/plain-static" "$C"
    run_oha_get "hybrid-zig" "/__bench/hybrid-zig" "$C"
    run_oha_get "hybrid-inline-bench" "/__bench/hybrid-inline" "$C"
    run_oha_get "hybrid-inline-text-literal" "/__bench/hybrid-inline-text-literal" "$C"
    run_oha_get "hybrid-inline-params" "/__bench/hybrid-inline-params/123" "$C"
    run_oha_get "health" "/health" "$C"
    run_oha_get "typed-param" "/users/123" "$C"
    run_oha_get "pattern-param" "/devices/router_01" "$C"
    run_oha_get "file-pattern" "/files/readme-01.txt" "$C"
    run_oha_get "hybrid-inline" "/hybrid-inline" "$C"
    run_oha_post "echo-small" "/echo" "$OUT/body-small.txt" "$C"
    run_oha_post "echo-8k" "/echo" "$OUT/body-8k.txt" "$C"
    run_oha_post "hybrid-inline-echo" "/__bench/hybrid-inline-echo" "$OUT/body-small.txt" "$C"
  done
}

capture_build_info() {
  curl -fsS "http://$HOST:$PORT/__bench/meta" > "$OUT/build-info.json" 2> "$OUT/build-info.log" || warn "could not capture build metadata"
}

run_strict_checks() {
  if [[ -z "$STRICT_BENCH" ]]; then
    return 0
  fi
  if [[ "$TARGET" == meteorite ]] && [[ -f "$OUT/build-info.json" ]]; then
    local optimize
    optimize="$(python3 -c "import json; print(json.load(open('$OUT/build-info.json')).get('zig_optimize','n/a'))" 2>/dev/null || echo "n/a")"
    if [[ "$optimize" == "Debug" ]]; then
      strict_fail "Zig optimize mode is Debug; rerun with release-static/release-hybrid to get publishable numbers"
    fi
  fi
  if [[ -n "$STRICT_FAIL_DIRTY" ]] && [[ -n "$(git -C "$ROOT" status --short 2>/dev/null)" ]]; then
    strict_fail "git working directory is dirty"
  fi
  local ka_on ka_off
  ka_on="$(python3 -c "import json; d=json.load(open('$OUT/keepalive-on-smoke.json')).get('summary',{}); print(d.get('requestsPerSec',0))" 2>/dev/null || echo 0)"
  ka_off="$(python3 -c "import json; d=json.load(open('$OUT/keepalive-off-smoke.json')).get('summary',{}); print(d.get('requestsPerSec',0))" 2>/dev/null || echo 0)"
  if [[ "$ka_on" != "0" ]]; then
    if python3 -c "import sys; on=float('$ka_on'); off=float('$ka_off'); sys.exit(0 if abs(on-off)/on <= 0.10 else 1)" 2>/dev/null; then
      strict_fail "keep-alive on/off produced similar throughput (within 10%); server or client may not be reusing connections"
    fi
  fi
  if [[ "$TARGET" == meteorite && "$BACKEND" == fast_http && "$FAST_HTTP_STRATEGY" == pool ]]; then
    python3 - "$OUT/memory.csv" "$FAST_HTTP_WORKERS" "$OUT/backend-counters.json" "$CONCURRENCY" "$MODE" "$STRICT_P99_BASELINE_MS" "$STRICT_P99_FACTOR" "$OUT" <<'PY' || strict_fail "fast_http pool failed bounded-runtime checks"
import csv, json, sys
mem_path, workers_arg, counters_path, concurrency_arg, mode, p99_baseline_arg, p99_factor_arg, out_dir = sys.argv[1:9]
rows=[]
try:
    with open(mem_path, newline='') as f:
        rows=list(csv.DictReader(f))
except FileNotFoundError:
    rows=[]
def num(v):
    try: return float(v)
    except Exception: return None
rss=[num(r.get('rss_kb')) for r in rows]
rss=[v for v in rss if v is not None]
threads=[num(r.get('threads')) for r in rows]
threads=[v for v in threads if v is not None]
counters={}
try:
    counters=json.load(open(counters_path))
except Exception:
    pass
workers=int(workers_arg or '0')
threads_spawned=int(counters.get('threads_spawned') or 0)
lua_states=int(counters.get('lua_states_created') or 0)
lua_errors=int(counters.get('lua_errors') or 0)
dropped=int(counters.get('dropped_connections') or 0)
if workers > 0 and threads_spawned > workers:
    raise SystemExit(f'threads_spawned {threads_spawned} > configured workers {workers}')
if workers == 0 and threads_spawned > 128:
    raise SystemExit(f'threads_spawned {threads_spawned} exceeds default worker sanity cap')
if workers > 0 and threads and max(threads) > workers + 12:
    raise SystemExit(f'max observed threads {max(threads)} exceeds workers + overhead')
if lua_errors > 0:
    raise SystemExit(f'lua_errors {lua_errors} > 0')
if lua_states > 0:
    bound = threads_spawned if threads_spawned > 0 else (workers if workers > 0 else 128)
    if lua_states > bound:
        raise SystemExit(f'lua_states_created {lua_states} > worker/thread bound {bound}')
concurrency_values=[]
for part in concurrency_arg.split(','):
    try:
        concurrency_values.append(int(part))
    except Exception:
        pass
if 256 in concurrency_values and dropped > 0:
    raise SystemExit(f'dropped_connections {dropped} during normal c256 run')
if rss and len(rss) > 3:
    first=rss[0]
    last=rss[-1]
    if first > 0 and last > max(first * 2.0, first + 51200):
        raise SystemExit(f'RSS grew from {first} KiB to {last} KiB')
if p99_baseline_arg:
    import glob, os
    try:
        baseline=float(p99_baseline_arg)
        factor=float(p99_factor_arg or '2.0')
    except Exception as exc:
        raise SystemExit(f'invalid p99 gate env: {exc}')
    candidates=glob.glob(os.path.join(out_dir, 'hybrid-inline-bench-oha-c256.json'))
    if mode == 'release-hybrid' and candidates:
        data=json.load(open(candidates[0]))
        def find_p99(obj):
            if isinstance(obj, dict):
                for key in ('p99','P99'):
                    if key in obj:
                        return obj[key]
                for key in ('latencyPercentiles','latency_percentiles','percentiles'):
                    value=obj.get(key)
                    if isinstance(value, dict):
                        for pkey in ('p99','P99','99','99.0'):
                            if pkey in value:
                                return value[pkey]
                for value in obj.values():
                    got=find_p99(value)
                    if got is not None:
                        return got
            return None
        p99=find_p99(data)
        if p99 is not None:
            p99=float(p99)
            if p99 < 10:
                p99 *= 1000.0
            if p99 > baseline * factor:
                raise SystemExit(f'hybrid-inline c256 p99 {p99:.3f} ms > baseline {baseline:.3f} ms * {factor:.2f}')
PY
  fi
}

run_wrk_checks() {
  if ! command -v wrk >/dev/null 2>&1; then
    warn "wrk not found; skipping wrk sanity checks"
    return 0
  fi
  echo "Running wrk cross-checks..."
  wrk -t8 -c256 -d"$DURATION" --latency \
    "http://$HOST:$PORT/health" \
    > "$OUT/wrk-health-c256.txt" 2> "$OUT/wrk-health-c256.log" || true

  wrk -t8 -c256 -d"$DURATION" --latency \
    -s "$BENCH_DIR/wrk/echo.lua" \
    "http://$HOST:$PORT/echo" \
    > "$OUT/wrk-echo-c256.txt" 2> "$OUT/wrk-echo-c256.log" || true
}

run_perf_check() {
  if [[ "$TARGET" != meteorite ]]; then
    return 0
  fi
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
  "target": "$TARGET",
  "mode": "$MODE",
  "backend": "$BACKEND",
  "fast_http_strategy": "$FAST_HTTP_STRATEGY",
  "fast_http_workers": "$FAST_HTTP_WORKERS",
  "fast_http_queue": "$FAST_HTTP_QUEUE",
  "router_dispatch": "$ROUTER_DISPATCH",
  "hybrid_profile": "$HYBRID_PROFILE",
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
probe_keepalive
capture_build_info
start_memory_sampler
start_runtime_artifacts
run_oha_matrix
sample_inline_route
stop_macos_sampler
run_oha_fixed "health-fixed" "/health" "64" "$QPS"
run_wrk_checks
run_perf_check
capture_post_runtime_artifacts
stop_memory_sampler
stop_server

run_strict_checks

python3 "$BENCH_DIR/summarize.py" "$OUT" > "$OUT/summary.md"

cat <<DONE
Benchmark complete

Results:
  ${OUT#$ROOT/}

Summary:
  ${OUT#$ROOT/}/summary.md

Raw oha JSON:
  ${OUT#$ROOT/}/*-oha-*.json
DONE
