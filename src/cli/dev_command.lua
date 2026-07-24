--- Meteorite dev command launcher.
local dev_command = {}

function dev_command.run(argv, deps)
  deps = deps or {}
  local quote = deps.shell_quote
  local request = deps.build_request.parse({ table.unpack(argv, 2) })
  deps.build_request.require_behavior(request, "meteorite dev")
  local cli = deps.package_cli_file()
  local root = deps.current_dir()
  local guard = deps.package_guard_file()
  local build_command = table.concat({
    "zig build --build-file", quote(deps.package_build_file()),
    "-Dmeteorite-cli=" .. quote(cli),
    "-Dproject-root=" .. quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current",
    table.concat(deps.build_request.to_build_flags(request, quote), " "),
    "install-server --", quote(root .. "/dist/server"),
  }, " ")
  local lua = deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"
  local inner = table.concat({
    "METEORITE_CLI=" .. quote(cli),
    "METEORITE_GUARD_SCRIPT=" .. quote(guard),
    "METEORITE_BUILD_COMMAND=" .. quote(build_command),
    quote(lua), quote(deps.package_dev_file()),
    quote(root .. "/src/main.lua"), quote(root .. "/.meteorite/graph/current"), quote(request.mode),
  }, " ")
  local cleanup = table.concat({
    "METEORITE_DEV_STATE_DIR=" .. quote(root .. "/.meteorite/dev"),
    "METEORITE_DEV_PID_FILE=" .. quote(root .. "/.meteorite/dev/server.pid"),
    "METEORITE_DEV_SERVER=" .. quote(root .. "/dist/server"),
    quote(guard), "cleanup >/dev/null 2>&1 || true",
  }, " ")
  local command_line = "sh -c " .. quote("trap " .. quote(cleanup) .. " EXIT INT TERM HUP; " .. inner)
  if not deps.run_command(command_line) then os.exit(1) end
end

return dev_command
