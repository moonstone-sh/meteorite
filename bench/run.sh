#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT/bench"
ORIGINAL_ARGS="$*"
source "$ROOT/fixtures/tests/cleanup.sh"
# shellcheck disable=SC2034
HOST="127.0.0.1"
# shellcheck disable=SC2034
PORT=8080
# shellcheck disable=SC2034
METEORITE_ONLY_SCENARIOS=()
LOADGEN_REQUEST="wrk"
OHA_LATENCY_CORRECTION=0
TARGET_QPS=""
ENV_POLICY=""
OUT=""
# shellcheck disable=SC2034
RESUME=0
ONLY_VARIANT=""

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --mode=*)
    MODE="--mode=${1#--mode=}"
    shift
    ;;
  --mode)
    MODE="--mode=${2:?missing value for --mode}"
    shift 2
    ;;
  --loadgen=*)
    LOADGEN_REQUEST="${1#--loadgen=}"
    shift
    ;;
  --loadgen)
    LOADGEN_REQUEST="${2:?missing value for --loadgen}"
    shift 2
    ;;
  --oha-latency-correction)
    OHA_LATENCY_CORRECTION=1
    shift
    ;;
  --target-qps=*)
    TARGET_QPS="${1#--target-qps=}"
    shift
    ;;
  --target-qps)
    TARGET_QPS="${2:?missing value for --target-qps}"
    shift 2
    ;;
  --qps=*)
    TARGET_QPS="${1#--qps=}"
    shift
    ;;
  --qps)
    TARGET_QPS="${2:?missing value for --qps}"
    shift 2
    ;;
  --env-policy=*)
    ENV_POLICY="${1#--env-policy=}"
    shift
    ;;
  --env-policy)
    ENV_POLICY="${2:?missing value for --env-policy}"
    shift 2
    ;;
  --out=*)
    OUT="${1#--out=}"
    RESUME=1
    shift
    ;;
  --out)
    OUT="${2:?missing value for --out}"
    RESUME=1
    shift 2
    ;;
  --resume=*)
    OUT="${1#--resume=}"
    RESUME=1
    shift
    ;;
  --resume)
    OUT="${2:?missing value for --resume}"
    RESUME=1
    shift 2
    ;;
  --variant=*)
    ONLY_VARIANT="${1#--variant=}"
    shift
    ;;
  --variant)
    ONLY_VARIANT="${2:?missing value for --variant}"
    shift 2
    ;;
  --only=*)
    ONLY_VARIANT="${1#--only=}"
    shift
    ;;
  --only)
    ONLY_VARIANT="${2:?missing value for --only}"
    shift 2
    ;;

  "") shift ;;
  *)
    echo "unknown option: $1" >&2
    echo "Usage: ./bench/run.sh --mode=public|smoke|work|meteorite-app|lua-bridge|lua-bridge-smoke [--loadgen=wrk|oha|both] [--oha-latency-correction] [--target-qps N] [--env-policy=strict|warn|off] [--variant LABEL] [--resume DIR]" >&2
    exit 2
    ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Usage: ./bench/run.sh --mode=public|smoke|work|meteorite-app|lua-bridge|lua-bridge-smoke [--loadgen=wrk|oha|both] [--oha-latency-correction] [--target-qps N] [--env-policy=strict|warn|off] [--variant LABEL] [--resume DIR]" >&2
  exit 2
fi

case "$MODE" in
--mode=public | --mode=smoke | --mode=lua-bridge | --mode=lua-bridge-smoke | --mode=work | --mode=meteorite-app) ;;
*)
  echo "INVALID $MODE" >&2
  echo "expected one of: --mode=public, --mode=smoke, --mode=work, --mode=meteorite-app, --mode=lua-bridge, --mode=lua-bridge-smoke" >&2
  exit 2
  ;;
esac

case "$LOADGEN_REQUEST" in
wrk | oha | both) ;;
*)
  echo "INVALID --loadgen=$LOADGEN_REQUEST" >&2
  echo "expected one of: wrk, oha, both" >&2
  exit 2
  ;;
esac

case "$ENV_POLICY" in
"" | strict | warn | off) ;;
*)
  echo "INVALID --env-policy=$ENV_POLICY" >&2
  echo "expected one of: strict, warn, off" >&2
  exit 2
  ;;
esac

