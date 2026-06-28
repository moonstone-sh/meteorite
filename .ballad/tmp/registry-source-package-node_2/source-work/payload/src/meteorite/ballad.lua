local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local base = source:match("^(.*)/meteorite/ballad%.lua$") or "src"
local chunk, err = loadfile(base .. "/ballad/init.lua")
if not chunk then error(err) end
return chunk()
