package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local m = require("meteorite")
local test = require("test")

test "m.dir requires explicit wildcard param" (function()
  test.assert_error(function()
    m.dir("public")
  end, "m.dir requires opts.param", "missing param diagnostic")
end)

test "m.dir rejects implicit index files explicitly" (function()
  test.assert_error(function()
    m.dir("public", { param = "path", index = "index.html" })
  end, "m.dir index files are not supported in the current release", "index diagnostic")
end)

test "m.dir accepts explicit non-index directory handler" (function()
  local handler = m.dir("public", { param = "path", immutable = true })
  test.assert_eq(handler.kind, "dir", "handler kind")
  test.assert_eq(handler.root, "public", "root")
  test.assert_eq(handler.param, "path", "param")
  test.assert_eq(handler.immutable, true, "immutable")
end)

test.run()
