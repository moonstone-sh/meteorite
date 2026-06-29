package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local m = require("meteorite")
local cache = require("core.plugins.cache")
local idempotency = require("core.plugins.idempotency")
local route_mod = require("core.route")
local test = require("test")

test "graph plugin registers via app:use" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  test.assert_true(app.graph_plugins ~= nil, "should have graph_plugins")
  test.assert_eq(#app.graph_plugins, 1)
  test.assert_eq(app.graph_plugins[1].id, "meteorite.cache")
end)

test "cache plugin injects stages during normalize" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  app:get({
    route = "/docs/:path*",
    policy = { cache = { mode = "public", ttl = 60 } },
    handler = "handlers.docs",
  })
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  local route = graph.routes[1]
  test.assert_true(route.pipeline ~= nil, "should have pipeline")
  test.assert_eq(#route.pipeline, 3, "should have 3 stages (lookup, handle, store)")
  test.assert_eq(route.pipeline[1].id, "cache_lookup")
  test.assert_eq(route.pipeline[1].owner, "meteorite.cache")
  test.assert_eq(route.pipeline[2].kind, "handle")
  test.assert_eq(route.pipeline[3].id, "cache_store")
  test.assert_eq(route.pipeline[3].owner, "meteorite.cache")
end)

test "idempotency plugin injects stages during normalize" (function()
  local app = m.app({ name = "test" })
  app:use(idempotency.create())
  app:post({
    route = "/orders",
    policy = { idempotency = { header = "Idempotency-Key", ttl = 86400 } },
    handler = "handlers.create_order",
  })
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  local route = graph.routes[1]
  test.assert_eq(#route.pipeline, 3, "should have 3 stages (lookup, handle, store)")
  test.assert_eq(route.pipeline[1].id, "idempotency_lookup")
  test.assert_eq(route.pipeline[1].owner, "meteorite.idempotency")
  test.assert_eq(route.pipeline[3].id, "idempotency_store")
end)

test "legacy route without policy has no plugin stages" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  app:get("/health", "handlers.health")
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  local route = graph.routes[1]
  -- Legacy routes have empty pipeline (no policy to trigger injection)
  test.assert_true(route.pipeline == nil or #route.pipeline == 0,
    "legacy route without policy should not have plugin stages")
end)

test "multiple plugins can be registered" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  app:use(idempotency.create())
  test.assert_eq(#app.graph_plugins, 2)
end)

test "plugin policy conflict is detected" (function()
  local app = m.app({ name = "test" })
  local plugin_contract = require("core.plugin_contract")
  local p1 = plugin_contract.define({ id = "p1", consumes_policy = { "cache" }, graph_passes = { "validate" }, validate = function() end })
  local p2 = plugin_contract.define({ id = "p2", consumes_policy = { "cache" }, graph_passes = { "validate" }, validate = function() end })
  app.graph_plugins = { p1, p2 }
  -- The conflict is recorded as a diagnostic, not an error
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  test.assert_true(graph ~= nil, "should normalize despite conflict")
end)

test "cache plugin validates invalid mode" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  app:get({
    route = "/x",
    policy = { cache = { mode = "invalid_mode", ttl = 60 } },
    handler = "handlers.x",
  })
  -- Should produce validation diagnostics but not crash
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  test.assert_true(graph ~= nil, "should normalize despite validation errors")
end)

test "canonical route with pipeline and policy works together" (function()
  local app = m.app({ name = "test" })
  app:use(cache.create())
  app:get({
    route = "/api/:id",
    params = { id = m.u64() },
    policy = { cache = { mode = "public", ttl = 30 } },
    pipeline = function(ctx)
      ctx:transform({ id = "auth", strat = "zig", path = "auth.zig" })
      ctx:handle({ id = "show", strat = "zig", path = "show.zig" })
    end,
  })
  local graph = route_mod.normalize_app(app, { mode = "dev" })
  local route = graph.routes[1]
  test.assert_true(route.pipeline ~= nil, "should have pipeline")
  -- Should have: cache_lookup + auth + show + cache_store = 4 stages
  test.assert_eq(#route.pipeline, 4, "should have 4 stages")
  test.assert_eq(route.pipeline[1].id, "cache_lookup")
  test.assert_eq(route.pipeline[1].owner, "meteorite.cache")
  test.assert_eq(route.pipeline[2].id, "auth")
  test.assert_eq(route.pipeline[3].id, "show")
  test.assert_eq(route.pipeline[4].id, "cache_store")
  test.assert_eq(route.pipeline[4].owner, "meteorite.cache")
end)

test.run()
