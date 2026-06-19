#!/usr/bin/env bash
set -euo pipefail

PID="${1:?usage: collect_memory.sh PID OUT.csv}"
OUT="${2:?usage: collect_memory.sh PID OUT.csv}"

echo "ts_ms,rss_kb,vsz_kb,threads" > "$OUT"

OS="$(uname -s)"

while kill -0 "$PID" 2>/dev/null; do
  ts="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

  rss="n/a"
  vsz="n/a"
  threads="n/a"

  if [[ "$OS" == "Linux" ]]; then
    if [[ -r "/proc/$PID/status" ]]; then
      rss="$(awk '/VmRSS:/ {print $2}' "/proc/$PID/status" 2>/dev/null || echo "n/a")"
      vsz="$(awk '/VmSize:/ {print $2}' "/proc/$PID/status" 2>/dev/null || echo "n/a")"
      threads="$(awk '/Threads:/ {print $2}' "/proc/$PID/status" 2>/dev/null || echo "n/a")"
    fi
  elif [[ "$OS" == "Darwin" ]]; then
    # Darwin ps supports different field sets. Try to get threads, but do not
    # fall back to a bogus zero if unavailable.
    if out="$(ps -o rss=,vsz=,nlwp= -p "$PID" 2>/dev/null)"; then
      read -r rss vsz threads <<< "$out"
    elif out="$(ps -o rss=,vsz= -p "$PID" 2>/dev/null)"; then
      read -r rss vsz <<< "$out"
      threads="n/a"
    fi
  fi

  # Default any empty or zero/null values to n/a if they are unsupported or empty
  rss="${rss:-n/a}"
  vsz="${vsz:-n/a}"
  threads="${threads:-n/a}"

  # Trim spaces
  rss="$(echo "$rss" | xargs)"
  vsz="$(echo "$vsz" | xargs)"
  threads="$(echo "$threads" | xargs)"

  if [[ -z "$rss" || "$rss" == "0" ]]; then rss="n/a"; fi
  if [[ -z "$vsz" || "$vsz" == "0" ]]; then vsz="n/a"; fi
  if [[ -z "$threads" || "$threads" == "0" ]]; then threads="n/a"; fi

  echo "$ts,$rss,$vsz,$threads" >> "$OUT"
  sleep 0.2
done

