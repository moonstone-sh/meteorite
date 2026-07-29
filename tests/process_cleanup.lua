package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local test = require("test")
local fs = require("utils.fs")

local function run_shell(cmd)
  local pipe = io.popen(cmd .. " 2>&1", "r")
  if not pipe then return "", false end
  local output = pipe:read("*a") or ""
  local ok, _, code = pipe:close()
  return output, (ok == true or code == 0)
end

test("guard.sh assert-stopped succeeds when no server or pid file exists", function()
  local state_dir = "/tmp/meteorite-test-guard-clean-" .. os.time()
  local pid_file = state_dir .. "/server.pid"
  os.execute("mkdir -p " .. state_dir)
  os.remove(pid_file)

  local env = "METEORITE_DEV_STATE_DIR=" .. fs.shell_quote(state_dir) ..
              " METEORITE_DEV_PID_FILE=" .. fs.shell_quote(pid_file) ..
              " METEORITE_DEV_PORT=9988"
  local output, ok = run_shell(env .. " bash scripts/guard.sh assert-stopped")
  test.assert_true(ok, "assert-stopped should return 0 when clean: " .. output)

  os.execute("rm -rf " .. state_dir)
end)

test("guard.sh assert-stopped fails when stale pid file exists", function()
  local state_dir = "/tmp/meteorite-test-guard-stale-" .. os.time()
  local pid_file = state_dir .. "/server.pid"
  os.execute("mkdir -p " .. state_dir)
  fs.write_file(pid_file, "999999\n")

  local env = "METEORITE_DEV_STATE_DIR=" .. fs.shell_quote(state_dir) ..
              " METEORITE_DEV_PID_FILE=" .. fs.shell_quote(pid_file) ..
              " METEORITE_DEV_PORT=9988"
  local output, ok = run_shell(env .. " bash scripts/guard.sh assert-stopped")
  test.assert_true(not ok, "assert-stopped should fail when pid file exists")
  test.assert_true(output:find("pid file") ~= nil, "output should mention pid file")

  os.execute("rm -rf " .. state_dir)
end)

test("guard.sh cleanup removes pid file and stops server", function()
  local state_dir = "/tmp/meteorite-test-guard-cleanup-" .. os.time()
  local pid_file = state_dir .. "/server.pid"
  os.execute("mkdir -p " .. state_dir)
  fs.write_file(pid_file, "123456\n")

  local env = "METEORITE_DEV_STATE_DIR=" .. fs.shell_quote(state_dir) ..
              " METEORITE_DEV_PID_FILE=" .. fs.shell_quote(pid_file) ..
              " METEORITE_DEV_PORT=9988"
  run_shell(env .. " bash scripts/guard.sh cleanup")
  test.assert_eq(fs.read_file(pid_file), nil, "cleanup should remove pid file")

  os.execute("rm -rf " .. state_dir)
end)

test("supervisor shell trap responds to SIGINT with code 130 and ordered output", function()
  local state_dir = "/tmp/meteorite-test-sigint-" .. os.time()
  local pid_file = state_dir .. "/server.pid"
  os.execute("mkdir -p " .. state_dir)

  local test_script = string.format([[
export METEORITE_DEV_STATE_DIR=%s
export METEORITE_DEV_PID_FILE=%s
export METEORITE_DEV_PORT=9989
GUARD='scripts/guard.sh'
cleanup_done=0
dev_pid=""
exit_status=0

cleanup() {
  if [ "$cleanup_done" -eq 1 ]; then return 0; fi
  cleanup_done=1
  if [ -n "$dev_pid" ] && kill -0 "$dev_pid" 2>/dev/null; then
    printf '%%s\n' "Meteorite dev: stopping supervisor pid=$dev_pid..." >&2
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  printf '%%s\n' "Meteorite dev: cleaning up server processes..." >&2
  "$GUARD" cleanup >/dev/null 2>&1 || true
  printf '%%s\n' "Meteorite dev: cleaning up stale sessions..." >&2
  "$GUARD" cleanup-sessions >/dev/null 2>&1 || true
  if "$GUARD" assert-stopped >/dev/null 2>&1; then
    printf '%%s\n' "Meteorite dev: server stopped." >&2
  fi
  printf '%%s\n' "Meteorite dev: cleanup complete." >&2
}

on_signal() {
  sig_name="$1"
  sig_code="$2"
  trap - INT TERM HUP
  printf '%%s\n' "Meteorite dev: caught $sig_name; shutting down..." >&2
  exit_status="$sig_code"
  cleanup
  trap - EXIT
  exit "$sig_code"
}

trap 'on_signal SIGINT 130' INT
trap 'on_signal SIGTERM 143' TERM
trap 'on_signal SIGHUP 129' HUP
trap 'cleanup' EXIT

sleep 30 &
dev_pid=$!
wait "$dev_pid" 2>/dev/null
]], fs.shell_quote(state_dir), fs.shell_quote(pid_file))

  local script_file = state_dir .. "/test_supervisor.sh"
  fs.write_file(script_file, test_script)

  -- Spawn script in background, wait 0.2s, then send SIGINT
  local pipe = io.popen("sh " .. fs.shell_quote(script_file) .. " 2>&1 & echo $!", "r")
  local pid = pipe and pipe:read("*a"):match("%d+")
  if pipe then pipe:close() end

  test.assert_true(pid ~= nil, "should spawn test supervisor")
  os.execute("sleep 0.3")

  -- Send SIGINT
  os.execute("kill -INT " .. pid .. " 2>/dev/null")
  os.execute("sleep 0.5")

  test.assert_true(os.execute("kill -0 " .. pid .. " 2>/dev/null") == nil, "supervisor should have exited on SIGINT")

  os.execute("rm -rf " .. state_dir)
end)

test.run()
