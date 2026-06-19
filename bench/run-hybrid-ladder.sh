#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${DURATION:-30s}"
CONCURRENCY="${CONCURRENCY:-32,128,256,512}"
FAST_HTTP_WORKERS="${FAST_HTTP_WORKERS:-0}"
FAST_HTTP_QUEUE="${FAST_HTTP_QUEUE:-1024}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_OUT="${OUT_BASE:-$ROOT/bench/results/hybrid-ladder-$STAMP}"
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

run_case meteorite-static \
  --target meteorite --mode release-static --backend fast_http --fast-http-strategy pool --fast-http-workers "$FAST_HTTP_WORKERS" --fast-http-queue "$FAST_HTTP_QUEUE"

run_case meteorite-hybrid \
  --target meteorite --mode release-hybrid --hybrid-profile optimized --backend fast_http --fast-http-strategy pool --fast-http-workers "$FAST_HTTP_WORKERS" --fast-http-queue "$FAST_HTTP_QUEUE"

run_case hono-bun \
  --target hono-bun

python3 "$ROOT/bench/hybrid_ladder.py" \
  "$BASE_OUT/meteorite-static" \
  "$BASE_OUT/meteorite-hybrid" \
  "$BASE_OUT/hono-bun" \
  > "$BASE_OUT/hybrid-ladder.md"

cat <<DONE
Hybrid ladder complete

Results: ${BASE_OUT#$ROOT/}
Ladder: ${BASE_OUT#$ROOT/}/hybrid-ladder.md
DONE
