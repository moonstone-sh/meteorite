local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/meteorite/"
local package_root = script_dir:gsub("meteorite[/\\]$", "")
package.path = "src/?.lua;src/?/init.lua;" .. package_root .. "?.lua;" .. package_root .. "?/init.lua;" .. package.path

local command = arg[1] or "graph"
if command ~= "graph" and command ~= "invoke" then error("unknown meteorite command: " .. tostring(command)) end
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
  local emitter = require("meteorite.emitter")
  local output = arg[3] or ".meteorite/graph/current"
  local mode = arg[4] or "release-static"
  local result = emitter.emit(app, { output = output, mode = mode })
  print("Meteorite graph")
  print("  graph: " .. result.graph_hash)
  print("  mode: " .. mode)
  print("  backend: std.http")
  print("  routes: " .. tostring(#result.graph.routes))
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
  local hybrid = require("meteorite.hybrid")
  local method = arg[3] or "GET"
  local path = arg[4] or "/"
  local body = arg[5] or ""
  local response = hybrid.invoke(app, { method = method, path = path, body = body }, { mode = "dev" })
  io.write(tostring(response.status), "\t", response.content_type or "", "\t", response.body or "", "\n")
end
