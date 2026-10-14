-- meteorite.compat for PUC Lua 5.1. See compat.lua (the fallback) for the
-- contract; tests/compat.lua keeps the variants in step.

local compat = {}

compat.flavor_file = "lua51"
compat.lua_version = "5.1"
compat.is_luajit = false
compat.unpack = unpack

function compat.pack(...)
  return { n = select("#", ...), ... }
end

-- PUC 5.1's `load` only takes reader functions and has no mode or env.
function compat.load(chunk, chunkname, _, env)
  local fn, err
  if type(chunk) == "string" then
    fn, err = loadstring(chunk, chunkname)
  else
    fn, err = load(chunk, chunkname)
  end
  if fn and env ~= nil then setfenv(fn, env) end
  return fn, err
end

return compat
