-- meteorite.compat: the few places where Meteorite's own Lua differs across
-- the Luas it runs on (PUC Lua 5.1-5.5 and LuaJIT).
--
-- This untagged file is the fallback and works everywhere by detecting the
-- runtime. Moonstone flavor variants specialize it without the branching:
--   compat@lua54.lua   PUC Lua 5.4
--   compat@luajit.lua  LuaJIT (beats @lua51 on LuaJIT)
--   compat@lua51.lua   PUC Lua 5.1
-- `moon sync` (for an installed package) or the runtime searcher installed
-- by cli/main.lua picks one; otherwise this file is used. All four must
-- export the same fields with the same behavior: tests/compat.lua checks.

local compat = {}

compat.flavor_file = "fallback"

--- "5.1" ... "5.5" (LuaJIT reports "5.1"): the share/lua/<v> directory name.
compat.lua_version = tostring(_VERSION):match("%d+%.%d+") or "5.1"

compat.is_luajit = type(rawget(_G, "jit")) == "table"

compat.unpack = table.unpack or unpack

compat.pack = table.pack or function(...)
  return { n = select("#", ...), ... }
end

local native_load = load
local setfenv = rawget(_G, "setfenv")
local loadstring = rawget(_G, "loadstring")

-- Does `load` accept a string chunk? True on 5.2+ and LuaJIT, false on 5.1.
local load_takes_strings = pcall(native_load, "return true") and native_load("return true") ~= nil

--- Lua 5.2+ `load(chunk, chunkname, mode, env)` on every Lua. `chunk` is a
--- string or a reader function. `mode` is honored where the runtime can.
function compat.load(chunk, chunkname, mode, env)
  if not setfenv then return native_load(chunk, chunkname, mode, env) end
  local fn, err
  if type(chunk) == "string" then
    if load_takes_strings then
      fn, err = native_load(chunk, chunkname, mode)
    else
      fn, err = loadstring(chunk, chunkname)
    end
  else
    fn, err = native_load(chunk, chunkname)
  end
  if fn and env ~= nil then setfenv(fn, env) end
  return fn, err
end

return compat
