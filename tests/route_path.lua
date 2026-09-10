package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local route = require("core.route")
local test = require("test")

test "final wildcard and catch-all path param are accepted" (function()
  local wildcard = route.parse_path("/assets/*")
  test.assert_eq(wildcard[2].kind, "wildcard")

  local catch_all = route.parse_path("/files/:path*")
  test.assert_eq(catch_all[2].name, "path")
  test.assert_true(catch_all[2].catch_all)
end)

test "a repeated wildcard cannot hide a non-final wildcard" (function()
  test.assert_error(function() route.parse_path("/a/*/*") end,
    "wildcard * must be the final route segment")
end)

test "a repeated catch-all cannot hide a non-final catch-all" (function()
  test.assert_error(function() route.parse_path("/a/:first*/:second*") end,
    "catch-all path param must be the final route segment")
end)

test.run()
