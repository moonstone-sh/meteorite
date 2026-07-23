package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local json = require("utils.json")
local test = require("test")

test "json encodes nil" (function()
  test.assert_eq(json.encode(nil), "null")
end)

test "json encodes booleans" (function()
  test.assert_eq(json.encode(true), "true")
  test.assert_eq(json.encode(false), "false")
end)

test "json encodes numbers" (function()
  test.assert_eq(json.encode(42), "42")
  test.assert_eq(json.encode(3.14), "3.14")
  test.assert_eq(json.encode(0), "0")
  test.assert_eq(json.encode(-1), "-1")
end)

test "json encodes strings" (function()
  test.assert_eq(json.encode("hello"), '"hello"')
  test.assert_eq(json.encode(""), '""')
  test.assert_eq(json.encode('with "quotes"'), '"with \\"quotes\\""')
end)

test "json escapes special characters" (function()
  test.assert_eq(json.encode("with\nnewline"), '"with\\nnewline"')
  test.assert_eq(json.encode("with\\backslash"), '"with\\\\backslash"')
end)

test "json encodes empty array" (function()
  test.assert_eq(json.encode({}), "[]")
end)

test "json encodes array" (function()
  test.assert_eq(json.encode({1, 2, 3}), "[1,2,3]")
  test.assert_eq(json.encode({"a", "b"}), '["a","b"]')
end)

test "json encodes object" (function()
  local result = json.encode({name = "test", count = 3})
  test.assert_true(result:find('"name":"test"', 1, true) ~= nil, "should have name field")
  test.assert_true(result:find('"count":3', 1, true) ~= nil, "should have count field")
end)

test "json sorts object keys" (function()
  local result = json.encode({zebra = 1, apple = 2})
  local apple_pos = result:find('"apple"', 1, true)
  local zebra_pos = result:find('"zebra"', 1, true)
  test.assert_true(apple_pos < zebra_pos, "apple should come before zebra")
end)

test "json handles nested objects" (function()
  local result = json.encode({outer = {inner = "value"}})
  test.assert_true(result:find('"outer"', 1, true) ~= nil, "should have outer")
  test.assert_true(result:find('"inner":"value"', 1, true) ~= nil, "should have inner:value")
end)

test "json handles nested arrays" (function()
  local result = json.encode({{1, 2}, {3, 4}})
  test.assert_eq(result, "[[1,2],[3,4]]")
end)

test "json handles mixed types" (function()
  local result = json.encode({str = "a", num = 1, bool = true})
  test.assert_true(result:find('"str":"a"', 1, true) ~= nil)
  test.assert_true(result:find('"num":1', 1, true) ~= nil)
  test.assert_true(result:find('"bool":true', 1, true) ~= nil)
end)

test.run()
