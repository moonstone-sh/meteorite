#!/usr/bin/env bash
# Shared cleanup library for test and bench scripts.
# Source this file at the top of any script that launches background processes.
#
# Usage:
#   source "$(dirname "$0")/cleanup.sh"   # or full path
#   register_pid "$PID"                     # track a background process
#   unregister_pid "$PID"                   # stop tracking (graceful exit)
#   # On EXIT/INT/TERM/HUP, all registered PIDs are killed automatically.

declare -a _CLEANUP_PIDS=()

register_pid() {
  local pid="$1"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    _CLEANUP_PIDS+=("$pid")
  fi
}

unregister_pid() {
  local pid="$1"
  local new_pids=()
  for p in "${_CLEANUP_PIDS[@]:-}"; do
    if [[ "$p" != "$pid" ]]; then
      new_pids+=("$p")
    fi
  done
  _CLEANUP_PIDS=("${new_pids[@]:-}")
}

cleanup_all() {
  # Kill in reverse order (children before parents)
  local i
  for ((i=${#_CLEANUP_PIDS[@]} - 1; i >= 0; i--)); do
    local pid="${_CLEANUP_PIDS[$i]}"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # Kill the process group (negative PID) to get children too
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi
  done
  # Force kill anything still alive after 0.5s
  sleep 0.2
  for pid in "${_CLEANUP_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

# Set trap for ALL signals that should trigger cleanup
trap cleanup_all EXIT INT TERM HUP
