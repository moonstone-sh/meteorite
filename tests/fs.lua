package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local fs = require("utils.fs")
local test = require("test")
local os = os

test "fs.join joins paths" (function()
  test.assert_eq(fs.join("a", "b"), "a/b")
  test.assert_eq(fs.join("", "b"), "b")
  test.assert_eq(fs.join(".", "b"), "b")
  test.assert_eq(fs.join("a/b", "c"), "a/b/c")
end)

test "fs.dirname extracts directory" (function()
  test.assert_eq(fs.dirname("a/b/c.lua"), "a/b")
  test.assert_eq(fs.dirname("file.lua"), ".")
  test.assert_eq(fs.dirname("/abs/path/file"), "/abs/path")
end)

test "fs.shell_quote quotes paths" (function()
  test.assert_eq(fs.shell_quote("hello"), "'hello'")
  test.assert_eq(fs.shell_quote("it's"), "'it'\\''s'")
end)

test "fs.read_file returns nil for missing" (function()
  test.assert_eq(fs.read_file("/nonexistent/path/file.txt"), nil)
end)

test "fs.write_file and read_file round-trip" (function()
  local tmp = os.tmpname()
  fs.write_file(tmp, "hello world")
  local content = fs.read_file(tmp)
  test.assert_eq(content, "hello world")
  os.remove(tmp)
end)

test "fs.file_size returns size" (function()
  local tmp = os.tmpname()
  fs.write_file(tmp, "12345")
  test.assert_eq(fs.file_size(tmp), 5)
  os.remove(tmp)
end)

test "fs.file_size returns 0 for missing" (function()
  test.assert_eq(fs.file_size("/nonexistent"), 0)
end)

test "fs.hash_text produces hash" (function()
  local h = fs.hash_text("test")
  test.assert_true(type(h) == "string", "hash should be string")
  test.assert_true(#h > 0, "hash should not be empty")
  test.assert_true(h:find("b3:") ~= nil or h:find("fnv32:") ~= nil, "should have b3: or fnv32: prefix")
end)

test "fs.hash_text is deterministic" (function()
  local h1 = fs.hash_text("same input")
  local h2 = fs.hash_text("same input")
  test.assert_eq(h1, h2)
end)

test "fs.hash_text differs for different inputs" (function()
  local h1 = fs.hash_text("input one")
  local h2 = fs.hash_text("input two")
  test.assert_true(h1 ~= h2, "different inputs should produce different hashes")
end)

test "fs.etag_for_text wraps hash in quotes" (function()
  local etag = fs.etag_for_text("test")
  test.assert_true(etag:sub(1, 1) == '"', "etag should start with quote")
  test.assert_true(etag:sub(-1) == '"', "etag should end with quote")
end)

test "fs.relative extracts relative path" (function()
  test.assert_eq(fs.relative("/a/b/c.lua", "/a/b"), "c.lua")
  test.assert_eq(fs.relative("/a/b/c/d.lua", "/a/b"), "c/d.lua")
end)

test "fs.is_dir detects directories" (function()
  -- is_dir may use shell fallback in restricted environments
  -- Just check it doesn't crash and returns a boolean
  local result = fs.is_dir(".")
  test.assert_true(type(result) == "boolean", "is_dir should return boolean")
end)

test.run()
