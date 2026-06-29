package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local plugin_contract = require("core.plugin_contract")
local hooks = require("core.hooks")
local cache_plugin = require("core.plugins.cache")
local idempotency_plugin = require("core.plugins.idempotency")
local test = require("test")

-- ============================================================
-- 5.1 Plugin registration tests
-- ============================================================

test "plugin registers with id" (function()
  local p = plugin_contract.define({ id = "my.plugin", graph_passes = { "validate" } })
  test.assert_eq(p.id, "my.plugin")
  test.assert_true(p.__meteorite_graph_plugin, "should be marked as graph plugin")
end)

test "plugin requires id" (function()
  test.assert_error(function()
    plugin_contract.define({})
  end, "id")
end)

test "plugin policy ownership conflict detected" (function()
  local p1 = plugin_contract.define({ id = "p1", consumes_policy = { "cache" } })
  local p2 = plugin_contract.define({ id = "p2", consumes_policy = { "cache" } })
  local result = plugin_contract.run_passes({ routes = {} }, { p1, p2 })
  local found_conflict = false
  for _, d in ipairs(result.diagnostics) do
    if d.message:find("ownership conflict", 1, true) then found_conflict = true end
  end
  test.assert_true(found_conflict, "should detect policy ownership conflict")
end)

-- ============================================================
-- 5.2 Graph API tests
-- ============================================================

