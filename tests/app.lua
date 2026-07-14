package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local m = require("meteorite")
local test = require("test")

test "app rejects trusted proxy config explicitly" (function()
  test.assert_error(function()
    m.app({ name = "proxy-fail", trusted_proxy = { cidrs = { "10.0.0.0/8" } } })
  end, "does not support trusted proxy configuration", "trusted proxy diagnostic")
end)

test "app rejects trust proxy alias explicitly" (function()
  test.assert_error(function()
    m.app({ name = "proxy-alias-fail", trust_proxy = true })
  end, "proxy-derived client IP headers", "trust proxy alias diagnostic")
end)

test "app still accepts ordinary options" (function()
  local app = m.app({ name = "ordinary", host = "127.0.0.1", port = 8080 })
  test.assert_eq(app.name, "ordinary", "app name")
  test.assert_eq(app.options.host, "127.0.0.1", "host option")
  test.assert_eq(app.options.port, 8080, "port option")
end)

test.run()