if [[ "$LOADGEN_REQUEST" == "both" ]]; then
  echo "Running comparative loadgen audit: wrk then oha"
  if [[ -z "$OUT" ]]; then
    OUT="$BENCH_DIR/results/$(date -u +%Y-%m-%d_%H-%M-%S)_${MODE#*=}"
  fi
  mkdir -p "$OUT"
  BOTH_MARKER="$(mktemp /tmp/meteorite-loadgen-both.XXXXXX)"
  resume_out_for_loadgen() {
    local label="$1"
    if [[ -z "$OUT" ]]; then
      printf ''
      return 0
    fi
    case "$OUT" in
    *-wrk-*) printf '%s' "${OUT/-wrk-/-${label}-}" ;;
    *-oha-corrected-*) printf '%s' "${OUT/-oha-corrected-/-${label}-}" ;;
    *-oha-*) printf '%s' "${OUT/-oha-/-${label}-}" ;;
    *) printf '%s/%s' "$OUT" "$label" ;;
    esac
  }
  run_loadgen_child() {
    local loadgen="$1"
    local resume_dir="$2"
    local corrected="${3:-0}"
    local args=("$MODE" --loadgen="$loadgen")
    if [[ "$corrected" == "1" ]]; then
      args+=(--oha-latency-correction)
    fi
    if [[ -n "$TARGET_QPS" ]]; then
      args+=(--target-qps "$TARGET_QPS")
    fi
    if [[ -n "$ENV_POLICY" ]]; then
      args+=(--env-policy "$ENV_POLICY")
    fi
    if [[ -n "$resume_dir" ]]; then
      args+=(--resume "$resume_dir")
    fi
    if [[ -n "$ONLY_VARIANT" ]]; then
      args+=(--variant "$ONLY_VARIANT")
    fi
    BENCH_RESULT_MARKER_FILE="$BOTH_MARKER" "$0" "${args[@]}"
  }
  WRK_RESUME_OUT="$(resume_out_for_loadgen wrk)"
  OHA_RESUME_OUT="$(resume_out_for_loadgen oha)"
  run_loadgen_child wrk "$WRK_RESUME_OUT"
  run_loadgen_child oha "$OHA_RESUME_OUT"
  if [[ "$OHA_LATENCY_CORRECTION" == "1" ]]; then
    OHA_CORRECTED_RESUME_OUT="$(resume_out_for_loadgen oha-corrected)"
    run_loadgen_child oha "$OHA_CORRECTED_RESUME_OUT" 1
  fi
  python3 "$BENCH_DIR/report/loadgen_audit.py" "$BOTH_MARKER"
  ln -sfn "$(basename "$OUT")" "$BENCH_DIR/results/latest"
  rm -f "$BOTH_MARKER"
  exit 0
fi

LOADGEN="$LOADGEN_REQUEST"
LOADGEN_LABEL="$LOADGEN"
if [[ "$LOADGEN" == "oha" && "$OHA_LATENCY_CORRECTION" == "1" ]]; then
  LOADGEN_LABEL="oha-corrected"
fi

if [[ "$MODE" == "--mode=public" ]]; then
  echo "Running Public/Presentation Suite..."
  echo "Fair set: meteorite-auto, hono-bun-multiprocess, go-nethttp, go-fiber-fasthttp, rust-actix. Single-worker/single-process rows are diagnostic."
  if [[ -z "$ENV_POLICY" ]]; then
    ENV_POLICY="strict"
  fi
  DURATION="20"
  WARMUP="5"
  REPS=5
  # CONCURRENCY="1,64,512,1024"
  # Since we are seeing just 11 connections at most, lets just leave like that.
  CONCURRENCY="1,4,11"
  THREADS="10"
  SCENARIOS=(
    "plain_text|GET|/__bench/plain"
    "typed_param|GET|/users/123"
    "echo_small|POST|/echo"
  )
  METEORITE_ONLY_SCENARIOS=(
    "plain_text_hybrid|GET|/__bench/hybrid-inline"
    "typed_param_hybrid|GET|/__bench/hybrid-inline-params/123"
    "echo_small_hybrid|POST|/__bench/hybrid-inline-echo"
  )
elif [[ "$MODE" == "--mode=smoke" ]]; then
  echo "Running Fast Smoke Suite..."
  echo "Smoke set includes all public target families with reduced reps/concurrency."
  DURATION="10"
  WARMUP="2"
  REPS=1
  CONCURRENCY="1,64,1024"
  THREADS="10"
  SCENARIOS=(
    "plain_text|GET|/__bench/plain"
    "typed_param|GET|/users/123"
    "echo_small|POST|/echo"
  )
