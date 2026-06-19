#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${DURATION:-60s}"
STABILITY_DURATION="${STABILITY_DURATION:-5m}"
CONCURRENCY="${CONCURRENCY:-1,8,32,128,256,512}"
FAST_HTTP_WORKERS="${FAST_HTTP_WORKERS:-0}"
FAST_HTTP_QUEUE="${FAST_HTTP_QUEUE:-1024}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_OUT="${OUT_BASE:-$ROOT/bench/results/fast-http-matrix-$STAMP}"

mkdir -p "$BASE_OUT"

run_case() {
  local name="$1"; shift
  echo "==> $name"
  "$ROOT/bench/run.sh" \
    --duration "$DURATION" \
    --concurrency "$CONCURRENCY" \
    --strict-bench \
    --out "$BASE_OUT/$name" \
    "$@"
}

run_case meteorite-static-threaded \
  --target meteorite --mode release-static --backend fast_http --fast-http-strategy threaded_probe

run_case meteorite-static-pool \
  --target meteorite --mode release-static --backend fast_http --fast-http-strategy pool --fast-http-workers "$FAST_HTTP_WORKERS" --fast-http-queue "$FAST_HTTP_QUEUE"

run_case meteorite-hybrid-threaded \
  --target meteorite --mode release-hybrid --hybrid-profile optimized --backend fast_http --fast-http-strategy threaded_probe

run_case meteorite-hybrid-pool \
  --target meteorite --mode release-hybrid --hybrid-profile optimized --backend fast_http --fast-http-strategy pool --fast-http-workers "$FAST_HTTP_WORKERS" --fast-http-queue "$FAST_HTTP_QUEUE"

run_case hono-bun \
  --target hono-bun

python3 "$ROOT/bench/compare.py" \
  "$BASE_OUT/meteorite-static-threaded" \
  "$BASE_OUT/meteorite-static-pool" \
  "$BASE_OUT/meteorite-hybrid-threaded" \
  "$BASE_OUT/meteorite-hybrid-pool" \
  "$BASE_OUT/hono-bun" \
  > "$BASE_OUT/comparison.md"

if [[ "${RUN_STABILITY:-0}" == "1" ]]; then
  echo "==> meteorite-pool-stability (${STABILITY_DURATION})"
  "$ROOT/bench/run.sh" \
    --target meteorite \
    --mode release-static \
    --backend fast_http \
    --fast-http-strategy pool \
    --fast-http-workers "$FAST_HTTP_WORKERS" \
    --fast-http-queue "$FAST_HTTP_QUEUE" \
    --duration "$STABILITY_DURATION" \
    --concurrency "256" \
    --strict-bench \
    --out "$BASE_OUT/meteorite-pool-stability"
fi

cat <<DONE
Fast HTTP matrix complete

Results: ${BASE_OUT#$ROOT/}
Comparison: ${BASE_OUT#$ROOT/}/comparison.md
DONE
