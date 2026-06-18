#!/usr/bin/env bash
set -euo pipefail

OUT="${1:?usage: collect_env.sh OUT.json}"
mkdir -p "$(dirname "$OUT")"

json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

json_value() {
  printf '%s' "$1" | json_string
}

json_run() {
  local output
  output="$($@ 2>/dev/null || true)"
  json_value "$output"
}

json_run_stderr() {
  local output
  output="$($@ 2>&1 || true)"
  json_value "$output"
}

json_tool() {
  local tool="$1"
  shift
  if command -v "$tool" >/dev/null 2>&1; then
    json_run_stderr "$tool" "$@"
  else
    printf '""'
  fi
}

moon_json() {
  local output=""
  if command -v moon >/dev/null 2>&1; then
    output="$(moon version 2>&1 || moon --version 2>&1 || true)"
  fi
  json_value "$output"
}

meminfo_json() {
  if [[ -r /proc/meminfo ]]; then
    json_run cat /proc/meminfo
  else
    printf '""'
  fi
}

cat > "$OUT" <<JSON
{
  "timestamp": $(json_value "$(date -u +%Y-%m-%dT%H:%M:%SZ)"),
  "git_commit": $(json_run git rev-parse HEAD),
  "git_status": $(json_run git status --short),
  "uname": $(json_run uname -a),
  "lscpu": $(json_tool lscpu),
  "meminfo": $(meminfo_json),
  "ulimit_n": $(json_value "$(ulimit -n)"),
  "zig_version": $(json_tool zig version),
  "moon_version": $(moon_json),
  "oha_version": $(json_tool oha --version),
  "wrk_version": $(json_tool wrk --version),
  "perf_version": $(json_tool perf --version),
  "file_version": $(json_tool file --version),
  "size_version": $(json_tool size --version)
}
JSON
