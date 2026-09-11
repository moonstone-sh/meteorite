--- Meteorite owns refresh decisions; Clingy owns the OS process group.
local dev_command = {}

function dev_command.run(argv, deps)
  deps = deps or {}
  local process = deps.process or require("clingy.process")
  assert(process.supervisor_script, "meteorite dev requires Clingy >= 0.6.2; run moon sync")
  local quote = deps.shell_quote
  local request = deps.build_request.parse({ table.unpack(argv, 2) })
  deps.build_request.require_behavior(request, "meteorite dev")
  local cli = deps.package_cli_file()
  local root = deps.current_dir()
  local build_command = table.concat({
    "zig build --build-file", quote(deps.package_build_file()),
    "-Dproject-root=" .. quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current",
    table.concat(deps.build_request.to_build_flags(request, quote), " "),
    "install-server --", quote(root .. "/dist/server"),
  }, " ")
  local lua = os.getenv("LUA_BIN") or (deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua")
  local script = process.supervisor_script({
    label = "Meteorite dev",
    cwd = root,
    argv = { lua, deps.package_dev_file(), root .. "/src/main.lua", root .. "/.meteorite/graph/current",
      request.mode, request.backend, build_command, root .. "/dist/server" },
    env = { METEORITE_CLI = cli, METEORITE_BUILD_COMMAND = build_command },
    stdin_eof = true,
    lock_dir = root .. "/.meteorite/dev/session.lock",
    cleanup_files = { root .. "/.meteorite/dev/server.pid" },
  })
  local script_file = root .. "/.meteorite/dev/supervisor.sh"
  local write = deps.write_file or function(path, content)
    local ok = os.execute("mkdir -p " .. quote(root .. "/.meteorite/dev"))
    assert(ok == true or ok == 0, "cannot create Meteorite dev state directory")
    local file = assert(io.open(path, "w"))
    assert(file:write(content))
    assert(file:close())
  end
  write(script_file, script)
  if deps.prepare_only then return end

  -- The package launcher execs Bash after this Lua preflight. For direct Lua
  -- invocations the same supervisor also detects loss of its original parent.
  if not deps.run_command("exec bash " .. quote(script_file)) then os.exit(1) end
end

return dev_command
