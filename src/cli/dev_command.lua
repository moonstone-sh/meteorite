--- Meteorite dev command launcher.

local dev_command = {}

local function unix_socket_build_flags(config, shell_quote)
  local flags = {}
  if config and config.path then flags[#flags + 1] = "-Dunix-socket-path=" .. shell_quote(config.path) end
  if config and config.mode then flags[#flags + 1] = "-Dunix-socket-mode=" .. shell_quote(config.mode) end
  if config and config.unlink_stale ~= nil then flags[#flags + 1] = "-Dunix-socket-unlink-stale=" .. tostring(config.unlink_stale) end
  return table.concat(flags, " ")
end

function dev_command.run(deps)
  deps = deps or {}
  local shell_quote = deps.shell_quote
  local cli = deps.package_cli_file()
  local root = deps.current_dir()
  local server_config = deps.parse_server_config(root)
  local backend = deps.assert_backend(server_config.backend or "std_http")
  local guard = deps.package_guard_file()
  local build_command = table.concat({
    "zig build --build-file", shell_quote(deps.package_build_file()),
    "-Dmeteorite-cli=" .. shell_quote(cli),
    "-Dproject-root=" .. shell_quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current -Dmode=hybrid_dev -Dbackend=" .. shell_quote(backend) .. " -Dhybrid-profile=optimized -Drouter-dispatch=param_matchers",
    unix_socket_build_flags(server_config.unix_socket, shell_quote),
    "install-server --", shell_quote(root .. "/dist/server"),
  }, " ")
  local lua = deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"
  local dev = deps.package_dev_file()
  local inner = table.concat({
    "METEORITE_CLI=" .. shell_quote(cli),
    "METEORITE_GUARD_SCRIPT=" .. shell_quote(guard),
    "METEORITE_BUILD_COMMAND=" .. shell_quote(build_command),
    shell_quote(lua), shell_quote(dev),
    shell_quote(root .. "/src/main.lua"), shell_quote(root .. "/.meteorite/graph/current"), "hybrid_dev",
  }, " ")
  local cleanup = table.concat({
    "METEORITE_DEV_STATE_DIR=" .. shell_quote(root .. "/.meteorite/dev"),
    "METEORITE_DEV_PID_FILE=" .. shell_quote(root .. "/.meteorite/dev/server.pid"),
    "METEORITE_DEV_SERVER=" .. shell_quote(root .. "/dist/server"),
    shell_quote(guard), "cleanup >/dev/null 2>&1 || true",
  }, " ")
  local command_line = "sh -c " .. shell_quote("trap " .. shell_quote(cleanup) .. " EXIT INT TERM HUP; " .. inner)
  if not deps.run_command(command_line) then os.exit(1) end
end

return dev_command
