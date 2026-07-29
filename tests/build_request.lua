package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local request = require("meteorite.build_request")
local templates = require("cli.templates")
local test = require("test")

test "build request keeps the last repeated behavior flag" (function()
  local parsed = request.parse({
    "--mode", "hybrid_dev",
    "--backend", "std_http",
    "--backend=fast_http",
    "--hybrid-profile", "optimized",
  })
  request.require_behavior(parsed)
  test.assert_eq(parsed.mode, "hybrid_dev")
  test.assert_eq(parsed.backend, "fast_http")
  test.assert_eq(parsed.hybrid_profile, "optimized")
end)

test "build request rejects incomplete direct invocations" (function()
  test.assert_error(function()
    request.require_behavior(request.parse({ "--mode", "hybrid" }), "meteorite build")
  end, "--backend")
end)

test "build request renders explicit CLI arguments" (function()
  local parsed = request.parse({ "--mode", "hybrid", "--backend", "fast_http", "--hybrid-profile", "optimized" })
  test.assert_table_eq(request.to_cli_args(parsed), {
    "build", "--mode", "hybrid", "--backend", "fast_http", "--hybrid-profile", "optimized",
  })
end)

test "generated manifests keep behavior explicit and generate the full partiture suite" (function()
  local manifest = templates.moonstone_manifest("example", "hybrid")
  test.assert_true(manifest:find("--mode hybrid_dev --backend fast_http", 1, true) ~= nil, "dev script")
  test.assert_true(manifest:find("check:release", 1, true) ~= nil, "release check")
  test.assert_false(manifest:find("[server]", 1, true) ~= nil, "no server section")
  test.assert_false(manifest:find("[meteorite]", 1, true) ~= nil, "no hidden Meteorite section")
  for _, factory in ipairs({ "partiture_common", "release_partiture", "dev_partiture", "watch_partiture", "check_partiture" }) do
    local chunk, err = load(templates[factory]())
    test.assert_true(chunk ~= nil, factory .. ": " .. tostring(err))
  end
end)

test "dev command passes mode and backend to dev supervisor" (function()
  local dev_command = require("cli.dev_command")
  local captured_command = nil
  local written_content = nil
  dev_command.run({ "dev", "--mode", "hybrid", "--backend", "fast_http" }, {
    shell_quote = function(val) return "'" .. tostring(val) .. "'" end,
    build_request = request,
    package_cli_file = function() return "src/cli/main.lua" end,
    current_dir = function() return "/app" end,
    package_guard_file = function() return "scripts/guard.sh" end,
    package_build_file = function() return "build.zig" end,
    package_dev_file = function() return "src/cli/dev.lua" end,
    read_file = function() return nil end,
    write_file = function(_, content) written_content = content end,
    run_command = function(cmd) captured_command = cmd; return true end,
  })
  test.assert_true(captured_command ~= nil, "command captured")
  test.assert_true(written_content ~= nil, "script written")
  test.assert_true(written_content:find("'src/cli/dev.lua' '/app/src/main.lua' '/app/.meteorite/graph/current' 'hybrid' 'fast_http'", 1, true) ~= nil, "passes backend to dev.lua")
end)

test.run()
