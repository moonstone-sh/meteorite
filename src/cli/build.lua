--- Meteorite build command.
local build = {}

function build.run(argv, deps)
  deps = deps or {}
  if argv[2] == "--help" or argv[2] == "-h" then deps.print_help("build"); return end
  local root = deps.current_dir()
  local request = deps.build_request.parse({ table.unpack(argv, 2) })
  deps.build_request.require_behavior(request, "meteorite build")
  local quote = deps.shell_quote
  local lua = deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"
  local graph_command = table.concat({
    quote(lua), quote(deps.package_cli_file()), "graph", quote(root .. "/src/main.lua"),
    quote(root .. "/.meteorite/graph/current"), quote(request.mode), quote(request.backend),
  }, " ")
  if not deps.run_command(graph_command) then os.exit(1) end
  local command_line = table.concat({
    "zig build --build-file", quote(deps.package_build_file()),
    "-Dmeteorite-cli=" .. quote(deps.package_cli_file()),
    "-Dproject-root=" .. quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current",
    table.concat(deps.build_request.to_build_flags(request, quote), " "),
    "install-server --", quote(root .. "/dist/server"),
  }, " ")
  if not deps.run_command(command_line) then os.exit(1) end
end

return build
