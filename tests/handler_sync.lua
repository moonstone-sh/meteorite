package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local handler_sync = require("codegen.handler_sync")
local test = require("test")

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

test "LuaLS config keeps libraries focused and excludes generated build state" (function()
  local root = os.tmpname()
  os.remove(root)
  assert(os.execute("mkdir -p " .. shell_quote(root .. "/.meteorite/graph/current")))

  handler_sync.sync_luarc(root .. "/.meteorite/graph/current")
  local config = read_file(root .. "/.luarc.json")

  test.assert_true(config:find('"useGitIgnore": true', 1, true) ~= nil, "uses Git ignore")
  test.assert_true(config:find('".zig-cache"', 1, true) ~= nil, "ignores Zig cache")
  test.assert_true(config:find('".ballad"', 1, true) ~= nil, "ignores Ballad state")
  test.assert_true(config:find('"maxPreload": 2000', 1, true) ~= nil, "bounds preload")
  test.assert_true(config:find('".meteorite/aids/lua"', 1, true) ~= nil, "keeps Meteorite aids")
  test.assert_true(config:find('".moonstone/env/share/lua/', 1, true) ~= nil, "keeps Moonstone runtime library")

  assert(os.execute("rm -rf " .. shell_quote(root)))
end)

test.run()
