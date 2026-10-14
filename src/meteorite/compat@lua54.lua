-- meteorite.compat for PUC Lua 5.4. See compat.lua (the fallback) for the
-- contract; tests/compat.lua keeps the variants in step.

local compat = {}

compat.flavor_file = "lua54"
compat.lua_version = "5.4"
compat.is_luajit = false
compat.unpack = table.unpack
compat.pack = table.pack
compat.load = load

return compat
