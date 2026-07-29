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
    "export METEORITE_CLI=" .. quote(cli),
    "METEORITE_GUARD_SCRIPT=" .. quote(guard),
    "METEORITE_BUILD_COMMAND=" .. quote(build_command) .. ";",
    "exec " .. quote(lua), quote(deps.package_dev_file()),
    quote(root .. "/src/main.lua"), quote(root .. "/.meteorite/graph/current"), quote(request.mode), quote(request.backend),
    quote(build_command), quote(root .. "/dist/server"),
  }, " ")
  local script = table.concat({
    "# Supervisor Process Topology:\n",
    "# The wrapper shell script acts as the signal-owning supervisor.\n",
    "# It sets environment variables, launches dev.lua as a managed child (dev_pid=$!),\n",
    "# and installs signal traps for INT, TERM, HUP, and EXIT.\n",
    "export METEORITE_DEV_STATE_DIR=" .. quote(root .. "/.meteorite/dev") .. "\n",
    "export METEORITE_DEV_PID_FILE=" .. quote(root .. "/.meteorite/dev/server.pid") .. "\n",
    "export METEORITE_DEV_SERVER=" .. quote(root .. "/dist/server") .. "\n",
    "GUARD=" .. quote(guard) .. "\n",
    "cleanup_done=0\n",
    "dev_pid=\"\"\n",
    "exit_status=0\n",
    "\n",
    "cleanup() {\n",
    "  if [ \"$cleanup_done\" -eq 1 ]; then\n",
    "    return 0\n",
    "  fi\n",
    "  cleanup_done=1\n",
    "  server_pid=$(sed -n 's/[^0-9].*$//; /^[0-9][0-9]*$/p; q' \"$METEORITE_DEV_PID_FILE\" 2>/dev/null || true)\n",
    "  if [ -n \"$server_pid\" ]; then\n",
    "    printf '%s\\n' \"Meteorite dev: shutting down Meteorite dev server PID=$server_pid...\" >&2\n",
    "  fi\n",
    "  if [ -n \"$dev_pid\" ] && kill -0 \"$dev_pid\" 2>/dev/null; then\n",
    "    printf '%s\\n' \"Meteorite dev: stopping supervisor pid=$dev_pid...\" >&2\n",
    "    kill -TERM \"$dev_pid\" 2>/dev/null || true\n",
    "    i=0\n",
    "    while kill -0 \"$dev_pid\" 2>/dev/null && [ \"$i\" -lt 20 ]; do\n",
    "      sleep 0.1 2>/dev/null || sleep 1\n",
    "      i=$((i + 1))\n",
    "    done\n",
    "    if kill -0 \"$dev_pid\" 2>/dev/null; then\n",
    "      printf '%s\\n' \"Meteorite dev: force stopping supervisor pid=$dev_pid...\" >&2\n",
    "      kill -KILL \"$dev_pid\" 2>/dev/null || true\n",
    "    fi\n",
    "    wait \"$dev_pid\" 2>/dev/null || true\n",
    "  fi\n",
    "  cleanup_failed=0\n",
    "  printf '%s\\n' \"Meteorite dev: cleaning up server processes...\" >&2\n",
    "  if ! \"$GUARD\" cleanup; then\n",
    "    cleanup_failed=1\n",
    "    printf '%s\\n' \"Meteorite dev: server cleanup reported an error.\" >&2\n",
    "  fi\n",
    "  printf '%s\\n' \"Meteorite dev: cleaning up stale sessions...\" >&2\n",
    "  if ! \"$GUARD\" cleanup-sessions; then\n",
    "    cleanup_failed=1\n",
    "    printf '%s\\n' \"Meteorite dev: stale-session cleanup reported an error.\" >&2\n",
    "  fi\n",
    "  if \"$GUARD\" assert-stopped >/dev/null 2>&1; then\n",
    "    printf '%s\\n' \"Meteorite dev: server stopped.\" >&2\n",
    "  else\n",
    "    printf '%s\\n' \"Meteorite dev: warning: server still appears to be running.\" >&2\n",
    "  fi\n",
    "  if [ \"$cleanup_failed\" -eq 0 ]; then\n",
    "    printf '%s\\n' \"Meteorite dev: cleanup complete.\" >&2\n",
    "  else\n",
    "    printf '%s\\n' \"Meteorite dev: cleanup completed with errors.\" >&2\n",
    "  fi\n",
    "}\n",
    "\n",
    "on_signal() {\n",
    "  sig_name=\"$1\"\n",
    "  sig_code=\"$2\"\n",
    "  trap - INT TERM HUP\n",
    "  printf '%s\\n' \"Meteorite dev: caught $sig_name; shutting down...\" >&2\n",
    "  exit_status=\"$sig_code\"\n",
    "  cleanup\n",
    "  trap - EXIT\n",
    "  exit \"$sig_code\"\n",
    "}\n",
    "\n",
    "trap 'on_signal SIGINT 130' INT\n",
    "trap 'on_signal SIGTERM 143' TERM\n",
    "trap 'on_signal SIGHUP 129' HUP\n",
    "trap 'cleanup' EXIT\n",
    "\n",
    "\"$GUARD\" handoff >/dev/null 2>&1 || true\n",
    "\n",
    "(trap - INT TERM HUP; " .. inner .. ") &\n",
    "dev_pid=$!\n",
    "wait \"$dev_pid\" 2>/dev/null\n",
    "child_code=$?\n",
    "if [ \"$exit_status\" -eq 0 ]; then\n",
    "  exit_status=\"$child_code\"\n",
    "fi\n",
    "cleanup\n",
    "trap - EXIT\n",
    "exit \"$exit_status\"\n",
  }, "")
  local script_file = root .. "/.meteorite/dev/supervisor.sh"
  local write = deps.write_file or function(path, content)
    os.execute("mkdir -p " .. quote(root .. "/.meteorite/dev"))
    local f = io.open(path, "w")
    if f then f:write(content); f:close() end
  end
  write(script_file, script)

  -- The package launcher runs this preflight with
  -- METEORITE_DEV_PREPARE_ONLY=1, then execs the script directly. Keeping the
  -- signal-owning shell outside Lua avoids Lua's os.execute/system() signal
  -- disposition changes while the supervisor is active.
  if deps.prepare_only then return end

  -- Direct Lua CLI invocation remains supported for development use.
  local command_line = "exec sh " .. quote(script_file)
  if not deps.run_command(command_line) then os.exit(1) end
end

return dev_command
