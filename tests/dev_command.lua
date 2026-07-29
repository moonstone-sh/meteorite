package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local test = require("test")
local dev_command = require("cli.dev_command")

test("dev_command writes supervisor script to file and execs into it", function()
  local ran_command = nil
  local written_file = nil
  local written_content = nil
  local mock_deps = {
    shell_quote = function(v) return "'" .. tostring(v) .. "'" end,
    current_dir = function() return "/tmp/mock-project" end,
    package_cli_file = function() return "/tmp/mock-meteorite/cli/main.lua" end,
    package_build_file = function() return "/tmp/mock-meteorite/build.zig" end,
    package_dev_file = function() return "/tmp/mock-meteorite/cli/dev.lua" end,
    package_guard_file = function() return "/tmp/mock-meteorite/scripts/guard.sh" end,
    read_file = function() return "lua" end,
    write_file = function(path, content)
      written_file = path
      written_content = content
    end,
    run_command = function(cmd)
      ran_command = cmd
      return true
    end,
    build_request = {
      parse = function() return { mode = "hybrid", backend = "fast_http" } end,
      require_behavior = function() end,
      to_build_flags = function() return {} end,
    },
  }

  dev_command.run({ "dev" }, mock_deps)

  -- Assert script was written to file
  test.assert_true(written_file ~= nil, "write_file should have been called")
  test.assert_true(written_file:find("supervisor%.sh") ~= nil, "script file should be supervisor.sh")
  test.assert_true(written_content ~= nil, "script content should not be nil")

  -- Assert exec sh invocation (no python, no sh -c)
  test.assert_true(ran_command ~= nil, "run_command should have been invoked")
  test.assert_true(ran_command:find("^exec sh ") ~= nil, "command should use exec sh")
  test.assert_true(ran_command:find("supervisor%.sh") ~= nil, "command should reference the script file")
  test.assert_true(ran_command:find("python") == nil, "command should not use python")

  -- Assert trap structure in script content
  local script = written_content
  test.assert_true(script:find("trap 'on_signal SIGINT 130' INT") ~= nil, "should trap INT with 130")
  test.assert_true(script:find("trap 'on_signal SIGTERM 143' TERM") ~= nil, "should trap TERM with 143")
  test.assert_true(script:find("trap 'on_signal SIGHUP 129' HUP") ~= nil, "should trap HUP with 129")
  test.assert_true(script:find("trap 'cleanup' EXIT") ~= nil, "should trap EXIT")

  -- Assert signal logging
  test.assert_true(script:find("caught $sig_name; shutting down") ~= nil, "should log caught signal")
  test.assert_true(script:find("trap %- INT TERM HUP") ~= nil, "should disable signals on trap entry")

  -- Assert idempotency guard
  test.assert_true(script:find("cleanup_done=0") ~= nil, "should initialize cleanup_done guard")
  test.assert_true(script:find("cleanup_done=1") ~= nil, "should set cleanup_done inside cleanup")

  -- Assert ordered cleanup logging and guard invocations
  test.assert_true(script:find("stopping supervisor") ~= nil, "should log stopping supervisor")
  test.assert_true(script:find("cleaning up server processes") ~= nil, "should log cleaning server processes")
  test.assert_true(script:find("cleaning up stale sessions") ~= nil, "should log cleaning stale sessions")
  test.assert_true(script:find('"$GUARD" cleanup') ~= nil, "should run guard cleanup")
  test.assert_true(script:find('"$GUARD" cleanup%-sessions') ~= nil, "should run guard cleanup-sessions")
  test.assert_true(script:find('"$GUARD" assert%-stopped') ~= nil, "should run guard assert-stopped")
  test.assert_true(script:find("cleanup complete") ~= nil, "should log cleanup complete")
end)

test.run()
