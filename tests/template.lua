package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local template = require("codegen.template")
local test = require("test")

test "template.render substitutes placeholders" (function()
  local result = template.render("Hello {{name}}!", {name = "world"})
  test.assert_eq(result, "Hello world!")
end)

test "template.render handles multiple placeholders" (function()
  local result = template.render("{{a}} + {{b}} = {{c}}", {a = 1, b = 2, c = 3})
  test.assert_eq(result, "1 + 2 = 3")
end)

test "template.render handles missing keys as empty" (function()
  local result = template.render("Hello {{name}}!", {})
  test.assert_eq(result, "Hello !")
end)

test "template.render handles nil values as empty" (function()
  local result = template.render("{{x}}", {x = nil})
  test.assert_eq(result, "")
end)

test "template.render converts non-string values" (function()
  local result = template.render("{{n}}", {n = 42})
  test.assert_eq(result, "42")
end)

test "template.render preserves text without placeholders" (function()
  local result = template.render("no placeholders here", {})
  test.assert_eq(result, "no placeholders here")
end)

test "template.render handles zig-like content" (function()
  local tpl = "pub fn route(comptime graph: type) graph.Route {\n    .id = {{id}}, .method = .{{method}}\n}"
  local result = template.render(tpl, {id = '"health"', method = "GET"})
  test.assert_true(result:find('.id = "health"', 1, true) ~= nil, "should have id")
  test.assert_true(result:find(".method = .GET", 1, true) ~= nil, "should have method")
end)

test "template.render_file reads and renders" (function()
  -- Write a temp template file
  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  f:write("{{greeting}}, {{target}}!")
  f:close()
  local result = template.render_file(tmp, {greeting = "Hello", target = "Zig"})
  test.assert_eq(result, "Hello, Zig!")
  os.remove(tmp)
end)

test "template.render_file returns nil for missing" (function()
  local result, err = template.render_file("/nonexistent/template.tpl", {})
  test.assert_eq(result, nil)
  test.assert_true(err ~= nil, "should return error message")
end)

test.run()
