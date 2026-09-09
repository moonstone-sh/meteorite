package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local test = require("test")

--- Regression coverage for the real clingy CLI schema in src/cli/main.lua.
--- Every other test in this suite exercises main.lua only as a path STRING
--- (see build_request.lua's package_cli_file mocks) -- none of them ever
--- actually build the clingy declaration graph. That gap is exactly how
--- meteorite 0.2.1 shipped with a CLI that crashed on startup against a
--- fresh clingy 0.3.0 resolve (varargs-style c.flag/c.option calls, and
--- calls to c.repeated/c.optional that 0.3.0 removed/repurposed) with
--- every existing test still green. This file shells out to the real
--- `lua src/cli/main.lua ...` entry point so a future clingy upgrade (or
--- any other change to the declaration graph) that breaks CLI startup, or
--- a command whose help page silently regresses to the "unknown help
--- topic" fallback, fails a real, fast test instead of shipping silently.

local function lua_bin()
  local f = io.open(".moonstone/env/bin/lua", "rb")
  if f then f:close(); return ".moonstone/env/bin/lua" end
  return os.getenv("LUA_BIN") or "lua"
end

-- Every subdirectory of .moonstone/env/share/lua/<abi> (clingy, valua, ...)
-- needs to be on the subprocess's LUA_PATH -- main.lua's own package.path
-- setup only ever adds itself and the install root, not the toolchain's
-- installed dependencies; a real invocation normally gets this from the
-- environment `moon exec` sets up. Discovered by running the CLI directly
-- without this and observing `module 'clingy' not found`, not assumed.
local function env_lua_path()
  local parts = {}
  local base = ".moonstone/env/share/lua"
  local handle = io.popen('ls "' .. base .. '" 2>/dev/null')
  if handle then
    for abi in handle:lines() do
      parts[#parts + 1] = base .. "/" .. abi .. "/?.lua"
      parts[#parts + 1] = base .. "/" .. abi .. "/?/init.lua"
    end
    handle:close()
  end
  return table.concat(parts, ";")
end

local LUA_PATH = "src/?.lua;src/?/init.lua;" .. env_lua_path() .. ";;"

--- Runs `lua src/cli/main.lua <args...>`, returns (ok, output).
--- `ok` reflects the real process exit status (via a sentinel line, since
--- Lua 5.1/5.4 os.execute/io.popen exit-code reporting differs and this
--- only needs to distinguish "exited 0" from anything else).
local function run_cli(args)
  local cmd = "LUA_PATH=" .. string.format("%q", LUA_PATH)
    .. " " .. lua_bin() .. " src/cli/main.lua " .. args
    .. "; echo EXIT:$?"
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then return false, "" end
  local output = handle:read("*a") or ""
  handle:close()
  local exit_code = tonumber(output:match("EXIT:(%d+)%s*$"))
  output = output:gsub("EXIT:%d+%s*$", "")
  return exit_code == 0, output
end

local COMMANDS = {
  "init", "build", "check", "dev", "doctor", "client",
  "openapi", "ipc", "routes", "graph", "sync", "invoke",
}

test("bare --help runs the real clingy schema without crashing", function()
  local ok, output = run_cli("--help")
  test.assert_true(ok, "exit 0")
  test.assert_true(output:find("Usage:", 1, true) ~= nil, "prints usage")
  test.assert_false(output:find("stack traceback", 1, true) ~= nil, "no Lua traceback")
  test.assert_false(output:find("module '", 1, true) ~= nil, "no module-not-found error")
end)

for _, command in ipairs(COMMANDS) do
  test("`meteorite " .. command .. " --help` runs and prints its own help page", function()
    local ok, output = run_cli("help " .. command)
    test.assert_true(ok, "exit 0 for `help " .. command .. "`")
    test.assert_false(output:find("stack traceback", 1, true) ~= nil, command .. ": no Lua traceback")
    test.assert_false(output:find("attempt to call", 1, true) ~= nil, command .. ": no attempt-to-call error")
    test.assert_false(output:find("unknown help topic", 1, true) ~= nil, command .. ": has a real help page, not the fallback")
    test.assert_true(output:find("Meteorite " .. command, 1, true) ~= nil
      or output:find("Usage:", 1, true) ~= nil, command .. ": prints real command-specific content")
  end)
end

test("every command in help.main's list has its own help page", function()
  local help = require("cli.help_text")
  for _, command in ipairs(COMMANDS) do
    test.assert_true(help[command] ~= nil, "help_text has no page for `" .. command .. "`")
  end
end)

test.run()
