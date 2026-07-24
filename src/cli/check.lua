--- Validate a target without producing a deployable release.
local check = {}

function check.run(argv, deps)
  if argv[2] == "--help" or argv[2] == "-h" then deps.print_help("check"); return end
  local request = deps.build_request.parse({ table.unpack(argv, 2) })
  deps.build_request.require_behavior(request, "meteorite check")
  local root = deps.current_dir()
  local quote = deps.shell_quote
  local lua = deps.read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"
  local command = table.concat({
    quote(lua), quote(deps.package_cli_file()), "graph", quote(root .. "/src/main.lua"),
    quote(root .. "/.meteorite/check/report"), quote(request.mode), quote(request.backend),
  }, " ")
  if not deps.run_command(command) then os.exit(1) end
  print("Meteorite check passed: " .. request.mode .. " via " .. request.backend)
end

return check
