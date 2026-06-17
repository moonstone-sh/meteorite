local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/meteorite/"
local package_root = script_dir:gsub("meteorite[/\\]$", "")
package.path = "src/?.lua;src/?/init.lua;" .. package_root .. "?.lua;" .. package_root .. "?/init.lua;" .. package.path

local emitter = require("meteorite.emitter")

local command = arg[1] or "graph"
if command ~= "graph" then error("unknown meteorite command: " .. tostring(command)) end
local input = arg[2] or "src/main.lua"
local output = arg[3] or ".meteorite/graph/current"
local mode = arg[4] or "release-static"
local chunk, err = loadfile(input)
if not chunk then error(err) end
local app = chunk()
if type(app) ~= "table" or not app.__meteorite_app then
  error(input .. " must return a Meteorite app")
end
local result = emitter.emit(app, { output = output, mode = mode })
print("Meteorite graph")
print("  graph: " .. result.graph_hash)
print("  mode: " .. mode)
print("  backend: std.http")
print("  routes: " .. tostring(#result.graph.routes))
