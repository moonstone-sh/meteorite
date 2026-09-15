package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local test = require("test")
local dev_command = require("cli.dev_command")

test("dev command gives Clingy the complete session ownership contract", function()
  local prepared, written, ran
  dev_command.run({ "dev", "--mode", "hybrid", "--backend", "fast_http" }, {
    shell_quote = function(v) return "'" .. tostring(v) .. "'" end,
    current_dir = function() return "/tmp/mock-project" end,
    package_cli_file = function() return "/pkg/cli/main.lua" end,
    package_build_file = function() return "/pkg/build.zig" end,
    package_dev_file = function() return "/pkg/cli/dev.lua" end,
    read_file = function() return true end,
    prepare_only = true,
    process = { supervisor_script = function(opts) prepared = opts; return "generated supervisor" end },
    write_file = function(path, content) written = { path, content } end,
    run_command = function(cmd) ran = cmd; return true end,
    build_request = require("meteorite.build_request"),
  })
  test.assert_true(prepared ~= nil, "Clingy receives the session")
  test.assert_eq(prepared.cwd, "/tmp/mock-project")
  test.assert_eq(prepared.argv[2], "/pkg/cli/dev.lua")
  test.assert_eq(prepared.argv[5], "hybrid")
  test.assert_eq(prepared.argv[6], "fast_http")
  test.assert_true(prepared.stdin_eof, "terminal EOF requests shutdown")
  test.assert_eq(prepared.lock_dir, "/tmp/mock-project/.meteorite/dev/session.lock")
  test.assert_table_eq(prepared.cleanup_files, { "/tmp/mock-project/.meteorite/dev/server.pid" })
  test.assert_eq(prepared.env.METEORITE_CLI, "/pkg/cli/main.lua")
  test.assert_eq(prepared.env.METEORITE_BUILD_COMMAND, prepared.argv[7])
  test.assert_table_eq(written, { "/tmp/mock-project/.meteorite/dev/supervisor.sh", "generated supervisor" })
  test.assert_eq(ran, nil, "preflight must allow the package launcher to exec the owner")
  test.assert_true(not prepared.argv[7]:match("%-Ddev%-events"),
    "a non-dev mode must not compile in the dev-event emitter")
end)

test("dev command wires the dev event stream only for dev-ish modes", function()
  local function build_command_for(build_mode)
    local prepared, made
    dev_command.run({ "dev", "--mode", build_mode, "--backend", "fast_http" }, {
      shell_quote = function(v) return "'" .. tostring(v) .. "'" end,
      current_dir = function() return "/tmp/mock-project" end,
      package_cli_file = function() return "/pkg/cli/main.lua" end,
      package_build_file = function() return "/pkg/build.zig" end,
      package_dev_file = function() return "/pkg/cli/dev.lua" end,
      read_file = function() return true end,
      prepare_only = true,
      mkdir_p = function(dir) made = dir end,
      process = { supervisor_script = function(opts) prepared = opts; return "generated supervisor" end },
      write_file = function() end,
      build_request = require("meteorite.build_request"),
    })
    return prepared.argv[7], made
  end

  local dev_command_line, dev_made = build_command_for("hybrid_dev")
  test.assert_true(dev_command_line:find("-Ddev-events='/tmp/mock-project/.meteorite/dev/events.log'", 1, true) ~= nil,
    "hybrid_dev builds carry the dev event path")
  test.assert_eq(dev_made, "/tmp/mock-project/.meteorite/dev")
  test.assert_true(dev_command_line:find("install-server", 1, true) > dev_command_line:find("-Ddev-events", 1, true),
    "the flag stays a build option, ahead of the step name")

  local release_command_line, release_made = build_command_for("release-static")
  test.assert_true(not release_command_line:match("%-Ddev%-events"), "release builds stay clean")
  test.assert_eq(release_made, nil, "no dev state directory is created for a release build")

  test.assert_eq(dev_command.events_log_path("/srv/app"), "/srv/app/.meteorite/dev/events.log")
end)

test.run()
