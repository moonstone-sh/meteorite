package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

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

test "sync preserves Composer plugins, JSONC comments and custom settings idempotently" (function()
  local root = os.tmpname()
  os.remove(root)
  assert(os.execute("mkdir -p " .. shell_quote(root .. "/.meteorite/graph/current")))
  local config = root .. "/.luarc.json"
  local file = assert(io.open(config, "wb"))
  file:write([[{
  // Workspace-owned Composer configuration.
  "runtime": {"plugin": "composer/init.lua", "pluginArgs": ["--config=plugins.json"], "path": ["custom/?.lua"]},
  "workspace": {"library": ["custom/types"], "maxPreload": 321},
  "diagnostics": {"disable": ["unused-local"]},
  "format": {"enable": false},
}]])
  file:close()
  handler_sync.sync_luarc(root .. "/.meteorite/graph/current")
  local first = read_file(config)
  test.assert_true(first:find("Workspace-owned Composer configuration", 1, true) ~= nil)
  for _, needle in ipairs({"composer/init.lua", "--config=plugins.json", "custom/?.lua", "custom/types", "unused-local", ".meteorite/aids/lua"}) do
    test.assert_true(first:find(needle, 1, true) ~= nil, "preserves " .. needle)
  end
  test.assert_true(first:find('"maxPreload": 321', 1, true) ~= nil)
  test.assert_true(first:find('"enable": false', 1, true) ~= nil)
  handler_sync.sync_luarc(root .. "/.meteorite/graph/current")
  test.assert_eq(read_file(config), first, "repeated sync does not rewrite the workspace config")
  assert(os.execute("rm -rf " .. shell_quote(root)))
end)

test "sync refuses conflicting config shapes without overwriting the file" (function()
  local root = os.tmpname()
  os.remove(root)
  assert(os.execute("mkdir -p " .. shell_quote(root .. "/.meteorite/graph/current")))
  local config = root .. "/.luarc.json"
  local original = '{"runtime":{"plugin":"keep.lua"},"workspace":{"library":"not-an-array"}}'
  local file = assert(io.open(config,"wb"));file:write(original);file:close()
  local ok = pcall(handler_sync.sync_luarc, root .. "/.meteorite/graph/current")
  test.assert_true(not ok, "invalid config must report a conflict")
  test.assert_eq(read_file(config), original, "a conflict must not partially commit edits")
  assert(os.execute("rm -rf " .. shell_quote(root)))
end)

test.run()
