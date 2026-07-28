local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = source:match("^(.*)/src/ballad_plugin/meteorite/ballad%.lua$")
if root then
  local previous_path = package.path
  package.path = table.concat({
    root .. "/src/?.lua",
    root .. "/src/?/init.lua",
    previous_path,
  }, ";")
  local chunk = assert(loadfile(root .. "/src/ballad/init.lua"))
  local ok, plugin = pcall(chunk)
  package.path = previous_path
  if not ok then error(plugin) end
  return plugin
end

local met_dir = source:match("^(.*)/ballad%.lua$")
if met_dir then
  local previous_path = package.path
  package.path = table.concat({
    met_dir .. "/?.lua",
    met_dir .. "/?/init.lua",
    previous_path,
  }, ";")
  local plugin = require("ballad.init")
  package.path = previous_path
  return plugin
end

return require("ballad.init")