elif [[ "$MODE" == "--mode=work" ]]; then
  echo "Running Controlled Work Benchmark Suite..."
  echo "Work endpoints are separate from raw fast-path results and validate load-generator active pressure."
  DURATION="10"
  WARMUP="2"
  REPS=2
  CONCURRENCY="1,8,16,32,64,128,512"
  THREADS="10"
  SCENARIOS=(
    "work-cpu-100us|GET|/__bench/work/cpu/100us"
    "work-cpu-500us|GET|/__bench/work/cpu/500us"
    "work-cpu-1ms|GET|/__bench/work/cpu/1ms"
    "work-cpu-2ms|GET|/__bench/work/cpu/2ms"
    "work-sleep-1ms|GET|/__bench/work/sleep/1ms"
    "work-sleep-5ms|GET|/__bench/work/sleep/5ms"
  )
elif [[ "$MODE" == "--mode=meteorite-app" ]]; then
  echo "Running Meteorite Realistic Lua App Workload Suite..."
  echo "Meteorite-only JSON/template/SQLite routes; not a public framework comparison."
  DURATION="10"
  WARMUP="2"
  REPS=2
  CONCURRENCY="1,4,11"
  THREADS="10"
  SCENARIOS=(
    "app-json-encode-small|GET|/__app/json/encode-small"
    "app-json-decode-1kb|POST|/__app/json/decode-1kb"
    "app-json-roundtrip-1kb|POST|/__app/json/roundtrip-1kb"
    "app-template-hello|GET|/__app/template/hello"
    "app-template-list-100|GET|/__app/template/list-100"
    "app-sqlite-select-one|GET|/__app/sqlite/select-one"
    "app-sqlite-select-100|GET|/__app/sqlite/select-100"
    "app-sqlite-insert-small|POST|/__app/sqlite/insert-small"
    "app-pipeline-cors|GET|/__app/pipeline/cors"
    "app-pipeline-cors-json-template|GET|/__app/pipeline/cors-json-template"
    "app-full-sqlite-json-template|GET|/__app/full/sqlite-json-template"
  )
elif [[ "$MODE" == "--mode=lua-bridge" ]]; then
  echo "Running Lua Bridge Decomposition Suite..."
  DURATION="10"
  WARMUP="2"
  REPS=3
  CONCURRENCY="1,64,512,1024"
  THREADS="10"
  SCENARIOS=(
    "zig-static|GET|/__bench/zig-static"
    "lua-empty|GET|/__bench/lua-empty"
    "lua-return-string|GET|/__bench/lua-return-string"
    "lua-text-direct|GET|/__bench/lua-text-direct"
    "lua-response-table|GET|/__bench/lua-response-table"
    "lua-direct-param|GET|/__bench/lua-direct-param/123"
    "lua-ctx-param|GET|/__bench/lua-ctx-param/123"
    "lua-req-table|GET|/__bench/lua-req-table/123"
    "lua-body-1k|POST|/__bench/lua-body-1k"
    "lua-json-small|GET|/__bench/lua-json-small"
    "lua-loop-0|GET|/__bench/lua-loop-0"
    "lua-loop-10|GET|/__bench/lua-loop-10"
    "lua-loop-100|GET|/__bench/lua-loop-100"
    "lua-loop-1000|GET|/__bench/lua-loop-1000"
    "lua-loop-10000|GET|/__bench/lua-loop-10000"
    "lua-loop-100000|GET|/__bench/lua-loop-100000"
    "lua-sleep-1s|GET|/__bench/lua-sleep-1s"
  )
elif [[ "$MODE" == "--mode=lua-bridge-smoke" ]]; then
  echo "Running Lua Bridge CI Smoke Suite..."
  DURATION="2"
  WARMUP="0"
  REPS=1
  CONCURRENCY="1,64"
  THREADS="4"
  SCENARIOS=(
    "zig-static|GET|/__bench/zig-static"
    "lua-return-string|GET|/__bench/lua-return-string"
    "lua-text-direct|GET|/__bench/lua-text-direct"
    "lua-direct-param|GET|/__bench/lua-direct-param/123"
    "lua-loop-1000|GET|/__bench/lua-loop-1000"
    "lua-sleep-1s|GET|/__bench/lua-sleep-1s"
  )
else
  echo "Usage: ./bench/run.sh --mode=public|smoke|work|meteorite-app|lua-bridge|lua-bridge-smoke"
  exit 1
fi

if [[ -z "$ENV_POLICY" ]]; then
  case "$MODE" in
  --mode=public | --mode=work | --mode=meteorite-app | --mode=lua-bridge) ENV_POLICY="strict" ;;
  *) ENV_POLICY="warn" ;;
  esac
fi

