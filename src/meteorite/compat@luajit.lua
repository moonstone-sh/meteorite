-- meteorite.compat for LuaJIT. See compat.lua (the fallback) for the
-- contract; tests/compat.lua keeps the variants in step.

local compat = {}

compat.flavor_file = "luajit"
compat.lua_version = "5.1"
compat.is_luajit = true
compat.unpack = unpack

function compat.pack(...)
  return { n = select("#", ...), ... }
end

-- LuaJIT's `load` takes strings and modes but not an environment.
function compat.load(chunk, chunkname, mode, env)
  local fn, err = load(chunk, chunkname, mode)
  if fn and env ~= nil then setfenv(fn, env) end
  return fn, err
end

return compat
