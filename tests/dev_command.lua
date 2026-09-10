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
end)

test.run()