if [[ -n "$ONLY_VARIANT" ]]; then
  case "$MODE:$ONLY_VARIANT" in
  --mode=public:meteorite-1worker | --mode=public:meteorite-auto | --mode=public:hono-bun-single | --mode=public:hono-bun-multiprocess | --mode=public:go-nethttp | --mode=public:go-fiber-fasthttp | --mode=public:rust-actix | --mode=public:openresty | --mode=public:lapis-openresty | --mode=public:lapis-cqueues | --mode=public:turbo | --mode=public:pegasus) ;;
  --mode=smoke:meteorite-1worker | --mode=smoke:meteorite-auto | --mode=smoke:hono-bun-single | --mode=smoke:go-nethttp | --mode=smoke:go-fiber-fasthttp | --mode=smoke:rust-actix | --mode=smoke:openresty | --mode=smoke:lapis-openresty | --mode=smoke:lapis-cqueues | --mode=smoke:turbo | --mode=smoke:pegasus) ;;
  --mode=work:meteorite-1worker | --mode=work:meteorite-auto | --mode=work:hono-bun-single | --mode=work:hono-bun-multiprocess | --mode=work:go-nethttp | --mode=work:go-fiber-fasthttp | --mode=work:rust-actix | --mode=work:openresty | --mode=work:lapis-openresty | --mode=work:lapis-cqueues | --mode=work:turbo | --mode=work:pegasus) ;;
  --mode=meteorite-app:meteorite-1worker | --mode=meteorite-app:meteorite-auto) ;;
  --mode=lua-bridge:meteorite-1worker | --mode=lua-bridge:meteorite-auto | --mode=lua-bridge-smoke:meteorite-1worker | --mode=lua-bridge-smoke:meteorite-auto) ;;
  *)
    echo "INVALID --variant=$ONLY_VARIANT for ${MODE#--mode=}" >&2
    echo "public variants: meteorite-1worker, meteorite-auto, hono-bun-single, hono-bun-multiprocess, go-nethttp, go-fiber-fasthttp, rust-actix, openresty, lapis-openresty, lapis-cqueues, turbo, pegasus" >&2
    echo "lua-bridge variants: meteorite-1worker, meteorite-auto" >&2
    exit 2
    ;;
  esac
fi

RUN_ROOT=""
if [[ -n "$OUT" ]]; then
  case "$(basename "$OUT")" in
  wrk | oha | oha-corrected)
    RUN_ROOT="$(dirname "$OUT")"
    ;;
  *)
    RUN_ROOT="$OUT"
    OUT="$RUN_ROOT/$LOADGEN_LABEL"
    ;;
  esac
else
  RUN_ROOT="$BENCH_DIR/results/$(date -u +%Y-%m-%d_%H-%M-%S)_${MODE#*=}"
  OUT="$RUN_ROOT/$LOADGEN_LABEL"
fi
mkdir -p "$RUN_ROOT" "$OUT"
RAW_DIR="$OUT/raw"
META_DIR="$OUT/meta"
mkdir -p "$RAW_DIR" "$META_DIR"
IFS=',' read -ra CONCURRENCY_VALUES <<<"$CONCURRENCY"

ln -sfn "$RUN_ROOT" "$BENCH_DIR/results/latest"


