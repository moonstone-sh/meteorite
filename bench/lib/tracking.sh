#!/usr/bin/env bash
set -euo pipefail

stats_field() {
  local route="$1" field="$2"
  curl -fsS "http://$HOST:$PORT/__bench/stats" 2>/dev/null | python3 -c 'import json,sys; route=sys.argv[1]; field=sys.argv[2]; data=json.load(sys.stdin); print(data.get("routes", {}).get(route, {}).get(field, ""))' "$route" "$field"
}


bench_meta_fields() {
  curl -fsS "http://$HOST:$PORT/__bench/meta" 2>/dev/null | python3 -c 'import json,sys
fields=sys.argv[1:]
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
for field in fields:
    print(f"{field}={data.get(field, 0)}")
' "$@"
}


reset_bench_stats() {
  curl -fsS -X POST "http://$HOST:$PORT/__bench/stats/reset" >/dev/null 2>&1
}


start_stats_tracker() {
  local pid="$1"
  local log_file="$2"

  : >"$log_file"

  (
    while kill -0 "$pid" 2>/dev/null; do
      get_descendants "$pid" |
        while read -r p; do
          ps -p "$p" -o %cpu= -o rss= 2>/dev/null || true
        done |
        awk '
            { cpu += $1; rss += $2; n += 1 }
            END {
              if (n > 0) printf "%.2f %.0f\n", cpu, rss
            }
          '

      sleep 0.5
    done
  ) >>"$log_file" 2>/dev/null &
  local stats_pid=$!
  STATS_PIDS+=("$stats_pid")
  register_pid "$stats_pid"
}


start_fd_tracker() {
  local server_pid="$1"
  local loadgen_pid="$2"
  local log_file="$3"

  : >"$log_file"
  (
    while kill -0 "$loadgen_pid" 2>/dev/null; do
      local server_fd loadgen_fd
      server_fd="$(fd_count_for_pid "$server_pid")"
      loadgen_fd="$(fd_count_for_pid "$loadgen_pid")"
      printf '%s %s\n' "${server_fd:-0}" "${loadgen_fd:-0}"
      sleep 0.2
    done
  ) >>"$log_file" 2>/dev/null &
  local fd_pid=$!
  STATS_PIDS+=("$fd_pid")
  register_pid "$fd_pid"
}


max_fd_from_log() {
  local log_file="$1"
  local column="$2"
  awk -v col="$column" '{ if ($col ~ /^[0-9]+$/ && $col > max) max = $col } END { if (max == "") print 0; else print max }' "$log_file" 2>/dev/null
}

# --- VARIANTS ---

