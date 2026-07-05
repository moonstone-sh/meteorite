#!/usr/bin/env bash
set -euo pipefail

now_ns() {
  python3 -c 'import time; print(time.time_ns())'
}


wait_for_server() {
  for _ in $(seq 1 100); do
    if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}


kill_server() {
  if [[ -n "${LOADGEN_PID:-}" ]] && kill -0 "$LOADGEN_PID" 2>/dev/null; then
    get_descendants "$LOADGEN_PID" | while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done || true
    kill -- "-$LOADGEN_PID" 2>/dev/null || true
    if ! wait_for_exit "$LOADGEN_PID" 20; then
      get_descendants "$LOADGEN_PID" | while read -r pid; do
        kill -9 "$pid" 2>/dev/null || true
      done || true
      kill -9 -- "-$LOADGEN_PID" 2>/dev/null || true
    fi
    wait "$LOADGEN_PID" 2>/dev/null || true
    unregister_pid "$LOADGEN_PID"
  fi
  LOADGEN_PID=""
  for stats_pid in "${STATS_PIDS[@]:-}"; do
    if [[ -n "$stats_pid" ]] && kill -0 "$stats_pid" 2>/dev/null; then
      kill "$stats_pid" 2>/dev/null || true
      wait "$stats_pid" 2>/dev/null || true
      unregister_pid "$stats_pid"
    fi
  done
  STATS_PIDS=()
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    get_descendants "$SERVER_PID" | while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done || true
    kill -- "-$SERVER_PID" 2>/dev/null || true
    if ! wait_for_exit "$SERVER_PID" 20; then
      get_descendants "$SERVER_PID" | while read -r pid; do
        kill -9 "$pid" 2>/dev/null || true
      done || true
      kill -9 -- "-$SERVER_PID" 2>/dev/null || true
    fi
    wait "$SERVER_PID" 2>/dev/null || true
    unregister_pid "$SERVER_PID"
  fi
  SERVER_PID=""
  lsof -tiTCP:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
}


handle_signal() {
  _INTERRUPTED=1
  kill_server
  exit 130
}

trap kill_server EXIT
trap handle_signal INT TERM HUP


start_meteorite() {
  local workers="$1"
  require_command zig
  echo "Building meteorite (workers=$workers)..."
  ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache-bench" \
    zig build install-server \
    -Dgraph-input="fixtures/apps/bench-service/src/main.lua" \
    -Dgraph-output=".meteorite/graph/bench" \
    -Dmode=release-hybrid \
    -Dhybrid-profile=optimized \
    -Dfast-http-strategy=pool \
    -Dfast-http-workers="$workers" \
    -- dist/server >/dev/null 2>&1
  assert_bench_graph

  local label="meteorite-1worker"
  if [[ "$workers" == "0" ]]; then label="meteorite-auto"; fi

  ./dist/server >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}


start_hono() {
  local mode="$1"
  require_command bun
  echo "Starting Hono/Bun ($mode)..."
  cd "$BENCH_DIR/competitors/hono"
  if [[ "$mode" == "single" ]]; then
    NODE_ENV=production BUN_GARBAGE_COLLECTOR_LEVEL=0 bun server.ts --port=$PORT --bench-mode=single-process >"$OUT/hono-bun-single.log" 2>&1 &
  else
    NODE_ENV=production BUN_GARBAGE_COLLECTOR_LEVEL=0 bun server-cluster.ts --port=$PORT >"$OUT/hono-bun-multiprocess.log" 2>&1 &
  fi
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  cd "$ROOT"
  wait_for_server
  SERVER_STATS_FILE="$OUT/hono-bun-${mode}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}


start_go_nethttp() {
  local label="go-nethttp"
  require_command go
  echo "Building Go net/http..."
  (cd "$BENCH_DIR/competitors/go-nethttp" && go build -trimpath -ldflags='-s -w' -o "$OUT/go-nethttp-server" .)
  echo "Starting Go net/http..."
  "$OUT/go-nethttp-server" --port="$PORT" >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}


start_go_fiber() {
  local label="go-fiber-fasthttp"
  require_command go
  echo "Building Go Fiber/fasthttp..."
  record_go_fiber_environment
  (cd "$BENCH_DIR/competitors/go-fiber" && GOCACHE="${GOCACHE:-/tmp/meteorite-go-build-cache}" go build -trimpath -ldflags='-s -w' -o "$OUT/go-fiber-server" .)
  echo "Starting Go Fiber/fasthttp..."
  "$OUT/go-fiber-server" --port="$PORT" >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
  curl -fsS "http://$HOST:$PORT/__bench/meta" >"$OUT/${label}.meta.json" 2>/dev/null || true
}


start_rust_actix() {
  local label="rust-actix"
  require_command cargo
  echo "Building Rust Actix..."
  cargo build --release --manifest-path "$BENCH_DIR/competitors/rust-actix/Cargo.toml" --target-dir "$BENCH_DIR/competitors/rust-actix/target" >/dev/null
  echo "Starting Rust Actix..."
  "$BENCH_DIR/competitors/rust-actix/target/release/meteorite-bench-rust-actix" --port="$PORT" >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_openresty() {
  local label="openresty"
  echo "Starting OpenResty..."
  (cd "$BENCH_DIR/competitors/openresty" && /Users/extrordinaire/Workbench/user/moonstone/zig-out/bin/moon orbit exec openresty -- bash run.sh) >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_lapis_openresty() {
  local label="lapis-openresty"
  echo "Starting Lapis OpenResty..."
  (cd "$BENCH_DIR/competitors/lapis-openresty" && /Users/extrordinaire/Workbench/user/moonstone/zig-out/bin/moon orbit exec lapis-openresty -- bash run.sh) >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_lapis_cqueues() {
  local label="lapis-cqueues"
  echo "Starting Lapis cqueues..."
  (cd "$BENCH_DIR/competitors/lapis-cqueues" && /Users/extrordinaire/Workbench/user/moonstone/zig-out/bin/moon orbit exec lapis-cqueues -- bash run.sh) >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_turbo() {
  local label="turbo"
  echo "Starting Turbo..."
  (cd "$BENCH_DIR/competitors/turbo" && /Users/extrordinaire/Workbench/user/moonstone/zig-out/bin/moon orbit exec turbo -- bash run.sh) >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}

start_pegasus() {
  local label="pegasus"
  echo "Starting Pegasus..."
  (cd "$BENCH_DIR/competitors/pegasus" && /Users/extrordinaire/Workbench/user/moonstone/zig-out/bin/moon orbit exec pegasus -- bash run.sh) >"$OUT/${label}.log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  wait_for_server
  SERVER_STATS_FILE="$OUT/${label}-stats.log"
  start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"
}


