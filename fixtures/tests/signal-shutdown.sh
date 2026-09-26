#!/usr/bin/env bash
# Regression coverage for the "compiled server ignores SIGINT/SIGTERM while
# idle" bug: zig/server/signals.zig installed handlers that only set an
# atomic flag, and zig/meteorite.zig's accept loop only checked that flag
# immediately before a *blocking* accept() call, so a signal delivered while
# already blocked there was invisible until the next real connection woke
# the loop up (Zig's std.Io accept retries on EINTR internally). Idle
# servers -- the common case for `docker stop` / Ctrl-C / CI teardown --
# would not exit until something else connected to them.
#
# The fix (zig/server/signals.zig + zig/meteorite.zig) adds a self-pipe the
# accept loop polls alongside the listening socket, so a signal always wakes
# it immediately. This script exercises the resulting contract end to end
# against a real compiled server binary:
#   1. idle SIGTERM  -> exits quickly, exit code 0
#   2. idle SIGINT   -> exits quickly, exit code 0
#   3. a request already in flight finishes during graceful shutdown
#   4. a second SIGINT/SIGTERM forces an immediate exit (128+signal),
#      pre-empting a graceful wait that would otherwise still be running
set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
meteorite_test_setup
meteorite_test_trap "signal-shutdown"

if [[ "${METEORITE_BASIC_SERVICE_BUILT:-0}" != "1" ]]; then
  bash fixtures/tests/basic-service-build.sh
fi

source "fixtures/tests/cleanup.sh"

clear_port_8080() {
  while read -r pid; do
    [[ -z "${pid:-}" ]] || kill -9 "$pid" 2>/dev/null || true
  done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
}

# Starts dist/server in the background directly in the caller's shell (never
# through `$(...)`, which would fork a subshell and make the pid it prints
# unwaitable -- `wait` only reports a real exit status for this shell's own
# direct children) and waits for it to bind :8080. Sets SERVER_PID. Fails
# the test if the server never comes up.
start_server() {
  local log="$1"
  clear_port_8080
  fixtures/apps/basic-service/dist/server >"$log" 2>&1 &
  SERVER_PID=$!
  register_pid "$SERVER_PID"
  for _ in $(seq 1 50); do
    lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null | grep -q "^$SERVER_PID\$" && return 0
    sleep 0.1
  done
  echo "signal-shutdown: server never bound :8080 (see $log)" >&2
  cat "$log" >&2 || true
  exit 1
}

# Polls `kill -0` until the pid is gone or `timeout_s` elapses. Prints the
# elapsed time in milliseconds; the caller decides pass/fail from that.
wait_for_exit_ms() {
  local pid="$1"
  local timeout_s="$2"
  local start end
  start="$(date +%s%N)"
  local deadline_steps=$(( timeout_s * 20 ))
  for _ in $(seq 1 "$deadline_steps"); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  end="$(date +%s%N)"
  echo $(( (end - start) / 1000000 ))
}

# --- Test 1 & 2: idle SIGINT/SIGTERM exit quickly with code 0 -------------
# Run each server directly under this script's own shell (not a subshell)
# so `wait` reports its real exit status, matching fixtures/tests/
# release-smoke.sh's pattern for the same reason.
assert_idle_signal_exit() {
  local sig="$1"
  local log="/tmp/meteorite-signal-shutdown-idle-$sig.log"
  start_server "$log"
  local pid="$SERVER_PID"
  kill "-$sig" "$pid"

  local elapsed_ms
  elapsed_ms="$(wait_for_exit_ms "$pid" 2)"
  if kill -0 "$pid" 2>/dev/null; then
    echo "FAIL: idle SIG$sig: server still alive after 2s (see $log)" >&2
    kill -9 "$pid" 2>/dev/null || true
    unregister_pid "$pid"
    exit 1
  fi
  unregister_pid "$pid"
  local status=0
  wait "$pid" 2>/dev/null || status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: idle SIG$sig: expected exit code 0, got $status (see $log)" >&2
    exit 1
  fi
  if ! grep -q 'Shutting down' "$log"; then
    echo "FAIL: idle SIG$sig: server never logged a graceful shutdown (see $log)" >&2
    exit 1
  fi
  echo "PASS: idle SIG$sig exits in ${elapsed_ms}ms with code 0"
}

