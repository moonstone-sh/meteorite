local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/cli/"
local module_root = script_dir:gsub("cli[/\\]$", "")
local install_root = module_root:gsub("src[/\\]$", "")
package.path = "src/?.lua;src/?/init.lua;" .. module_root .. "?.lua;" .. module_root .. "?/init.lua;" .. install_root .. "?.lua;" .. install_root .. "?/init.lua;" .. package.path

local function dirname(path)
  return tostring(path):match("^(.*)/[^/]+$") or "."
end

local function parent_dir(path)
  local value = tostring(path):gsub("/+$", "")
  return value:match("^(.*)/[^/]+$") or "."
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function path_join(a, b)
  if a == "." or a == "" then return b end
  return a .. "/" .. b
end

local function candidate_file(paths)
  for _, candidate in ipairs(paths) do
    if candidate and read_file(candidate) then return candidate end
  end
  return nil
end

local function find_moonstone_share_root(path)
  local marker = "/share/lua/"
  local start_at, end_at = tostring(path):find(marker, 1, true)
  if not start_at then return nil end
  local rest = path:sub(end_at + 1)
  local lua_ver = rest:match("^([^/]+)")
  if not lua_ver then return nil end
  return path:sub(1, start_at - 1) .. "/share/lua/" .. lua_ver
end

local share_root = find_moonstone_share_root(source)
local libexec_root = share_root and (parent_dir(parent_dir(parent_dir(share_root))) .. "/libexec/meteorite") or nil
local package_root = candidate_file({
  install_root .. "build.zig",
  install_root .. "../build.zig",
  share_root and (share_root .. "/build.zig") or nil,
  libexec_root and (libexec_root .. "/build.zig") or nil,
  libexec_root and (libexec_root .. "/files/build.zig") or nil,
})
package_root = package_root and dirname(package_root) or install_root

local command = arg[1] or "graph"
if command == "--" then
  table.remove(arg, 1)
  command = arg[1] or "graph"
end

local help_text = require("cli.help_text")

local function print_help(topic)
  topic = topic or "main"
  topic = ({ ["--help"] = "main", ["-h"] = "main", help = "main" })[topic] or topic
  local page = help_text[topic]
  if not page then
    io.stderr:write("unknown help topic: " .. tostring(topic) .. "\n\n")
    page = help_text.main
  end
  print(page)
end

if command == "help" or command == "--help" or command == "-h" then
  print_help(arg[2])
  return
end

local function write_file(path, content, force)
  local existing = read_file(path)
  if existing ~= nil and not force then return false end
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then os.execute("mkdir -p " .. string.format("%q", parent)) end
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
  return true
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function render_template(text, name, lua_ver)
  return (text:gsub("{{name}}", name):gsub("{{lua_ver}}", lua_ver))
end

local function project_name_from_path(path)
  path = tostring(path or "."):gsub("/+$", "")
  local name = path:match("([^/]+)$") or "meteorite-app"
  if name == "." or name == "" then name = "meteorite-app" end
  return name:gsub("[^%w_.-]", "-")
end

local function template_root(name)
  name = name or "project"
  for _, candidate in ipairs({
    install_root .. "templates/" .. name,
    install_root .. "../templates/" .. name,
    module_root .. "../templates/" .. name,
  }) do
    if read_file(path_join(candidate, "src/main.lua")) then return candidate end
  end
  error("Meteorite template files not found near " .. tostring(install_root))
end

local function parse_init_args()
  local opts = { target = ".", name = nil, force = false, with_zig = false, no_sync = false, template = "project" }
  local i = 2
  while i <= #arg do
    local value = arg[i]
    if value == "--help" or value == "-h" then print_help("init"); os.exit(0)
    end
    if value == "--force" then opts.force = true
    elseif value == "--with-zig" then opts.with_zig = true
    elseif value == "--minimal" then opts.with_zig = false
    elseif value == "--crud" then error("`meteorite init --crud` was removed; see EXAMPLES.md for the CRUD example")
    elseif value == "--static" then opts.template = "static"
    elseif value == "--hybrid" then opts.template = "hybrid"
    elseif value == "--no-sync" then opts.no_sync = true
    elseif value == "--template" then
      i = i + 1
      opts.template = arg[i]
    elseif value and value:match("^%-%-template=") then opts.template = value:match("^%-%-template=(.*)$")
    elseif value == "--name" then
      i = i + 1
      opts.name = arg[i]
    elseif value and value:match("^%-%-name=") then opts.name = value:match("^%-%-name=(.*)$")
    elseif value and value:sub(1, 1) == "-" then error("unknown meteorite init flag: " .. tostring(value))
    else opts.target = value end
    i = i + 1
  end
  return opts
