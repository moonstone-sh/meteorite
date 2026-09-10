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
              " METEORITE_DEV_PORT=0"
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
              " METEORITE_DEV_PORT=0"
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
              " METEORITE_DEV_PORT=0"
  run_shell(env .. " bash scripts/guard.sh cleanup")
  test.assert_eq(fs.read_file(pid_file), nil, "cleanup should remove pid file")

  os.execute("rm -rf " .. state_dir)
end)

-- Real signal, EOF, process-group and reaping behavior is exercised by
-- Clingy tests/process_supervision.py and the Meteorite launcher integration.

test.run()
