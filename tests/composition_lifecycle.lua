package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local m = require("meteorite")
local hybrid = require("cli.hybrid")
local route = require("core.route")
local plugin_contract = require("core.plugin_contract")
local test = require("test")

test "mounted scopes retain local and effective graph facts" (function()
  local app = m.app({ name = "scope-facts" })
  local auth = m.plugin({ id = "scope.auth", execute = function() end })
  app:use(auth)
  app:mount("/orgs/:org_id", {
    id = "org",
    params = { org_id = m.u64() },
    query = { locale = m.slug() },
    context = { audience = "org" },
  }, function(org)
    org:mount("/devices", {
      id = "devices",
      context = { feature = "devices" },
    }, function(devices)
      devices:get("/:device_id", {
        params = { device_id = m.slug() },
      }, function(ctx)
        return ctx:text(ctx.scope.audience .. ":" .. ctx.scope.feature)
      end)
    end)
  end)

  local graph = route.normalize_app(app, { mode = "dev" })
  local node = graph.routes[1]
  test.assert_eq(node.scope.id, "devices")
  test.assert_eq(node.scope.parent, "org")
  test.assert_eq(node.scope.local_prefix, "/devices")
  test.assert_eq(node.scope.path_prefix, "/orgs/:org_id/devices")
  test.assert_eq(#node.scope.chain, 2)
  test.assert_eq(node.scope.declared.context.feature, "devices")
  test.assert_eq(node.scope.effective.context.audience, "org")
  test.assert_eq(node.scope.effective.context.feature, "devices")
  test.assert_eq(node.scope.plugins[1], "scope.auth")
end)

test "conflicting inherited declarations fail with a deterministic diagnostic" (function()
  local app = m.app({ name = "scope-conflict" })
  test.assert_error(function()
    app:mount("/orgs", { id = "org", context = { audience = "org" } }, function(org)
      org:mount("/admin", { id = "admin", context = { audience = "admin" } }, function() end)
    end)
  end, "conflicting inherited context declaration", "context collision")
end)

test "equal inherited parameter declarations are accepted" (function()
  local app = m.app({ name = "scope-equal" })
  app:mount("/orgs/:org_id", { id = "org", params = { org_id = m.u64() } }, function(org)
    org:get("/devices", { params = { org_id = m.u64() } }, "handlers.devices")
  end)
  local graph = route.normalize_app(app, { mode = "dev" })
  test.assert_eq(graph.routes[1].params[1].name, "org_id")
end)

test "duplicate scope IDs and path parameters fail" (function()
  local duplicate_id = m.app({ name = "scope-id" })
  duplicate_id:mount("/one", { id = "same" }, function() end)
  test.assert_error(function()
    duplicate_id:mount("/two", { id = "same" }, function() end)
  end, "duplicate mounted scope id", "scope id")

  local duplicate_param = m.app({ name = "scope-param" })
  test.assert_error(function()
    duplicate_param:mount("/orgs/:id", { id = "org" }, function(org)
      org:mount("/projects/:id", { id = "project" }, function() end)
    end)
  end, "conflicting mounted path parameter", "path parameter")
end)

test "request plugins inherit root to leaf once and raw middleware fails" (function()
  local calls = {}
  local app = m.app({ name = "plugins" })
  local root = m.plugin({ id = "root", execute = function() calls[#calls + 1] = "root" end })
  local child = m.plugin({ id = "child", execute = function() calls[#calls + 1] = "child" end })
  app:use(root)
  app:mount("/scope", { id = "scope", plugins = { root, child } }, function(scoped)
    scoped:get("/ready", function(ctx)
      calls[#calls + 1] = "handler"
      return ctx:text("ready")
    end)
  end)
  local response = hybrid.invoke(app, { method = "GET", path = "/scope/ready" })
  test.assert_eq(response.status, 200)
  test.assert_eq(table.concat(calls, ","), "root,child,handler")
  test.assert_error(function()
    app:use(function() end)
  end, "raw app:use(function) middleware is not supported", "raw middleware")
end)

test "scope context is request-visible but immutable" (function()
  local app = m.app({ name = "scope-readonly" })
  app:mount("/scope", { id = "scope", context = { audience = "public" } }, function(scoped)
    scoped:get("/value", function(ctx)
      local ok = pcall(function() ctx.scope.audience = "private" end)
      return ctx:text((ok and "mutable" or "readonly") .. ":" .. ctx.scope.audience)
    end)
  end)
  local response = hybrid.invoke(app, { method = "GET", path = "/scope/value" })
  test.assert_eq(response.body, "readonly:public")
end)

test "graph plugin stage insertion is revalidated" (function()
  local app = m.app({ name = "graph-revalidation" })
  app:use(plugin_contract.define({
    id = "test.insert",
    graph_passes = { "transform" },
    transform = function(graph, api)
      api:insert_stage_before("route_ready", "handle", {
        id = "before_handle",
        kind = "hook",
        phase = "post_handler",
        strat = "zig",
        symbol = "handlers.bad",
      })
    end,
  }))
  app:get({
    route = "/ready",
    id = "route_ready",
    pipeline = function(p)
      p:handle({ id = "handle", strat = "zig", symbol = "handlers.ready" })
    end,
  })
  test.assert_error(function()
    route.normalize_app(app, { mode = "dev" })
  end, "invalid hook ordering in pipeline", "post-transform pipeline validation")
end)

test "graph plugins have unique IDs and deterministic pass ordering" (function()
  local order = {}
  local app = m.app({ name = "graph-order" })
  app:use(plugin_contract.define({ id = "zeta", graph_passes = { "validate" }, validate = function() order[#order + 1] = "zeta" end }))
  app:use(plugin_contract.define({ id = "alpha", graph_passes = { "validate" }, validate = function() order[#order + 1] = "alpha" end }))
  app:get("/ready", "handlers.ready")
  route.normalize_app(app, { mode = "dev" })
  test.assert_eq(table.concat(order, ","), "alpha,zeta")
  test.assert_error(function()
    app:use(plugin_contract.define({ id = "alpha" }))
  end, "duplicate graph plugin id", "graph plugin id")
end)

test "scope snapshots are serializable into graph artifacts" (function()
  local app = m.app({ name = "scope-artifact" })
  app:mount("/orgs/:org_id", {
    id = "organization",
    params = { org_id = m.u64() },
    context = { audience = "operators" },
  }, function(org)
    org:get("/ready", "handlers.ready")
  end)
  local graph = route.normalize_app(app, { mode = "dev" })
  local scope = graph.routes[1].scope
  test.assert_eq(scope.declared.context.audience, "operators")
  test.assert_eq(scope.effective.params.org_id.type, "u64")
end)

test.run()
