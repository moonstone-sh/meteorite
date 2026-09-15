local input = arg[1] or "src/main.lua"
local output = arg[2] or ".meteorite/graph/current"
local mode = arg[3] or "hybrid_dev"
local backend = arg[4] or "std_http"
local build_args = arg[5] or ("-Dmode=" .. mode .. " -Dbackend=" .. backend .. " -Dhybrid-profile=optimized -Drouter-dispatch=param_matchers")
local server = arg[6] or "dist/server"
local state_dir = ".meteorite/dev"
local pid_file = state_dir .. "/server.pid"
local log_file = state_dir .. "/server.log"
local session_id = os.getenv("CLINGY_SUPERVISOR_PID")
local explicit_dev_port = os.getenv("METEORITE_DEV_PORT")
local meteorite_cli = os.getenv("METEORITE_CLI") or "src/cli/main.lua"
local build_command_override = os.getenv("METEORITE_BUILD_COMMAND")
local once = os.getenv("METEORITE_DEV_ONCE") == "1"
local prebuilt = os.getenv("METEORITE_DEV_PREBUILT") == "1"
local dev_watch = require("core.dev_watch")

local function path_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local lua_bin = os.getenv("METEORITE_LUA") or (path_exists(".moonstone/env/bin/lua") and ".moonstone/env/bin/lua" or "lua")

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local running = true
local is_shutting_down = false
local stop_server

-- Reaction handler for subprocess signal interruptions (e.g. from os.execute).
-- Note: This is NOT a C/OS native signal handler; the shell supervisor owns OS signals.
local function handle_execute_signal()
  if is_shutting_down then return end
  is_shutting_down = true
  running = false
  io.stderr:write("\nMeteorite dev: stopping dev server...\n")
  io.stderr:flush()
  if stop_server then stop_server() end
  io.stderr:write("Meteorite dev: stopped.\n")
  io.stderr:flush()
  os.exit(0)
end

local function is_signal(ok, exit_type, code)
  if exit_type == "signal" then return true end
  if type(ok) == "number" and (ok == 2 or ok == 130 or ok == 15 or ok == 143) then return true end
  if type(code) == "number" and (code == 2 or code == 130 or code == 15 or code == 143) then return true end
  return false
end

local function run(command)
  io.stderr:write("$ " .. command .. "\n")
  io.stderr:flush()
  local ok, exit_type, code = os.execute(command)
  if is_signal(ok, exit_type, code) then
    handle_execute_signal()
  end
  return ok == true or ok == 0 or code == 0
end

local function quiet_run(command)
  local ok, exit_type, code = os.execute(command)
  if is_signal(ok, exit_type, code) then
    handle_execute_signal()
  end
  return ok == true or ok == 0 or code == 0
end

local function capture(command)
  local pipe = io.popen(command, "r")
  if not pipe then return "" end
  local data = pipe:read("*a") or ""
  pipe:close()
  return data
end

local function mkdir_p(path)
  os.execute("mkdir -p " .. shell_quote(path))
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function write_file(path, content)
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
end

