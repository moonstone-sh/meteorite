package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local test = require("test")

local DIR = "src/meteorite/"
local VARIANTS = { "compat.lua", "compat@lua54.lua", "compat@luajit.lua", "compat@lua51.lua" }

local function running_tag()
  if type(rawget(_G, "jit")) == "table" then return "luajit" end
  return "lua" .. tostring(_VERSION):gsub("%D", "")
end

local function load_variant(name)
  local chunk, err = loadfile(DIR .. name)
  assert(chunk, err)
  return chunk()
end

test "every compat variant parses on this interpreter" (function()
  for _, name in ipairs(VARIANTS) do
    local chunk, err = loadfile(DIR .. name)
    test.assert_true(chunk ~= nil, name .. " parses: " .. tostring(err))
  end
end)

-- Variants for other Luas cannot run here (5.1's setfenv/loadstring do not
-- exist on 5.4 and vice versa), but they must declare the same fields.
test "every compat variant exports the fallback's fields" (function()
  local function exported(name)
    local source = assert(io.open(DIR .. name, "rb")):read("*a")
    local fields = {}
    for field in source:gmatch("\ncompat%.([%w_]+)%s*=") do fields[field] = true end
    for field in source:gmatch("\nfunction compat%.([%w_]+)%(") do fields[field] = true end
    return fields
  end
  local base = exported("compat.lua")
  for _, name in ipairs(VARIANTS) do
    local fields = exported(name)
    for field in pairs(base) do test.assert_true(fields[field], name .. " defines compat." .. field) end
    for field in pairs(fields) do test.assert_true(base[field], "compat.lua defines compat." .. field .. " (from " .. name .. ")") end
  end
end)

local function behaves_like_fallback(compat, label)
  local fallback = load_variant("compat.lua")
  test.assert_eq(compat.lua_version, fallback.lua_version, label .. " lua_version")
  test.assert_eq(compat.is_luajit, fallback.is_luajit, label .. " is_luajit")
  local a, b, c = compat.unpack({ 1, 2, 3 }, 2)
  test.assert_eq(a, 2, label .. " unpack from index")
  test.assert_eq(b, 3, label .. " unpack second")
  test.assert_eq(c, nil, label .. " unpack end")
  local packed = compat.pack(1, nil, 3)
  test.assert_eq(packed.n, 3, label .. " pack keeps nils in n")
  test.assert_eq(packed[3], 3, label .. " pack values")
  local fn = assert(compat.load("return x", "=compat-test", "t", { x = 42 }))
  test.assert_eq(fn(), 42, label .. " load with env")
  fn = assert(compat.load("return 7", "=compat-test"))
  test.assert_eq(fn(), 7, label .. " load string")
  local parts, i = { "return ", "9" }, 0
  fn = assert(compat.load(function() i = i + 1; return parts[i] end, "=compat-reader"))
  test.assert_eq(fn(), 9, label .. " load reader")
  local bad, err = compat.load("return +", "=compat-bad")
  test.assert_eq(bad, nil, label .. " syntax error returns nil")
  test.assert_true(type(err) == "string", label .. " syntax error message")
end

test "fallback compat works on this interpreter" (function()
  local compat = load_variant("compat.lua")
  test.assert_eq(compat.flavor_file, "fallback", "fallback marker")
  behaves_like_fallback(compat, "fallback")
end)

test "the variant for this interpreter matches the fallback" (function()
  local tag = running_tag()
  local name = "compat@" .. tag .. ".lua"
  local file = io.open(DIR .. name, "rb")
  if not file then
    print("  (no " .. name .. "; " .. tag .. " uses the fallback)")
    return
  end
  file:close()
  local compat = load_variant(name)
  test.assert_eq(compat.flavor_file, tag, "variant marker")
  behaves_like_fallback(compat, name)
end)

test "require('meteorite.compat') resolves without Moonstone" (function()
  local compat = require("meteorite.compat")
  test.assert_true(type(compat.unpack) == "function", "unpack")
  test.assert_true(type(compat.load) == "function", "load")
end)

test.run()
