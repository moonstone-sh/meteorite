local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = source:match("^(.*)/src/ballad_plugin/meteorite/ballad%.lua$")
if not root then error("cannot locate Meteorite Ballad plugin source") end

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
