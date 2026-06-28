package.path = "src/?.lua;src/?/init.lua;" .. package.path

local zon = require("codegen.zon")
local test = require("test")

test "zon encodes strings" (function()
  test.assert_eq(zon.encode("hello"), '"hello"\n')
  test.assert_eq(zon.encode(""), '""\n')
  test.assert_eq(zon.encode("with\nnewline"), '"with\\nnewline"\n')
  local q = zon.encode('with "quotes"')
  test.assert_true(q:find('with', 1, true) ~= nil, 'should contain with')
  test.assert_true(q:find('quotes', 1, true) ~= nil, 'should contain quotes')
end)

test "zon encodes numbers" (function()
  test.assert_eq(zon.encode(42), '42\n')
  test.assert_eq(zon.encode(3.14), '3.14\n')
  test.assert_eq(zon.encode(0), '0\n')
  test.assert_eq(zon.encode(-1), '-1\n')
end)

test "zon encodes booleans" (function()
  test.assert_eq(zon.encode(true), 'true\n')
  test.assert_eq(zon.encode(false), 'false\n')
end)

test "zon encodes nil" (function()
  test.assert_eq(zon.encode(nil), 'null\n')
end)

test "zon encodes empty array" (function()
  test.assert_eq(zon.encode({}), '.{}\n')
end)

test "zon encodes sequential array" (function()
  local result = zon.encode({ "a", "b", "c" })
  test.assert_true(result:find('"a"', 1, true) ~= nil, "should contain a")
  test.assert_true(result:find('"b"', 1, true) ~= nil, "should contain b")
  test.assert_true(result:find('"c"', 1, true) ~= nil, "should contain c")
  test.assert_true(result:find(".{", 1, true) ~= nil, "should start with .{")
  test.assert_true(result:find("}", 1, true) ~= nil, "should end with }")
end)

test "zon encodes object" (function()
  local result = zon.encode({ name = "test", count = 3 })
  test.assert_true(result:find(".name", 1, true) ~= nil, "should have .name field")
  test.assert_true(result:find(".count", 1, true) ~= nil, "should have .count field")
  test.assert_true(result:find('"test"', 1, true) ~= nil, "should have test value")
end)

test "zon uses preferred key ordering" (function()
  local result = zon.encode({ zebra = 1, name = 2, apple = 3 })
  -- "name" should appear before "apple" (preferred) and "zebra" (alphabetical after preferred)
  local name_pos = result:find(".name", 1, true)
  local apple_pos = result:find("%.apple")
  local zebra_pos = result:find("%.zebra")
  test.assert_true(name_pos < apple_pos, "name should come before apple")
  test.assert_true(apple_pos < zebra_pos, "apple should come before zebra")
end)

test "zon encodes enum markers" (function()
  local enum = { __meteorite_enum = true, value = "GET" }
  test.assert_eq(zon.encode(enum), '.GET\n')
end)

test "zon rejects functions" (function()
  test.assert_error(function() zon.encode(function() end) end, "cannot serialize")
end)

test "zon handles nested tables" (function()
  local result = zon.encode({ inner = { key = "value" } })
  test.assert_true(result:find(".inner", 1, true) ~= nil, "should have .inner")
  test.assert_true(result:find(".key", 1, true) ~= nil, "should have nested .key")
  test.assert_true(result:find('"value"') ~= nil, "should have value")
end)

test "zon encodes mixed array with nested objects" (function()
  local data = {
    { id = "route_1", method = "GET" },
    { id = "route_2", method = "POST" },
  }
  local result = zon.encode(data)
  test.assert_true(result:find("route_1") ~= nil, "should contain route_1")
  test.assert_true(result:find("route_2") ~= nil, "should contain route_2")
  test.assert_true(result:find(".method", 1, true) ~= nil, "should have method fields")
end)

test "zon skips functions in object fields" (function()
  local result = zon.encode({
    name = "ok",
    fn = function() end,
  })
  test.assert_true(result:find(".name", 1, true) ~= nil, "should have name")
  test.assert_true(result:find(".fn", 1, true) == nil, "should skip fn")
end)

test "zon handles boolean and number values in objects" (function()
  local result = zon.encode({
    enabled = true,
    count = 0,
    ratio = 0.5,
  })
  test.assert_true(result:find("true") ~= nil, "should have true")
  test.assert_true(result:find("0.5") ~= nil, "should have 0.5")
end)

test.run()
