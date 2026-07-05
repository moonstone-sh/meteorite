#!/usr/bin/env bash
set -euo pipefail

run_loadgen_once() {
  local method="$1" url="$2" concurrency="$3" threads="$4" duration="$5" raw_file="$6" latency="$7"
  if [[ "$LOADGEN" == "wrk" ]]; then
    if [[ "$method" == "POST" ]]; then
      wrk -t "$threads" -c "$concurrency" -d "${duration}s" -s "$OUT/post.lua" ${latency:+--latency} "$url" >"$raw_file" 2>&1
    else
      wrk -t "$threads" -c "$concurrency" -d "${duration}s" ${latency:+--latency} "$url" >"$raw_file" 2>&1
    fi
  else
    local args=(--no-tui --output-format json -c "$concurrency" -z "${duration}s" -H "Connection: keep-alive")
    if [[ "$OHA_LATENCY_CORRECTION" == "1" ]]; then
      args+=(--latency-correction)
    fi
    if [[ -n "$TARGET_QPS" ]]; then
      args+=(-q "$TARGET_QPS")
    fi
    if [[ "$method" == "POST" ]]; then
      args+=(-m POST -d "$BENCH_POST_BODY" -H "Content-Type: $([[ "$MODE" == "--mode=meteorite-app" ]] && printf 'application/json' || printf 'text/plain')")
    fi
    env -u NO_COLOR oha "${args[@]}" "$url" >"$raw_file" 2>&1
  fi
}


parse_oha_metric() {
  local raw_file="$1"
  python3 - "$raw_file" <<'PY'
import json, math, sys
from pathlib import Path

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

def first(*names, default=0):
    wanted = {name.lower() for name in names}
    for d in walk(data):
        for key, value in d.items():
            if str(key).lower() in wanted and isinstance(value, (int, float)):
                return value
    return default

def duration_us(value):
    if value is None:
        return 0
    if isinstance(value, str):
        s = value.strip()
        try:
            if s.endswith('ms'):
                return float(s[:-2]) * 1000
            if s.endswith('us') or s.endswith('µs'):
                return float(s[:-2])
            if s.endswith('s'):
                return float(s[:-1]) * 1_000_000
            return float(s) * 1_000_000
        except Exception:
            return 0
    if isinstance(value, (int, float)):
        return float(value) * 1_000_000
    return 0

def percentile(name):
    wanted = {name, name.upper(), name.lower(), name.replace('p', ''), name.replace('p', '') + '.0'}
    for d in walk(data):
        for key, value in d.items():
            if str(key) in wanted:
                return duration_us(value)
    return 0

def count_non2xx():
    total = 0
    for d in walk(data):
        for key, value in d.items():
            lk = str(key).lower()
            if 'status' in lk and isinstance(value, dict):
                for code, count in value.items():
                    try:
                        code_i = int(code)
                        count_i = int(count)
                    except Exception:
                        continue
                    if not (200 <= code_i < 400):
                        total += count_i
    return total

def count_status_total():
    total = 0
    for d in walk(data):
        for key, value in d.items():
            lk = str(key).lower()
            if 'status' in lk and isinstance(value, dict):
                for _, count in value.items():
                    try:
                        total += int(count)
                    except Exception:
                        pass
    return total

try:
    data = json.loads(Path(sys.argv[1]).read_text(errors='replace'))
except Exception:
    data = {}

requests = count_status_total() or int(first('requests', 'requests_completed', 'successful', default=0))
rps = float(first('requestsPerSec', 'requests_per_sec', 'requestPerSec', 'rps', default=0))
avg = duration_us(first('average', 'avg', 'latency_avg', default=0))
stdev = duration_us(first('stddev', 'stdev', 'standardDeviation', 'latency_stdev', default=0))
max_v = duration_us(first('slowest', 'max', 'latency_max', default=0))
transfer = float(first('sizePerSec', 'bytesPerSec', 'transfer_per_sec', default=0))
errors = int(first('error', 'errors', 'failed', default=0))
non2xx = count_non2xx()
print(f"rps={rps}")
print(f"requests={requests}")
print(f"latency_avg_us={avg:.0f}")
print(f"latency_stdev_us={stdev:.0f}")
print(f"latency_max_us={max_v:.0f}")
print(f"p50_us={percentile('p50'):.0f}")
print(f"p75_us={percentile('p75'):.0f}")
print(f"p90_us={percentile('p90'):.0f}")
print(f"p99_us={percentile('p99'):.0f}")
print("socket_connect_errors=0")
print("socket_read_errors=0")
print("socket_write_errors=0")
print(f"socket_timeout_errors={errors}")
print(f"socket_errors={errors}")
print(f"non2xx={non2xx}")
print(f"transfer_per_sec_bytes={transfer:.0f}")
PY
}


