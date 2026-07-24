local doctor = {}

function doctor.run(deps)
  local read_file = assert(deps.read_file, "read_file required")
  local run_command = assert(deps.run_command, "run_command required")
  local shell_quote = assert(deps.shell_quote, "shell_quote required")
  local path_join = assert(deps.path_join, "path_join required")
  local current_dir = assert(deps.current_dir, "current_dir required")
  local package_cli_file = assert(deps.package_cli_file, "package_cli_file required")
  local capture_command = assert(deps.capture_command, "capture_command required")
  local candidate_file = assert(deps.candidate_file, "candidate_file required")
  local roots = deps.roots or {}
  local module_root = roots.module_root or "src/"
  local install_root = roots.install_root or ""
  local share_root = roots.share_root

  local checks = {}
  local failed = false
  local function add(status, label, detail)
    checks[#checks + 1] = { status = status, label = label, detail = detail }
    if status == "fail" then failed = true end
  end
  local function exists(path)
    return read_file(path) ~= nil or run_command("test -e " .. shell_quote(path) .. " >/dev/null 2>&1")
  end
  local function dir_exists(path)
    return run_command("test -d " .. shell_quote(path) .. " >/dev/null 2>&1")
  end
  local function graph_file(name)
    return read_file(path_join(".meteorite/graph/current", name)) ~= nil
  end
  local function load_app_for_doctor()
    local input = "src/main.lua"
    if not read_file(input) then return nil, "src/main.lua missing" end
    local input_dir = input:match("^(.*[/\\])") or ""
    if input_dir ~= "" then package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path end
    local chunk, err = loadfile(input)
    if not chunk then return nil, err end
    local ok, app_or_err = pcall(chunk)
    if not ok then return nil, app_or_err end
    local app = app_or_err
    if type(app) ~= "table" or not app.__meteorite_app then return nil, "src/main.lua must return a Meteorite app" end
    return app, nil
  end
  local function lua_runtime_nodes(graph)
    local count = 0
    for _, route in ipairs((graph and graph.routes) or {}) do
      if route.runtime and route.runtime.requires_lua then count = count + 1 end
    end
    return count
  end

  local has_manifest = read_file("moonstone.toml") ~= nil
  local has_app = read_file("src/main.lua") ~= nil
  local has_moon_env = dir_exists(".moonstone/env")
  local has_moon_lua = read_file(".moonstone/env/bin/lua") ~= nil
  add(has_manifest and "ok" or "fail", "moonstone.toml", has_manifest and "found" or "run from a Moonstone project root")
  add(has_app and "ok" or "fail", "src/main.lua", has_app and "found" or "Meteorite apps default to src/main.lua")
  add(has_moon_env and "ok" or "warn", "Moonstone env", has_moon_env and ".moonstone/env" or "run moon sync")
  add(has_moon_lua and "ok" or "warn", "Lua runtime", has_moon_lua and ".moonstone/env/bin/lua" or "run moon sync")
  local cli_ok, cli_path = pcall(package_cli_file)
  add(cli_ok and read_file(cli_path) and "ok" or "fail", "Meteorite CLI", cli_ok and cli_path or tostring(cli_path))
  local zig_ok = run_command("command -v zig >/dev/null 2>&1")
  local zig_version = zig_ok and (capture_command("zig version 2>/dev/null"):gsub("%s+$", "")) or nil
  add(zig_ok and "ok" or "fail", "Zig", zig_ok and zig_version or "zig not found on PATH")
  local ballad_plugin_path = candidate_file({
    "src/meteorite/ballad.lua",
    module_root .. "meteorite/ballad.lua",
    install_root .. "src/meteorite/ballad.lua",
    share_root and (share_root .. "/meteorite/ballad.lua") or nil,
  })
  add(ballad_plugin_path and "ok" or "fail", "Ballad plugin", ballad_plugin_path or "meteorite.ballad source not found")
  local ballad_core_path = candidate_file({
    ".moonstone/env/share/lua/5.4/ballad/graph.lua",
    ".moonstone/env/share/lua/5.1/ballad/graph.lua",
    "../ballad/src/ballad/graph.lua",
  })
  add(ballad_core_path and "ok" or "warn", "Ballad core", ballad_core_path or "Ballad runtime not on local Lua path; release partiture may need moon sync")
  local graph_ready = graph_file("graph.zig") and graph_file("routes.zon") and graph_file("build-report.txt")
  add(graph_ready and "ok" or "warn", "generated graph", graph_ready and ".meteorite/graph/current" or "run meteorite graph or meteorite dev")
  add(read_file(".meteorite/aids/lua/meteorite.lua") and "ok" or "warn", "LuaLS aids", read_file(".meteorite/aids/lua/meteorite.lua") and ".meteorite/aids/lua" or "generated on graph build")
  local app, app_err = load_app_for_doctor()
  if app then
    local ok, graph_or_err = pcall(function() return app:normalize({ mode = "dev" }) end)
    if ok then
      local retained_lua = lua_runtime_nodes(graph_or_err)
      add(retained_lua == 0 and "ok" or "warn", "static release readiness", retained_lua == 0 and "no retained Lua runtime nodes" or (tostring(retained_lua) .. " retained Lua route(s); use hybrid mode or Zig handlers"))
      add(has_moon_lua and "ok" or "warn", "hybrid release readiness", has_moon_lua and "Lua runtime available for hybrid packaging" or "run moon sync before hybrid release")
    else
      add("warn", "release readiness", tostring(graph_or_err))
    end
  else
    add("warn", "release readiness", tostring(app_err))
  end
  add(exists("partiture.lua") and "ok" or "warn", "release partiture", exists("partiture.lua") and "partiture.lua" or "add partiture.lua for Ballad release exports")
  add("ok", "build behavior", "provided explicitly by Moonstone scripts or command arguments")
  local port = os.getenv("METEORITE_DEV_PORT") or "8080"
  local listener = capture_command("lsof -tiTCP:" .. port .. " -sTCP:LISTEN 2>/dev/null | head -n 1")
  add(listener ~= "" and "warn" or "ok", "dev port " .. port, listener ~= "" and ("listener pid " .. listener:gsub("%s+$", "")) or "free")

  print("Meteorite doctor")
  for _, check in ipairs(checks) do
    local mark = check.status == "ok" and "ok" or (check.status == "warn" and "warn" or "fail")
    print("  " .. mark .. "  " .. check.label .. " — " .. tostring(check.detail))
  end
  if failed then os.exit(1) end
end

return doctor
