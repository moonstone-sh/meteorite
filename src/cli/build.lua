--- Meteorite build command.

local build = {}

local function parse_build_args(argv, deps, start_at, default_mode, root)
  local server_config = deps.parse_server_config(root or deps.current_dir())
  local parsed = {
    mode = default_mode,
    backend = server_config.backend or "std_http",
    unix_socket = server_config.unix_socket or {},
    extras = {},
  }
  local i = start_at
  while i <= #argv do
    local value = argv[i]
    if value == "--help" or value == "-h" then deps.print_help("build"); os.exit(0)
    elseif value == "--mode" then
      i = i + 1
      parsed.mode = argv[i] or parsed.mode
    elseif value and value:match("^%-%-mode=") then
      parsed.mode = value:match("^%-%-mode=(.*)$")
    elseif value == "--backend" then
      i = i + 1
      parsed.backend = deps.assert_backend(argv[i])
    elseif value and value:match("^%-%-backend=") then
      parsed.backend = deps.assert_backend(value:match("^%-%-backend=(.*)$"))
    elseif value and value:match("^%-Dbackend=") then
      parsed.backend = deps.assert_backend(value:match("^%-Dbackend=(.*)$"))
    elseif value == "--unix-socket-path" then
      i = i + 1
      parsed.unix_socket.path = argv[i]
    elseif value and value:match("^%-%-unix%-socket%-path=") then
      parsed.unix_socket.path = value:match("^%-%-unix%-socket%-path=(.*)$")
    elseif value == "--unix-socket-mode" then
      i = i + 1
      parsed.unix_socket.mode = argv[i]
    elseif value and value:match("^%-%-unix%-socket%-mode=") then
      parsed.unix_socket.mode = value:match("^%-%-unix%-socket%-mode=(.*)$")
    elseif value == "--unix-socket-unlink-stale" then
      parsed.unix_socket.unlink_stale = true
    elseif value == "--no-unix-socket-unlink-stale" then
      parsed.unix_socket.unlink_stale = false
    else
      parsed.extras[#parsed.extras + 1] = deps.shell_quote(value)
    end
    i = i + 1
  end
  parsed.backend = deps.assert_backend(parsed.backend)
  return parsed
end

local function unix_socket_build_flags(config, shell_quote)
  local flags = {}
  if config and config.path then flags[#flags + 1] = "-Dunix-socket-path=" .. shell_quote(config.path) end
  if config and config.mode then flags[#flags + 1] = "-Dunix-socket-mode=" .. shell_quote(config.mode) end
  if config and config.unlink_stale ~= nil then flags[#flags + 1] = "-Dunix-socket-unlink-stale=" .. tostring(config.unlink_stale) end
  return table.concat(flags, " ")
end

function build.run(argv, deps)
  deps = deps or {}
  local root = deps.current_dir()
  local parsed = parse_build_args(argv, deps, 2, "hybrid", root)
  local shell_quote = deps.shell_quote
  local graph_command = table.concat({ shell_quote(deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"), shell_quote(deps.package_cli_file()), "graph", shell_quote(root .. "/src/main.lua"), shell_quote(root .. "/.meteorite/graph/current"), shell_quote(parsed.mode), shell_quote(parsed.backend) }, " ")
  if not deps.run_command(graph_command) then os.exit(1) end
  local command_line = table.concat({
    "zig build --build-file", shell_quote(deps.package_build_file()),
    "-Dmeteorite-cli=" .. shell_quote(deps.package_cli_file()),
    "-Dproject-root=" .. shell_quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current -Dmode=" .. shell_quote(parsed.mode) .. " -Dbackend=" .. shell_quote(parsed.backend),
    unix_socket_build_flags(parsed.unix_socket, shell_quote),
    table.concat(parsed.extras, " "),
    "install-server --", shell_quote(root .. "/dist/server"),
  }, " ")
  if not deps.run_command(command_line) then os.exit(1) end
end

return build