assert_idle_signal_exit TERM
assert_idle_signal_exit INT

# --- Test 3: a request already in flight finishes during graceful shutdown
log3="/tmp/meteorite-signal-shutdown-inflight.log"
start_server "$log3"
server_pid="$SERVER_PID"

curl_out="/tmp/meteorite-signal-shutdown-inflight-body.txt"
rm -f "$curl_out"
curl -sS -o "$curl_out" http://127.0.0.1:8080/__test/sleep-1s &
curl_pid=$!
sleep 0.2 # let the request actually reach the 1s handler before we signal

t0="$(date +%s%N)"
kill -TERM "$server_pid"

wait "$curl_pid"
body="$(cat "$curl_out" 2>/dev/null || true)"
if [[ "$body" != "slept" ]]; then
  echo "FAIL: in-flight request did not complete during graceful shutdown (got '$body', see $log3)" >&2
  exit 1
fi

server_exit_ms="$(wait_for_exit_ms "$server_pid" 3)"
t1="$(date +%s%N)"
total_ms=$(( (t1 - t0) / 1000000 ))
if kill -0 "$server_pid" 2>/dev/null; then
  echo "FAIL: server still alive after in-flight request completed (see $log3)" >&2
  kill -9 "$server_pid" 2>/dev/null || true
  unregister_pid "$server_pid"
  exit 1
fi
unregister_pid "$server_pid"
status=0
wait "$server_pid" 2>/dev/null || status=$?
if [[ "$status" -ne 0 ]]; then
  echo "FAIL: in-flight test: expected exit code 0, got $status (see $log3)" >&2
  exit 1
fi
# The request needs ~1s; a server that shut down without waiting for it
# would exit near-instantly instead. Require it to have taken a real chunk
# of that second, so this test would actually fail if the drain wait were
# ever removed.
if [[ "$total_ms" -lt 700 ]]; then
  echo "FAIL: in-flight test: shutdown finished in ${total_ms}ms, too fast to have waited for a 1s request (see $log3)" >&2
  exit 1
fi
echo "PASS: in-flight request completed (body='$body') and server exited ${server_exit_ms}ms after it did (total ${total_ms}ms), code 0"

# --- Test 4: a second signal forces an immediate exit ---------------------
log4="/tmp/meteorite-signal-shutdown-force.log"
start_server "$log4"
server_pid="$SERVER_PID"

curl -sS -o /dev/null http://127.0.0.1:8080/__test/sleep-1s &
curl_pid=$!
sleep 0.2 # request is in flight; a graceful shutdown here would otherwise wait ~0.8s more

kill -TERM "$server_pid"
sleep 0.1
t0="$(date +%s%N)"
kill -TERM "$server_pid" # second signal: must force an immediate exit

force_exit_ms="$(wait_for_exit_ms "$server_pid" 2)"
t1="$(date +%s%N)"
if kill -0 "$server_pid" 2>/dev/null; then
  echo "FAIL: server still alive after second SIGTERM (see $log4)" >&2
  kill -9 "$server_pid" 2>/dev/null || true
  unregister_pid "$server_pid"
  exit 1
fi
unregister_pid "$server_pid"
status=0
wait "$server_pid" 2>/dev/null || status=$?
kill "$curl_pid" 2>/dev/null || true
wait "$curl_pid" 2>/dev/null || true

if [[ "$status" -ne 143 ]]; then
  echo "FAIL: second SIGTERM: expected exit code 143 (128+SIGTERM), got $status (see $log4)" >&2
  exit 1
fi
# The in-flight request needed another ~0.8s to finish naturally; the forced
# exit must land well before that, or this is just the graceful path again.
if [[ "$force_exit_ms" -gt 500 ]]; then
  echo "FAIL: second SIGTERM took ${force_exit_ms}ms to take effect; expected an immediate forced exit" >&2
  exit 1
fi
echo "PASS: second SIGTERM force-exits in ${force_exit_ms}ms with code 143 (pre-empting the in-flight request's graceful wait)"

echo "PASS: signal-shutdown"
