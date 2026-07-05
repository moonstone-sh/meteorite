#!/usr/bin/env bash
set -euo pipefail

num_or_zero() {
  case "${1:-}" in
  '' | *[!0-9]*) printf '0' ;;
  *) printf '%s' "$1" ;;
  esac
}


sysctl_value() {
  local key="$1"
  local value
  value="$(sysctl -n "$key" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    printf 'not_available'
  else
    printf '%s' "$value"
  fi
}


first_available_sysctl() {
  local key value
  for key in "$@"; do
    value="$(sysctl_value "$key")"
    if [[ "$value" != "not_available" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf 'not_available'
}


max_concurrency_requested() {
  local max=0 c
  for c in "${CONCURRENCY_VALUES[@]}"; do
    if ((c > max)); then max=$c; fi
  done
  printf '%s' "$max"
}


loadgen_version_safe() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing'
    return 0
  fi
  case "$tool" in
  wrk) wrk -v 2>&1 | head -n 1 || printf unknown ;;
  oha) env -u NO_COLOR oha --version 2>&1 | head -n 1 || printf unknown ;;
  *) printf unknown ;;
  esac
}


loadgen_path_safe() {
  command -v "$1" 2>/dev/null || printf 'missing'
}


launchctl_maxfiles() {
  if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]] || ! command -v launchctl >/dev/null 2>&1; then
    printf 'not_available not_available'
    return 0
  fi
  launchctl limit maxfiles 2>/dev/null | awk 'NR==2 { print $2, $3; found=1 } END { if (!found) print "not_available not_available" }'
}


check_interrupted() {
  if [[ $_INTERRUPTED -eq 1 ]]; then
    echo "Interrupted!" >&2
    exit 130
  fi
}


require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "error: $name is required for this benchmark target" >&2
    exit 127
  fi
}


get_descendants() {
  local pid="$1"
  local child

  echo "$pid"

  while IFS= read -r child; do
    get_descendants "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  return 0
}


wait_for_exit() {
  local pid="$1"
  local attempts="${2:-20}"
  for _ in $(seq 1 "$attempts"); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}


latency_to_us() {
  python3 -c 'import sys
v=sys.argv[1].strip()
try:
    if v.endswith("ms"):
        print(int(round(float(v[:-2]) * 1000)))
    elif v.endswith("us"):
        print(int(round(float(v[:-2]))))
    elif v.endswith("s"):
        print(int(round(float(v[:-1]) * 1000000)))
    else:
        print(int(round(float(v))))
except Exception:
    print(0)' "$1"
}


sanitize_text_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 -c 'from pathlib import Path
import re, sys
p = Path(sys.argv[1])
text = p.read_text(errors="replace")
text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
text = "".join(ch for ch in text if ch in "\n\r\t" or ord(ch) >= 32)
p.write_text(text)' "$file"
}


loadgen_version() {
  case "$LOADGEN" in
  wrk) wrk -v 2>&1 | head -n 1 || printf unknown ;;
  oha) env -u NO_COLOR oha --version 2>&1 | head -n 1 || printf unknown ;;
  esac
}


fd_count_for_pid() {
  local pid="$1"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    printf '0'
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -p "$pid" 2>/dev/null | awk 'END { if (NR > 0) print NR - 1; else print 0 }'
    return 0
  fi
  if [[ -d "/proc/$pid/fd" ]]; then
    find "/proc/$pid/fd" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' '
    return 0
  fi
  printf '0'
}


system_env_field() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { value = substr($0, index($0, "=") + 1) } END { print value }' "$OUT/system.env" 2>/dev/null
}


