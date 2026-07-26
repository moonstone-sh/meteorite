package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local hybrid = require("cli.hybrid")
local m = require("meteorite")
local test = require("test")

test "hybrid invoke applies compiled pattern contracts to route parameters" (function()
  local app = m.app({ name = "hybrid-patterns" })
  local device_id = m.pattern("^[a-z0-9_-]{1,64}$")

  app:get("/devices/:device_id", {
    params = {
      device_id = m.string({ max = 64, pattern = device_id }),
    },
  }, function(ctx)
    return ctx:text(ctx:param("device_id"))
  end)

  local valid = hybrid.invoke(app, { method = "GET", path = "/devices/router_01" }, { mode = "dev" })
  test.assert_eq(valid.status, 200, "valid patterned parameter status")
  test.assert_eq(valid.body, "router_01", "valid patterned parameter body")

  local invalid = hybrid.invoke(app, { method = "GET", path = "/devices/INVALID" }, { mode = "dev" })
  test.assert_eq(invalid.status, 404, "invalid patterned parameter status")
  test.assert_eq(invalid.body, "not found", "invalid patterned parameter body")
end)

test.run()
