#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_OUT="${OUT_BASE:-$ROOT/bench/results/lua-stability-$STAMP}"
FAST_HTTP_WORKERS="${FAST_HTTP_WORKERS:-0}"
FAST_HTTP_QUEUE="${FAST_HTTP_QUEUE:-1024}"
NORMAL_DURATION="${NORMAL_DURATION:-60s}"
PRESSURE_DURATION="${PRESSURE_DURATION:-120s}"
SOAK_DURATION="${SOAK_DURATION:-5m}"
NORMAL_CONCURRENCY="${NORMAL_CONCURRENCY:-32,128,256}"
PRESSURE_CONCURRENCY="${PRESSURE_CONCURRENCY:-512,1024}"

mkdir -p "$BASE_OUT"

echo "==> lua correctness smoke"
FAST_HTTP_WORKERS="${CORRECTNESS_WORKERS:-2}" FAST_HTTP_QUEUE="$FAST_HTTP_QUEUE" \
  "$ROOT/bench/check-lua-state-correctness.sh" > "$BASE_OUT/correctness.log" 2>&1

echo "==> 60s normal hybrid ladder"
DURATION="$NORMAL_DURATION" \
CONCURRENCY="$NORMAL_CONCURRENCY" \
FAST_HTTP_WORKERS="$FAST_HTTP_WORKERS" \
FAST_HTTP_QUEUE="$FAST_HTTP_QUEUE" \
OUT_BASE="$BASE_OUT/hybrid-ladder" \
  "$ROOT/bench/run-hybrid-ladder.sh"

echo "==> 120s high-concurrency queue pressure"
"$ROOT/bench/run.sh" \
  --target meteorite \
  --mode release-hybrid \
  --hybrid-profile optimized \
  --backend fast_http \
  --fast-http-strategy pool \
  --fast-http-workers "$FAST_HTTP_WORKERS" \
  --fast-http-queue "$FAST_HTTP_QUEUE" \
  --duration "$PRESSURE_DURATION" \
  --concurrency "$PRESSURE_CONCURRENCY" \
  --strict-bench \
  --out "$BASE_OUT/queue-pressure"

if [[ "${RUN_SOAK:-0}" == "1" ]]; then
  echo "==> optional 5m hybrid soak"
  "$ROOT/bench/run.sh" \
    --target meteorite \
    --mode release-hybrid \
    --hybrid-profile optimized \
    --backend fast_http \
    --fast-http-strategy pool \
    --fast-http-workers "$FAST_HTTP_WORKERS" \
    --fast-http-queue "$FAST_HTTP_QUEUE" \
    --duration "$SOAK_DURATION" \
    --concurrency "256" \
    --strict-bench \
    --out "$BASE_OUT/soak"
fi

cat <<DONE
Lua stability validation complete

Results: ${BASE_OUT#$ROOT/}
Correctness log: ${BASE_OUT#$ROOT/}/correctness.log
DONE