test "plugin can append stage to route" (function()
  local graph = {
    routes = {
      { id = "route_1", raw_path = "/test", pipeline = { { id = "h1", kind = "handle" } } },
    },
  }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  api:append_stage("route_1", { id = "injected", kind = "transform", strat = "lua", path = "x.lua" })
  test.assert_eq(#graph.routes[1].pipeline, 2)
  test.assert_eq(graph.routes[1].pipeline[2].id, "injected")
  test.assert_eq(graph.routes[1].pipeline[2].owner, "test.plugin")
end)

test "plugin can prepend stage to route" (function()
  local graph = {
    routes = {
      { id = "route_1", pipeline = { { id = "h1", kind = "handle" } } },
    },
  }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  api:prepend_stage("route_1", { id = "injected", kind = "transform", strat = "lua" })
  test.assert_eq(graph.routes[1].pipeline[1].id, "injected")
  test.assert_eq(graph.routes[1].pipeline[1].owner, "test.plugin")
end)

test "plugin can insert stage before target" (function()
  local graph = {
    routes = {
      { id = "r1", pipeline = {
        { id = "t1", kind = "transform" },
        { id = "h1", kind = "handle" },
      } },
    },
  }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  api:insert_stage_before("r1", "h1", { id = "injected", kind = "transform" })
  test.assert_eq(graph.routes[1].pipeline[2].id, "injected")
  test.assert_eq(graph.routes[1].pipeline[3].id, "h1")
end)

test "plugin can insert stage after target" (function()
  local graph = {
    routes = {
      { id = "r1", pipeline = {
        { id = "t1", kind = "transform" },
        { id = "h1", kind = "handle" },
      } },
    },
  }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  api:insert_stage_after("r1", "t1", { id = "injected", kind = "transform" })
  test.assert_eq(graph.routes[1].pipeline[2].id, "injected")
  test.assert_eq(graph.routes[1].pipeline[3].id, "h1")
end)

test "plugin can get route policy" (function()
  local graph = {
    routes = {
      { id = "r1", policy = { cache = { ttl = 60 } } },
    },
  }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  local policy = api:get_policy("r1", "cache")
  test.assert_eq(policy.ttl, 60)
end)

test "plugin errors on missing route" (function()
  local api = plugin_contract.create_graph_api({ routes = {} }, "test.plugin")
  test.assert_error(function()
    api:append_stage("nonexistent", { kind = "transform" })
  end, "route not found")
end)

test "plugin can add global hook" (function()
  local graph = { routes = {} }
  local api = plugin_contract.create_graph_api(graph, "test.plugin")
  api:add_hook("pre_tree", { kind = "hook", strat = "lua", path = "hook.lua" })
  test.assert_eq(#graph.hooks, 1)
  test.assert_eq(graph.hooks[1].owner_plugin, "test.plugin")
  test.assert_eq(graph.hooks[1].phase, "pre_tree")
end)

test "plugin can add diagnostic" (function()
  local api = plugin_contract.create_graph_api({ routes = {} }, "test.plugin")
  api:add_diagnostic("warning", "test warning")
  test.assert_eq(#api._diagnostics, 1)
  test.assert_eq(api._diagnostics[1].severity, "warning")
  test.assert_eq(api._diagnostics[1].plugin, "test.plugin")
end)

-- ============================================================
-- 5.3 First-party cache plugin tests
-- ============================================================

test "cache plugin validates policy" (function()
  local cache = cache_plugin.create()
  local graph = {
    routes = {
      { id = "r1", policy = { cache = { mode = "invalid", ttl = 60 } } },
    },
  }
  local result = plugin_contract.run_passes(graph, { cache })
  local found_error = false
  for _, d in ipairs(result.diagnostics) do
    if d.message:find("mode must be", 1, true) then found_error = true end
  end
  test.assert_true(found_error, "should validate cache mode")
end)

test "cache plugin injects lookup and store stages" (function()
  local cache = cache_plugin.create()
  local graph = {
    routes = {
      { id = "r1", raw_path = "/docs", policy = { cache = { mode = "public", ttl = 60 } },
        pipeline = { { id = "h1", kind = "handle", strat = "zig" } } },
    },
  }
  plugin_contract.run_passes(graph, { cache })
  test.assert_eq(#graph.routes[1].pipeline, 3)
  test.assert_eq(graph.routes[1].pipeline[1].id, "cache_lookup")
  test.assert_eq(graph.routes[1].pipeline[3].id, "cache_store")
  test.assert_eq(graph.routes[1].pipeline[1].owner, "meteorite.cache")
end)

test "cache plugin skips disabled routes" (function()
  local cache = cache_plugin.create()
  local graph = {
    routes = {
      { id = "r1", policy = { cache = { disabled = true } },
        pipeline = { { id = "h1", kind = "handle" } } },
    },
  }
  plugin_contract.run_passes(graph, { cache })
  test.assert_eq(#graph.routes[1].pipeline, 1, "should not inject stages for disabled routes")
end)

-- ============================================================
-- 5.4 First-party idempotency plugin tests
-- ============================================================

test "idempotency plugin validates header requirement" (function()
  local idemp = idempotency_plugin.create()
  local graph = {
    routes = {
      { id = "r1", policy = { idempotency = { ttl = 3600 } } },
    },
  }
  local result = plugin_contract.run_passes(graph, { idemp })
  local found_error = false
  for _, d in ipairs(result.diagnostics) do
    if d.message:find("header", 1, true) then found_error = true end
  end
  test.assert_true(found_error, "should require header field")
end)

test "idempotency plugin injects lookup and store" (function()
  local idemp = idempotency_plugin.create()
  local graph = {
    routes = {
      { id = "r1", raw_path = "/orders", method = "POST",
        policy = { idempotency = { header = "Idempotency-Key", ttl = 86400 } },
        pipeline = { { id = "create", kind = "handle", strat = "lua", path = "create.lua" } } },
    },
  }
  plugin_contract.run_passes(graph, { idemp })
  test.assert_eq(#graph.routes[1].pipeline, 3)
  test.assert_eq(graph.routes[1].pipeline[1].id, "idempotency_lookup")
  test.assert_eq(graph.routes[1].pipeline[3].id, "idempotency_store")
  test.assert_eq(graph.routes[1].pipeline[1].owner, "meteorite.idempotency")
end)

-- ============================================================
-- 4. Hook phase enforcement tests
-- ============================================================

test "observe hook cannot short-circuit" (function()
  local err = hooks.validate({
    kind = "hook", phase = "observe",
    may_short_circuit = true, strat = "lua", path = "x.lua",
  })
  test.assert_true(err ~= nil, "should reject observe hook with short_circuit")
  test.assert_true(err:find("short-circuit", 1, true) ~= nil, "should mention short-circuit")
end)

test "observe hook cannot write response" (function()
  local err = hooks.validate({
    kind = "hook", phase = "observe",
    may_short_circuit = false, strat = "lua",
    writes = { "response.body" },
  })
  test.assert_true(err ~= nil, "should reject observe hook writing response")
end)

test "pre_tree hook cannot require route params" (function()
  local err = hooks.validate({
    kind = "hook", phase = "pre_tree",
    strat = "lua", reads = { "route_param.id" },
  })
  test.assert_true(err ~= nil, "should reject pre_tree hook reading route params")
end)

test "valid observe hook passes" (function()
  local err = hooks.validate({
    kind = "hook", phase = "observe",
    may_short_circuit = false, strat = "lua",
    reads = { "response.status" },
  })
  test.assert_eq(err, nil)
end)

test "hooks.validate_graph finds errors" (function()
  local errors = hooks.validate_graph({
    routes = {
      { id = "r1", pipeline = {
        { kind = "hook", phase = "observe", may_short_circuit = true, strat = "lua" },
      } },
    },
  })
  test.assert_true(#errors > 0, "should find hook validation errors")
end)

test "hooks.describe returns description" (function()
  local desc = hooks.describe("pre_tree")
  test.assert_true(desc:find("Before", 1, true) ~= nil, "should describe pre_tree")
end)

-- ============================================================
-- 9.5 Diagnostics tests
-- ============================================================

test "plugin validation error includes plugin id" (function()
  local p = plugin_contract.define({
    id = "my.test.plugin",
    graph_passes = { "validate" },
    validate = function(graph, diag)
      diag.emit("error", "test error from plugin")
    end,
  })
  local result = plugin_contract.run_passes({ routes = {} }, { p })
  test.assert_eq(#result.diagnostics, 1)
  test.assert_eq(result.diagnostics[1].plugin, "my.test.plugin")
  test.assert_eq(result.diagnostics[1].message, "test error from plugin")
end)

test "plugin transform can add codegen unit" (function()
  local p = plugin_contract.define({
    id = "codegen.plugin",
    graph_passes = { "transform" },
    transform = function(graph, api)
      api:add_codegen_unit("generated.zig", "pub const x = 42;")
    end,
  })
  local result = plugin_contract.run_passes({ routes = {} }, { p })
  test.assert_eq(#result.codegen_units, 1)
  test.assert_eq(result.codegen_units[1].name, "generated.zig")
  test.assert_eq(result.codegen_units[1].owner, "codegen.plugin")
end)

test.run()