-- Structured dev events. Purely additive: every plain-text status line below is
-- unchanged. Each one additionally appends an equivalent JSON line to the very
-- file the Zig server appends its "source":"server" request lines to (see
-- zig/server/dev_events.zig and cli/dev_command.lua's events_log_path), so an
-- external consumer gets one interleaved, tailable stream. Encoding reuses
-- utils.json the way cli/hybrid.lua does, defensively: a dev loop must never
-- fail because an observability side-channel could not load.
local events_file = state_dir .. "/events.log"
local json_encode = (function()
  local ok, json = pcall(require, "utils.json")
  if ok and json and json.encode then return json.encode end
  return nil
end)()

local function emit_event(kind, fields)
  if not json_encode then return end
  local event = { v = 1, ts = os.time() * 1000, source = "supervisor", kind = kind }
  for key, value in pairs(fields or {}) do event[key] = value end
  local ok, encoded = pcall(json_encode, event)
  if not ok then return end
  local file = io.open(events_file, "a")
  if not file then return end
  file:write(encoded, "\n")
  file:close()
end

-- Route count for the startup event, read from the same generated graph the
-- server itself was compiled from rather than re-deriving it.
local function graph_route_count()
  local data = read_file(output .. "/routes.zon")
  if not data then return 0 end
  local count = 0
  for _ in data:gmatch("%.raw_path%s*=") do count = count + 1 end
  return count
end

-- The project's real listen port is whatever the generated graph says: the Zig
-- server binds listen.zon (see src/codegen/emitter.lua and zig/main.zig), which
-- carries app.options.port. Resolving it here keeps the dev banner, the guard's
-- port-collision check and the Lua reload endpoint all pointing at the port the
-- server actually listens on, instead of a literal 8080 that may belong to an
-- entirely unrelated project.
local function graph_listen_port()
  local data = read_file(output .. "/listen.zon")
  return data and data:match("%.port%s*=%s*(%d+)") or nil
end

-- METEORITE_DEV_PORT stays an explicit override; the 8080 literal is only a
-- last resort for the window before the first graph() run produces listen.zon.
local function resolve_dev_port()
  return explicit_dev_port or graph_listen_port() or "8080"
end

local function pid_running(pid)
  return pid ~= nil and quiet_run("kill -0 " .. tostring(pid) .. " >/dev/null 2>&1")
end

local function current_server_pid()
  local record = read_file(pid_file) or ""
  local pid, owner = record:match("^(%d+)\n(%d+)\n$")
  if owner == session_id then return pid end
  return nil
end

local function server_running()
  return pid_running(current_server_pid())
end

-- Server PID this supervisor believes it currently owns, used only to tell a
-- crash (emit server_exit) apart from a stop we performed ourselves (silent).
local supervised_pid = nil

stop_server = function()
  supervised_pid = nil
  -- Only this active Clingy session may stop its recorded server. Stale PID
  -- files and listeners belonging to another project confer no ownership.
  local pid = current_server_pid()
  if pid and pid_running(pid) then
    os.execute("kill -TERM " .. pid .. " >/dev/null 2>&1")
    for _ = 1, 20 do
      if not pid_running(pid) then break end
      os.execute("sleep 0.1")
    end
  end
  if pid and pid_running(pid) then
    os.execute("kill -9 " .. tostring(pid) .. " >/dev/null 2>&1 || true")
  end
  os.remove(pid_file)
end

local function start_server()
  stop_server()
  local command = "(trap - INT TERM HUP; exec " .. shell_quote(server) .. ") >" .. shell_quote(log_file) .. " 2>&1 & echo $!"
  local pid = capture(command):match("%d+")
  if pid then write_file(pid_file, pid .. "\n" .. session_id .. "\n") end
  local is_up = false
  -- Readiness at the supervisor's own polling resolution (100ms steps).
  local ready_ms = 0
  for _ = 1, 5 do
    os.execute("sleep 0.1")
    ready_ms = ready_ms + 100
    if pid_running(pid) then
      is_up = true
      break
    end
  end
  if not is_up then
    emit_event("build_error", { stage = "server_start", detail = "server failed to stay running; see " .. log_file })
    error("Meteorite dev server failed to stay running; see " .. log_file)
  else
    io.stderr:write("Meteorite dev server: http://127.0.0.1:" .. resolve_dev_port() .. " pid=" .. tostring(pid or "?") .. " log=" .. log_file .. "\n")
    supervised_pid = pid
    emit_event("startup", {
      routes = graph_route_count(),
      mode = mode,
      backend = backend,
      ready_ms = ready_ms,
    })
  end
end

local function watch_paths()
  local policy = dev_watch.decode(read_file(output .. "/dev-watch.paths"))
  local graph = { input, "zig", "build.zig", "moonstone.toml" }
  for _, path in ipairs(policy.graph) do graph[#graph + 1] = path end
  return graph, policy.runtime
end

local function source_fingerprint(paths)
  if #paths == 0 then return "" end
  local quoted = {}
  for _, path in ipairs(paths) do quoted[#quoted + 1] = shell_quote(path) end
  local command = table.concat({
    "find " .. table.concat(quoted, " ") .. " -type f 2>/dev/null",
    "| sort",
    "| while IFS= read -r f; do stat -f '%m %z %N' \"$f\" 2>/dev/null || stat -c '%Y %s %n' \"$f\" 2>/dev/null; done"
  }, " ")
  return capture(command)
end

local function parse_partition_changes()
  local text = read_file(output .. "/partition-changes.json") or "[]"
  local changes = {}
  local current = {}
  for line in text:gmatch("[^\n]+") do
    local status = line:match('"status"%s*:%s*"([^"]+)"')
    if status then current = { status = status } end
    local kind = line:match('"kind"%s*:%s*"([^"]+)"')
    if kind then current.kind = kind end
    local id = line:match('"id"%s*:%s*"([^"]+)"')
    if id then
      current.id = id
      changes[#changes + 1] = current
      current = {}
    end
  end
  return changes
end

local function summarize_changes(changes)
  if #changes == 0 then return "none" end
  local counts = {}
  for _, change in ipairs(changes) do counts[change.kind] = (counts[change.kind] or 0) + 1 end
  local keys = {}
  for kind, _ in pairs(counts) do keys[#keys + 1] = kind end
  table.sort(keys)
  local parts = {}
  for _, kind in ipairs(keys) do parts[#parts + 1] = kind .. "=" .. tostring(counts[kind]) end
  return table.concat(parts, ", ")
end

local function classify_changes(changes, force_build)
  if force_build then return "rebuild", "zig/build input changed" end
  if #changes == 0 then return "none", "no graph partition changes" end
  local counts = {}
  for _, change in ipairs(changes) do counts[change.kind] = (counts[change.kind] or 0) + 1 end
  local function has(kind) return counts[kind] ~= nil end
  local function only(allowed)
    for kind, _ in pairs(counts) do
      if not allowed[kind] then return false end
    end
    return true
  end
  if only({ lua_chunk = true, lua_chunks = true }) then return "reload", "Lua-only handler chunks changed" end
  if has("route_graph") or has("route") or has("patterns") or has("pattern") or has("plugins") or has("plugin") or has("capabilities") or has("runtime") then
    return "rebuild", "graph-shape partitions changed"
  end
  if has("static_asset") and only({ static_asset = true, handlers = true, handler = true }) then
    return "rebuild", "static asset partitions changed"
  end
  for _, change in ipairs(changes) do
    if change.kind == "handler" or change.kind == "handlers" then
      return "rebuild", "Zig/file handler partitions changed"
    end
  end
  return "rebuild", "graph-affecting partitions changed"
end

local function reload_lua()
  return run("curl -fsS -X POST http://127.0.0.1:" .. resolve_dev_port() .. "/__meteorite/reload-lua >/dev/null")
end

local function graph()
  local graph_command = table.concat({ shell_quote(lua_bin), shell_quote(meteorite_cli), "graph", shell_quote(input), shell_quote(output), shell_quote(mode), shell_quote(backend) }, " ")
  return run(graph_command)
end

local function build()
  local build_command = build_command_override or ("zig build install-server " .. build_args .. " -- " .. shell_quote(server))
  return run(build_command)
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function changed_zig_or_build(previous, current)
  if not previous then return true end
  local function filter(text)
    local out = {}
    for line in tostring(text):gmatch("[^\n]+") do
      if line:match(" zig/") or line:match(" build%.zig$") or line:match(" moonstone%.toml$") then out[#out + 1] = line end
    end
    return table.concat(out, "\n")
  end
  return filter(previous) ~= filter(current)
end

if input == "--classify-partitions" then
  output = arg[2] or output
  local force_build = arg[3] == "true" or arg[3] == "1" or arg[3] == "force"
  local changes = parse_partition_changes()
  local action, reason = classify_changes(changes, force_build)
  io.write(action, "\t", reason, "\n")
  return
end

assert(os.getenv("CLINGY_SUPERVISED") == "1" and session_id,
  "dev.lua requires a Clingy-owned session; use meteorite dev or scripts/watch.sh")

mkdir_p(state_dir)

if prebuilt then
  io.stderr:write("Meteorite dev: supervising a Ballad-materialized server\n")
elseif once then
  io.stderr:write("Meteorite dev: running one graph-aware refresh cycle\n")
else
  io.stderr:write("Meteorite dev: watching app graph and runtime inputs\n")
end
io.stderr:write("Meteorite dev: mode=" .. mode .. " build_args=" .. build_args .. "\n")
io.stderr:write("Press Ctrl-C or Ctrl-D to stop.\n")

if prebuilt then
  stop_server()
  start_server()
  if once then return end
end

local last_graph, last_runtime = nil, nil
while running do
  local graph_paths, runtime_paths = watch_paths()
  local current_graph = source_fingerprint(graph_paths)
  local current_runtime = source_fingerprint(runtime_paths)
  if current_graph ~= last_graph then
    local force_build = changed_zig_or_build(last_graph, current_graph) or not file_exists(server)
    io.stderr:write("\nMeteorite dev: change detected; regenerating graph...\n")
    if graph() then
      local changes = parse_partition_changes()
      io.stderr:write("Meteorite dev: partitions " .. summarize_changes(changes) .. "\n")
      local action, reason = classify_changes(changes, force_build)
      io.stderr:write("Meteorite dev: action=" .. action .. " reason=" .. reason .. "\n")
      emit_event("rebuild", { reason = reason, action = action, partitions = summarize_changes(changes) })
      if action == "none" then
        if not server_running() then start_server() end
      elseif action == "reload" then
        local reloaded = reload_lua()
        emit_event("reload", { ok = reloaded })
        if reloaded then
          io.stderr:write("Meteorite dev: Lua handlers reloaded in-process.\n")
        else
          io.stderr:write("Meteorite dev: Lua reload failed; restarting server.\n")
          start_server()
        end
      elseif build() then
        start_server()
      else
        io.stderr:write("Meteorite dev: build failed; keeping previous server state.\n")
        emit_event("build_error", { stage = "build", detail = "build failed; keeping previous server state" })
      end
    else
      io.stderr:write("Meteorite dev: graph failed; keeping previous server state.\n")
      emit_event("build_error", { stage = "graph", detail = "graph failed; keeping previous server state" })
    end
    graph_paths, runtime_paths = watch_paths()
    last_graph = source_fingerprint(graph_paths)
    last_runtime = source_fingerprint(runtime_paths)
  elseif current_runtime ~= last_runtime then
    io.stderr:write("\nMeteorite dev: runtime input changed; restarting server without graph regeneration.\n")
    start_server()
    last_runtime = current_runtime
  end
  -- A server we started that is gone without us stopping it is a crash: report
  -- it so a consumer can show a definite down-state instead of a stuck spinner.
  if supervised_pid and not pid_running(supervised_pid) then
    emit_event("server_exit", { pid = tonumber(supervised_pid), reason = "unexpected_exit" })
    supervised_pid = nil
  end
  if once then break end
  local ok, exit_type, code = os.execute("sleep 1")
  if is_signal(ok, exit_type, code) then
    handle_execute_signal()
  end
end

if not once then handle_execute_signal() end