# Source all library modules
for lib in "$BENCH_DIR"/lib/*.sh; do
  source "$lib"
done

cat <<EOF >"$OUT/post.lua"
wrk.method = "POST"
wrk.body = string.rep("x", 1024)
wrk.headers["Connection"] = "keep-alive"
EOF
BENCH_POST_BODY="$(printf '%*s' 1024 '' | tr ' ' x)"
if [[ "$MODE" == "--mode=meteorite-app" ]]; then
  BENCH_POST_BODY="$(
    python3 - <<'PY'
import json
payload = "x" * 1024
print(json.dumps({"name":"meteorite","n":123,"payload":payload}, separators=(",", ":")))
PY
  )"
  cat <<EOF >"$OUT/post.lua"
wrk.method = "POST"
wrk.body = '$BENCH_POST_BODY'
wrk.headers["Connection"] = "keep-alive"
wrk.headers["Content-Type"] = "application/json"
EOF
fi

run_environment_preflight "$OUT/system.env"

{
  printf 'mode=%s\n' "${MODE#--mode=}"
  printf 'command=%s\n' "bench/run.sh $ORIGINAL_ARGS"
  printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'host=%s\n' "$(hostname 2>/dev/null || printf unknown)"
  printf 'uname=%s\n' "$(uname -a 2>/dev/null || printf unknown)"
  printf 'git_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
  printf 'loadgen=%s\n' "$LOADGEN_LABEL"
  printf 'loadgen_base=%s\n' "$LOADGEN"
  printf 'oha_latency_correction=%s\n' "$OHA_LATENCY_CORRECTION"
  printf 'target_qps=%s\n' "${TARGET_QPS:-none}"
  printf 'env_policy=%s\n' "$ENV_POLICY"
  printf 'variant=%s\n' "${ONLY_VARIANT:-all}"
  printf 'result_subdir=%s\n' "$(basename "$OUT")"
} >"$RUN_ROOT/run-info.txt"

# State tracking
SERVER_PID=""
SERVER_STATS_FILE=""
LOADGEN_PID=""
LOADGEN_STATS_FILE=""
STATS_PIDS=()

_INTERRUPTED=0

# Execute Variants based on Mode
if [[ "$MODE" == "--mode=smoke" ]]; then
  run_selected_variant "meteorite-1worker" start_meteorite "1"
  run_selected_variant "meteorite-auto" start_meteorite "0"
  run_selected_variant "hono-bun-single" start_hono "single"
  run_selected_variant "go-nethttp" start_go_nethttp
  run_selected_variant "go-fiber-fasthttp" start_go_fiber
  run_selected_variant "rust-actix" start_rust_actix
  run_selected_variant "openresty" start_openresty
  run_selected_variant "lapis-openresty" start_lapis_openresty
  run_selected_variant "lapis-cqueues" start_lapis_cqueues
  run_selected_variant "turbo" start_turbo
  run_selected_variant "pegasus" start_pegasus
elif [[ "$MODE" == "--mode=work" ]]; then
  run_selected_variant "meteorite-1worker" start_meteorite "1"
  run_selected_variant "meteorite-auto" start_meteorite "0"
  run_selected_variant "hono-bun-single" start_hono "single"
  run_selected_variant "hono-bun-multiprocess" start_hono "multiprocess"
  run_selected_variant "go-nethttp" start_go_nethttp
  run_selected_variant "go-fiber-fasthttp" start_go_fiber
  run_selected_variant "rust-actix" start_rust_actix
  run_selected_variant "openresty" start_openresty
  run_selected_variant "lapis-openresty" start_lapis_openresty
  run_selected_variant "lapis-cqueues" start_lapis_cqueues
  run_selected_variant "turbo" start_turbo
  run_selected_variant "pegasus" start_pegasus
elif [[ "$MODE" == "--mode=meteorite-app" ]]; then
  run_selected_variant "meteorite-1worker" start_meteorite "1"
  run_selected_variant "meteorite-auto" start_meteorite "0"
elif [[ "$MODE" == "--mode=public" ]]; then
  run_selected_variant "meteorite-1worker" start_meteorite "1"
  run_selected_variant "meteorite-auto" start_meteorite "0"
  run_selected_variant "hono-bun-single" start_hono "single"
  run_selected_variant "hono-bun-multiprocess" start_hono "multiprocess"
  run_selected_variant "go-nethttp" start_go_nethttp
  run_selected_variant "go-fiber-fasthttp" start_go_fiber
  run_selected_variant "rust-actix" start_rust_actix
  run_selected_variant "openresty" start_openresty
  run_selected_variant "lapis-openresty" start_lapis_openresty
  run_selected_variant "lapis-cqueues" start_lapis_cqueues
  run_selected_variant "turbo" start_turbo
  run_selected_variant "pegasus" start_pegasus
elif [[ "$MODE" == "--mode=lua-bridge" || "$MODE" == "--mode=lua-bridge-smoke" ]]; then
  run_selected_variant "meteorite-1worker" start_meteorite "1"
  run_selected_variant "meteorite-auto" start_meteorite "0"
fi

kill_server

echo ""
echo "=== Validation Matrix Complete ==="
{
  printf '%s\n' "${SCENARIOS[@]}"
  if [[ "$MODE" == "--mode=public" ]]; then
    printf '%s\n' "${METEORITE_ONLY_SCENARIOS[@]}"
  fi
} >"$OUT/scenarios.txt"
BENCH_OUT="$OUT" BENCH_MODE="$MODE" BENCH_REPS="$REPS" BENCH_CONCURRENCY="$CONCURRENCY" BENCH_SCENARIOS_FILE="$OUT/scenarios.txt" BENCH_LOADGEN="$LOADGEN_LABEL" BENCH_LATENCY_CORRECTION="$OHA_LATENCY_CORRECTION" python3 "$BENCH_DIR/report/summary.py" | tee "$OUT/summary.md"
sanitize_text_file "$OUT/summary.md"
sanitize_text_file "$OUT/summary.json"
if [[ -n "${BENCH_RESULT_MARKER_FILE:-}" ]]; then
  printf '%s=%s\n' "$LOADGEN_LABEL" "$OUT" >>"$BENCH_RESULT_MARKER_FILE"
fi
echo "Done."