end

local cli_templates = require("cli.templates")

local function moonstone_manifest(name)
  local build_mode = _G.METEORITE_INIT_BUILD_MODE or "hybrid"
  local dev_script = build_mode == "release-static" and "meteorite build --mode release-static && ./dist/server" or "meteorite dev"
  return cli_templates.moonstone_manifest(name, build_mode, dev_script)
end

local function release_partiture(name)
  local build_mode = _G.METEORITE_INIT_BUILD_MODE or "hybrid"
  local release_mode = build_mode == "release-static" and "static" or "hybrid"
  return cli_templates.release_partiture(release_mode)
end

local function ensure_tool_dependencies(path)
  local content = read_file(path)
  if not content then return false end
  local deps = {}
  if not content:find('"moonstone/meteorite"', 1, true) then deps[#deps + 1] = '"moonstone/meteorite" = "^0.1.0"' end
  if not content:find('"moonstone/ballad"', 1, true) then deps[#deps + 1] = '"moonstone/ballad" = "^0.2.0"' end
  if #deps == 0 then return false end
  local block = table.concat(deps, "\n") .. "\n"
  local updated, count = content:gsub("(\n%[dependencies%.tool%]\n)", "%1" .. block, 1)
  if count == 0 then updated = content:gsub("%s*$", "\n\n[dependencies.tool]\n" .. block) end
  return write_file(path, updated, true)
end

local function init_project()
  local opts = parse_init_args()
  local target = opts.target or "."
  local name = opts.name or project_name_from_path(target)
  local lua_ver = "5.4"
  local template_name = ({ minimal = "project" })[opts.template] or opts.template or "project"
  if template_name ~= "project" and template_name ~= "static" and template_name ~= "hybrid" then
    error("unknown Meteorite template `" .. tostring(opts.template) .. "`; expected minimal, static, or hybrid")
  end
  _G.METEORITE_INIT_BUILD_MODE = template_name == "static" and "release-static" or "hybrid"
  local root = template_root(template_name)
  local files = {}
  local pipe = io.popen("cd " .. shell_quote(root) .. " && find . -type f | sort", "r")
  if pipe then
    for line in pipe:lines() do files[#files + 1] = line:gsub("^%./", "") end
    pipe:close()
  end
  if opts.with_zig then
    files[#files + 1] = "zig/handlers.zig"
    files[#files + 1] = "zig/validators.zig"
  end
  os.execute("mkdir -p " .. string.format("%q", target))
  for _, rel in ipairs(files) do
    local source_path = path_join(root, rel)
    local content = read_file(source_path)
    if not content then error("missing Meteorite template file: " .. source_path) end
    write_file(path_join(target, rel), render_template(content, name, lua_ver), opts.force)
  end
  local manifest_path = path_join(target, "moonstone.toml")
  if not read_file(manifest_path) then
    write_file(manifest_path, moonstone_manifest(name), opts.force)
  else
    ensure_tool_dependencies(manifest_path)
  end
  local partiture_path = path_join(target, "partiture.lua")
  if not read_file(partiture_path) then
    write_file(partiture_path, release_partiture(name), opts.force)
  end
  if not opts.no_sync then os.execute("cd " .. shell_quote(target) .. " && moon sync") end
  print("Meteorite project initialized: " .. target .. " (template: " .. template_name .. ")" .. (opts.with_zig and " (with Zig scaffolding)" or ""))
end

local function package_build_file()
  local found = candidate_file({
    package_root .. "/build.zig",
    install_root .. "build.zig",
    install_root .. "../build.zig",
    share_root and (share_root .. "/build.zig") or nil,
    libexec_root and (libexec_root .. "/build.zig") or nil,
    libexec_root and (libexec_root .. "/files/build.zig") or nil,
  })
  if found then return found end
  error("Meteorite build.zig not found near " .. tostring(install_root))
end

local function package_cli_file()
  local found = candidate_file({
    module_root .. "cli/main.lua",
    install_root .. "src/cli/main.lua",
    install_root .. "cli/main.lua",
    share_root and (share_root .. "/meteorite/cli/main.lua") or nil,
    libexec_root and (libexec_root .. "/src/cli/main.lua") or nil,
    libexec_root and (libexec_root .. "/files/meteorite/cli/main.lua") or nil,
  })
  if found then return found end
  error("Meteorite CLI not found near " .. tostring(install_root))
end

local function package_dev_file()
  local found = candidate_file({
    module_root .. "cli/dev.lua",
    install_root .. "src/cli/dev.lua",
    install_root .. "cli/dev.lua",
    share_root and (share_root .. "/meteorite/cli/dev.lua") or nil,
    libexec_root and (libexec_root .. "/src/cli/dev.lua") or nil,
    libexec_root and (libexec_root .. "/files/meteorite/cli/dev.lua") or nil,
  })
  if found then return found end
  error("Meteorite dev CLI not found near " .. tostring(install_root))
end

local function package_guard_file()
  local found = candidate_file({
    package_root .. "/scripts/guard.sh",
    install_root .. "scripts/guard.sh",
    install_root .. "../scripts/guard.sh",
    libexec_root and (libexec_root .. "/scripts/guard.sh") or nil,
    libexec_root and (libexec_root .. "/files/scripts/guard.sh") or nil,
  })
  if found then return found end
  return "scripts/guard.sh"
end

local function run_command(command)
  local ok, _, code = os.execute(command)
  return ok == true or ok == 0 or code == 0
end

local function capture_command(command)
  local pipe = io.popen(command, "r")
  if not pipe then return "" end
  local data = pipe:read("*a") or ""
  pipe:close()
  return data
end

local function current_dir()
  local pipe = io.popen("pwd", "r")
  if not pipe then return "." end
  local value = (pipe:read("*l") or "."):gsub("/+$", "")
  pipe:close()
  return value ~= "" and value or "."
end

local function forward_args(start_at)
  local out = {}
  for i = start_at, #arg do out[#out + 1] = shell_quote(arg[i]) end
  return table.concat(out, " ")
end

local function parse_mode_args(start_at, default_mode)
  local mode = default_mode
  local extras = {}
  local i = start_at
  while i <= #arg do
    local value = arg[i]
    if value == "--help" or value == "-h" then print_help("build"); os.exit(0)
    elseif value == "--mode" then
      i = i + 1
      mode = arg[i] or mode
    elseif value and value:match("^%-%-mode=") then
      mode = value:match("^%-%-mode=(.*)$")
    else
      extras[#extras + 1] = shell_quote(value)
    end
    i = i + 1
  end
  return mode, table.concat(extras, " ")
end

local function build_project()
  local mode, extras = parse_mode_args(2, "hybrid")
  local root = current_dir()
  local graph_command = table.concat({ shell_quote(read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"), shell_quote(package_cli_file()), "graph", shell_quote(root .. "/src/main.lua"), shell_quote(root .. "/.meteorite/graph/current"), shell_quote(mode) }, " ")
  if not run_command(graph_command) then os.exit(1) end
  local command_line = table.concat({
    "zig build --build-file", shell_quote(package_build_file()),
    "-Dmeteorite-cli=" .. shell_quote(package_cli_file()),
    "-Dproject-root=" .. shell_quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current -Dmode=" .. shell_quote(mode) .. " -Dbackend=std_http",
    extras,
    "install-server --", shell_quote(root .. "/dist/server"),
  }, " ")
  if not run_command(command_line) then os.exit(1) end
end

local function dev_project()
  local cli = package_cli_file()
  local root = current_dir()
  local guard = package_guard_file()
  local build_command = table.concat({
    "zig build --build-file", shell_quote(package_build_file()),
    "-Dmeteorite-cli=" .. shell_quote(cli),
    "-Dproject-root=" .. shell_quote(root),
    "-Dgraph-input=src/main.lua -Dgraph-output=.meteorite/graph/current -Dmode=hybrid_dev -Dbackend=std_http -Dhybrid-profile=optimized -Drouter-dispatch=param_matchers",
    "install-server --", shell_quote(root .. "/dist/server"),
  }, " ")
  local lua = read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua"
  local dev = package_dev_file()
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
  if not run_command(command_line) then os.exit(1) end
end

local function doctor_project()
  local checks = {}
  local failed = false
  local function add(status, label, detail)
    checks[#checks + 1] = { status = status, label = label, detail = detail }
    if status == "fail" then failed = true end
  end

  add(read_file("moonstone.toml") and "ok" or "fail", "moonstone.toml", read_file("moonstone.toml") and "found" or "run from a Moonstone project root")
  add(read_file("src/main.lua") and "ok" or "fail", "src/main.lua", read_file("src/main.lua") and "found" or "Meteorite apps default to src/main.lua")
  add(read_file(".moonstone/env/bin/lua") and "ok" or "warn", "Moonstone Lua", read_file(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "run moon sync")
  local cli_ok, cli_path = pcall(package_cli_file)
  add(cli_ok and read_file(cli_path) and "ok" or "fail", "Meteorite CLI", cli_ok and cli_path or tostring(cli_path))
  local zig_ok = run_command("command -v zig >/dev/null 2>&1")
  add(zig_ok and "ok" or "fail", "Zig", zig_ok and (capture_command("zig version 2>/dev/null"):gsub("%s+$", "")) or "zig not found on PATH")
  add(read_file(".meteorite/graph/current/graph.zig") and "ok" or "warn", "graph", read_file(".meteorite/graph/current/graph.zig") and ".meteorite/graph/current" or "run meteorite graph or meteorite dev")
  add(read_file(".meteorite/aids/lua/meteorite.lua") and "ok" or "warn", "LuaLS aids", read_file(".meteorite/aids/lua/meteorite.lua") and ".meteorite/aids/lua" or "generated on graph build")
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

if (command == "graph" or command == "invoke" or command == "doctor" or command == "dev") and (arg[2] == "--help" or arg[2] == "-h") then
  print_help(command)
  return
end
if command == "init" then init_project(); return end
if command == "build" then build_project(); return end
if command == "dev" then dev_project(); return end
if command == "doctor" then doctor_project(); return end
if command == "routes" then
  -- meteorite routes --graph: inspect route declarations and pipelines
  local json = require("utils.json")
  local contract = require("core.contract")
  local show_graph = false
  local input = "src/main.lua"
  for i = 2, #arg do
    local a = arg[i]
    if a == "--graph" or a == "--json" then
      show_graph = true
    elseif a:sub(1, 1) ~= "-" and a ~= command then
      input = a
    end
  end
  _G.METEORITE_BUILD_MODE = "dev"
  local input_dir = input:match("^(.*[/\\])") or ""
  if input_dir ~= "" then
    package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path
  end
  local chunk, err = loadfile(input)
  if not chunk then error(err) end
  local app = chunk()
  if type(app) ~= "table" or not app.__meteorite_app then
    error(input .. " must return a Meteorite app")
  end
  local route_mod = require("core.route")
  local normalized = route_mod.normalize_app(app, { mode = "dev" })
  if show_graph then
    print(json.encode({
      routes = (function()
        local out = {}
        for _, r in ipairs(normalized.routes) do
          out[#out + 1] = {
            id = r.id,
            method = r.method,
            path = r.raw_path,
            handler_kind = r.handler.kind,
            source_form = r.source_form or "legacy",
            has_pipeline = r.pipeline ~= nil,
            pipeline = r.pipeline and (function()
              local stages = {}
              for _, st in ipairs(r.pipeline) do
                stages[#stages + 1] = {
                  id = st.id,
                  kind = st.kind,
                  strat = st.strat,
                  path = st.path,
                  symbol = st.symbol,
                  inline = st.strat == "inline_lua",
                  phase = st.phase,
                  owner = st.owner,
                  may_short_circuit = st.may_short_circuit,
                }
              end
              return stages
            end)() or nil,
          }
        end
        return out
      end)(),
    }))
  else
    -- Human-readable output
    for _, r in ipairs(normalized.routes) do
      local src = r.source_form or "legacy"
      io.write(string.format("  %-6s %-30s  handler=%-12s  source=%s\n",
        r.method, r.raw_path, r.handler.kind, src))
      if r.pipeline then
        for _, st in ipairs(r.pipeline) do
          local detail = st.strat
          if st.path then detail = detail .. " " .. st.path
          elseif st.symbol then detail = detail .. " " .. st.symbol
          elseif st.strat == "inline_lua" then detail = detail .. " <inline>"
          end
          io.write(string.format("    %-10s %-8s  %s\n", st.kind, st.strat, detail))
        end
      end
    end
  end
  return
end

if command ~= "graph" and command ~= "invoke" then
  error("unknown meteorite command: " .. tostring(command) .. "\n\nRun:\n  meteorite help")
end
local input = arg[2] or "src/main.lua"
local mode = arg[4] or "release-static"
_G.METEORITE_BUILD_MODE = mode
local input_dir = input:match("^(.*[/\\])") or ""
if input_dir ~= "" then
  package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path
end
local chunk, err = loadfile(input)
if not chunk then error(err) end
local app = chunk()
if type(app) ~= "table" or not app.__meteorite_app then
  error(input .. " must return a Meteorite app")
end


if command == "graph" then
  local emitter = require("codegen.emitter")
  local output = arg[3] or ".meteorite/graph/current"
  local mode = arg[4] or "release-static"
  local result = emitter.emit(app, { output = output, mode = mode })
  print("Meteorite graph")
  print("  graph: " .. result.graph_hash)
  print("  mode: " .. mode)
  print("  backend: fast_http")
  print("  routes: " .. tostring(#result.graph.routes))
  if result.partitions then
    print("  partitions:")
    print("    route graph: " .. result.partitions.route_graph_hash)
    print("    handlers: " .. result.partitions.handler_hash)
    print("    patterns: " .. result.partitions.pattern_hash)
    print("    lua chunks: " .. result.partitions.lua_chunk_hash)
    print("    capabilities: " .. result.partitions.capability_hash)
    print("    runtime: " .. result.partitions.runtime_hash)
  end
  if result.partition_changes then
    if #result.partition_changes == 0 then
      print("  changed partitions: none")
    else
      print("  changed partitions: " .. tostring(#result.partition_changes))
      local max_changes = 12
      for i, change in ipairs(result.partition_changes) do
        if i > max_changes then
          print("    ... " .. tostring(#result.partition_changes - max_changes) .. " more")
          break
        end
        print("    " .. change.status .. " " .. change.kind .. ":" .. change.id)
      end
    end
  end
  if result.graph.memory_report then
    local memory = result.graph.memory_report
    print("  memory profile: " .. tostring(memory.profile))
    print("  peak memory: " .. tostring(memory.estimated_peak_bytes) .. " bytes (" .. tostring(memory.peak_route) .. ")")
    print("  uri limit: " .. tostring(memory.max_uri_bytes) .. " bytes")
    print("  dfa tables: " .. tostring(memory.dfa_bytes) .. " bytes")
  end
  local capability_kinds = {}
  for kind, _ in pairs(result.graph.capabilities or {}) do capability_kinds[#capability_kinds + 1] = kind end
  table.sort(capability_kinds)
  if #capability_kinds > 0 then
    print("  capabilities: " .. table.concat(capability_kinds, ", "))
  end
else
  local hybrid = require("cli.hybrid")
  local method = arg[3] or "GET"
  local path = arg[4] or "/"
  local body = arg[5] or ""
  local response = hybrid.invoke(app, { method = method, path = path, body = body }, { mode = "dev" })
  io.write(tostring(response.status), "\t", response.content_type or "", "\t", response.body or "", "\n")
end
