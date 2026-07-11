package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local m = require("meteorite")
local route = require("core.route")
local test = require("test")

test "inferred HTTP message names sanitize numeric path segments" (function()
  local app = m.app({ name = "messages" })
  app:get("/bench/work/cpu/50us", "handlers.cpu")
  local graph = route.normalize_app(app, { mode = "dev" })
  test.assert_eq(graph.routes[1].message.name, "bench.work.cpu._50us.get")
end)

test "explicit message names remain strict dot identifiers" (function()
  local app = m.app({ name = "messages" })
  app:message("bench.work.cpu.50us.get", function(ctx) return ctx:text("bad") end)
  test.assert_error(function()
    route.normalize_app(app, { mode = "dev" })
  end, "invalid message name")
end)

test "canonical message table lands in message graph" (function()
  local app = m.app({ name = "messages" })
  app:message({
    name = "system.ping",
    handler = function(ctx) return ctx:text("pong") end,
  })
  local graph = route.normalize_app(app, { mode = "dev" })
  test.assert_eq(#graph.routes, 0)
  test.assert_eq(#graph.messages, 1)
  test.assert_eq(graph.messages[1].message.name, "system.ping")
  test.assert_eq(graph.messages[1].message.source, "message")
end)

test.run()
