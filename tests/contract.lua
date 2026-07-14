package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local contract = require("core.contract")
local test = require("test")
local m = require("meteorite")

-- ============================================================
-- 1.1 Contract parser tests
-- ============================================================

test "canonical route with handler" (function()
  local rc = contract.build("GET", {
    route = "/health",
    handler = function(ctx) return "ok" end,
  })
  test.assert_eq(rc.method, "GET")
  test.assert_eq(rc.route, "/health")
  test.assert_true(rc.pipeline ~= nil, "should have pipeline")
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].kind, "handle")
  test.assert_eq(rc.pipeline[1].strat, "inline_lua")
  test.assert_eq(rc._source_form, "canonical")
end)

test "canonical route with pipeline" (function()
  local rc = contract.build("GET", {
    route = "/orders/:id",
    pipeline = function(ctx)
      ctx:transform({ id = "auth", strat = "lua", path = "transforms/auth.lua" })
      ctx:handle({ id = "get_order", strat = "lua", path = "handlers/get_order.lua" })
    end,
  })
  test.assert_eq(rc.method, "GET")
  test.assert_eq(rc.route, "/orders/:id")
  test.assert_eq(#rc.pipeline, 2)
  test.assert_eq(rc.pipeline[1].id, "auth")
  test.assert_eq(rc.pipeline[1].kind, "transform")
  test.assert_eq(rc.pipeline[1].strat, "lua")
  test.assert_eq(rc.pipeline[1].path, "transforms/auth.lua")
  test.assert_eq(rc.pipeline[2].id, "get_order")
  test.assert_eq(rc.pipeline[2].kind, "handle")
end)

test "inline Lua transform" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform(function(ctx) ctx.state.foo = "bar" end)
    end,
  })
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].strat, "inline_lua")
  test.assert_true(rc.pipeline[1].fn_ref ~= nil, "should have fn_ref")
end)

test "external Lua transform" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform("lua", "transforms/auth.lua")
    end,
  })
  test.assert_eq(rc.pipeline[1].strat, "lua")
  test.assert_eq(rc.pipeline[1].path, "transforms/auth.lua")
end)

test "external Zig transform contract" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform({ id = "load", strat = "zig", path = "transforms/load.zig" })
    end,
  })
  test.assert_eq(rc.pipeline[1].strat, "zig")
  test.assert_eq(rc.pipeline[1].path, "transforms/load.zig")
  test.assert_eq(rc.pipeline[1].id, "load")
end)

test "positional form transform" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform("zig", "transforms/crunch.zig")
    end,
  })
  test.assert_eq(rc.pipeline[1].strat, "zig")
  test.assert_eq(rc.pipeline[1].path, "transforms/crunch.zig")
end)

test "malformed route table — missing route" (function()
  -- A table with no .route field and no [1] positional path
  -- should produce an error during build
  test.assert_error(function()
    contract.build("GET", { pipeline = function(ctx) end })
  end)
end)

test "duplicate stage ids" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:transform({ id = "dup", strat = "lua", path = "a.lua" })
        ctx:handle({ id = "dup", strat = "lua", path = "b.lua" })
      end,
    })
  end, "duplicate stage id")
end)

test "conflicting handler and pipeline" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      handler = function(ctx) return "ok" end,
      pipeline = function(ctx) ctx:handle("lua", "h.lua") end,
    })
  end, "mutually exclusive")
end)

test "rust strategy rejected with clear message" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:transform({ strat = "rust", path = "transforms/x.rs" })
      end,
    })
  end, "Rust")
end)

test "hook with valid phase" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:hook("pre_handler", { id = "log", strat = "lua", path = "hooks/log.lua" })
    end,
  })
  test.assert_eq(rc.pipeline[1].kind, "hook")
  test.assert_eq(rc.pipeline[1].phase, "pre_handler")
end)

test "hook with invalid phase rejected" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:hook("invalid_phase", { strat = "lua", path = "x.lua" })
      end,
    })
  end, "invalid hook phase")
end)

test "hook with inline function" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:hook("observe", function(ctx) end)
    end,
  })
  test.assert_eq(rc.pipeline[1].kind, "hook")
  test.assert_eq(rc.pipeline[1].phase, "observe")
  test.assert_eq(rc.pipeline[1].strat, "inline_lua")
end)

test "hook phase permissions reject impossible reads and writes" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test/:id",
      pipeline = function(ctx)
        ctx:hook("pre_tree", { strat = "lua", path = "x.lua", reads = { "route_param.id" } })
      end,
    })
  end, "must not read route params")

  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:hook("observe", { strat = "lua", path = "x.lua", writes = { "response.headers" } })
      end,
    })
  end, "must not write to response")
end)

test "all hook phases can declare valid resource access" (function()
  local rc = contract.build("GET", {
    route = "/test/:id",
    pipeline = function(ctx)
      ctx:hook("pre_tree", { id = "pre_tree", strat = "lua", path = "pre_tree.lua", reads = { "request.path" } })
      ctx:hook("post_match", { id = "post_match", strat = "lua", path = "post_match.lua", reads = { "route.params" } })
      ctx:hook("pre_handler", { id = "pre_handler", strat = "lua", path = "pre_handler.lua", writes = { "state.auth" } })
      ctx:handle({ id = "handle", strat = "lua", path = "handle.lua" })
      ctx:hook("post_handler", { id = "post_handler", strat = "lua", path = "post_handler.lua", writes = { "response.headers" } })
      ctx:hook("observe", { id = "observe", strat = "lua", path = "observe.lua", reads = { "response.status" }, may_short_circuit = false })
      ctx:hook("error", { id = "error", strat = "lua", path = "error.lua", reads = { "error" }, writes = { "response.body" } })
    end,
  })
  test.assert_eq(#rc.pipeline, 7)
  test.assert_eq(rc.pipeline[1].phase, "pre_tree")
  test.assert_eq(rc.pipeline[7].phase, "error")
end)

test "hook ordering is deterministic around handle stage" (function()
  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:handle({ id = "handle", strat = "lua", path = "handle.lua" })
        ctx:hook("pre_handler", { id = "too_late", strat = "lua", path = "pre.lua" })
      end,
    })
  end, "invalid hook ordering")

  test.assert_error(function()
    contract.build("GET", {
      route = "/test",
      pipeline = function(ctx)
        ctx:hook("post_handler", { id = "too_early", strat = "lua", path = "post.lua" })
        ctx:handle({ id = "handle", strat = "lua", path = "handle.lua" })
      end,
    })
  end, "invalid hook ordering")
end)

test "pipeline builder records stages in order" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform({ id = "t1", strat = "lua", path = "a.lua" })
      ctx:handle({ id = "h1", strat = "lua", path = "b.lua" })
      ctx:transform({ id = "t2", strat = "lua", path = "c.lua" })
    end,
  })
  test.assert_eq(#rc.pipeline, 3)
  test.assert_eq(rc.pipeline[1].id, "t1")
  test.assert_eq(rc.pipeline[2].id, "h1")
  test.assert_eq(rc.pipeline[3].id, "t2")
end)

-- ============================================================
-- 1.2 Legacy lowering tests
-- ============================================================

test "legacy string handler lowers to pipeline" (function()
  local rc = contract.build("GET", { "/health", {}, "handlers.health" })
  test.assert_true(rc.pipeline ~= nil, "should have pipeline")
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].kind, "handle")
  test.assert_eq(rc.pipeline[1].strat, "zig")
  test.assert_eq(rc.pipeline[1].symbol, "health")
  test.assert_true(rc.pipeline[1]._legacy, "should be marked legacy")
end)

test "legacy function handler lowers to pipeline" (function()
  local rc = contract.build("GET", { "/health", function(ctx) return "ok" end })
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].kind, "handle")
  test.assert_eq(rc.pipeline[1].strat, "inline_lua")
  test.assert_true(rc.pipeline[1]._legacy, "should be marked legacy")
  test.assert_eq(rc._source_form, "legacy_signature")
end)

test "legacy table handler (lua file) lowers to pipeline" (function()
  local rc = contract.build("GET", { "/test", {}, { kind = "lua", path = "h.lua", module = "h" } })
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].strat, "lua")
  test.assert_eq(rc.pipeline[1].path, "h.lua")
end)

test "legacy table handler (zig file) lowers to pipeline" (function()
  local rc = contract.build("GET", { "/test", {}, { kind = "zig_file", path = "h.zig", decl = "handle" } })
  test.assert_eq(#rc.pipeline, 1)
  test.assert_eq(rc.pipeline[1].strat, "zig")
  test.assert_eq(rc.pipeline[1].path, "h.zig")
  test.assert_eq(rc.pipeline[1].decl, "handle")
end)

test "legacy file/dir handler does not get a pipeline" (function()
  local rc = contract.build("GET", { "/test", {}, { kind = "file", artifact_path = "static/x.html", content_type = "text/html" } })
  test.assert_true(rc.pipeline == nil, "file handler should not have pipeline")
  test.assert_true(rc.handler ~= nil, "should have special handler")
  test.assert_eq(rc.handler.kind, "file")
end)

-- ============================================================
-- 6.1 Graph serialization tests
-- ============================================================

test "serialize produces inspectable table" (function()
  local rc = contract.build("GET", {
    route = "/orders/:id",
    pipeline = function(ctx)
      ctx:transform({ id = "auth", strat = "lua", path = "auth.lua" })
      ctx:handle({ id = "show", strat = "lua", path = "show.lua" })
    end,
  })
  local s = contract.serialize(rc)
  test.assert_eq(s.method, "GET")
  test.assert_eq(s.route, "/orders/:id")
  test.assert_eq(s.has_pipeline, true)
  test.assert_eq(#s.pipeline, 2)
  test.assert_eq(s.pipeline[1].id, "auth")
  test.assert_eq(s.pipeline[1].kind, "transform")
  test.assert_eq(s.pipeline[2].id, "show")
  test.assert_eq(s.pipeline[2].kind, "handle")
  test.assert_eq(s.source_form, "canonical")
end)

test "serialize legacy shows source form" (function()
  local rc = contract.build("GET", { "/health", "handlers.health" })
  local s = contract.serialize(rc)
  test.assert_eq(s.source_form, "legacy_signature")
end)

test "serialize inline Lua shows inline marker" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform(function(ctx) end)
    end,
  })
  local s = contract.serialize(rc)
  test.assert_eq(s.pipeline[1].inline, true)
end)

test "transform-only pipeline flagged" (function()
  local rc = contract.build("GET", {
    route = "/test",
    pipeline = function(ctx)
      ctx:transform({ strat = "lua", path = "x.lua" })
    end,
  })
  test.assert_true(rc._transform_only_pipeline, "should flag transform-only pipeline")
end)

test "strict docs fail release undocumented routes" (function()
  local app = m.app({ name = "docs-strict" })
  app:get("/undocumented", "handlers.ok")
  test.assert_error(function()
    app:normalize({ mode = "release-static", strict_docs = true })
  end, "undocumented routes detected in release build", "strict docs diagnostic")
end)

test "strict docs accepts documented release routes" (function()
  local app = m.app({ name = "docs-strict-ok" })
  app:get("/documented", {
    summary = "Documented route",
    responses = { [200] = { description = "OK" } },
  }, "handlers.ok")
  local graph = app:normalize({ mode = "release-static", strict_docs = true })
  test.assert_eq(#graph.routes, 1, "documented graph builds")
end)

test "ipc backend rejects annotated HTTP-only hook resources" (function()
  local app = m.app({ name = "ipc-resource-fail" })
  app:message({
    name = "docs.fail",
    pipeline = function(ctx)
      ctx:handle({ id = "handle", strat = "zig", symbol = "handlers.ok" })
      ctx:hook("post_handler", { id = "bad_http_resource", strat = "zig", symbol = "handlers.bad", writes = { "response.headers" } })
    end,
  })
  test.assert_error(function()
    app:normalize({ mode = "dev", backend = "ipc_unixsocket" })
  end, "backend-incompatible pipeline resource", "ipc backend resource diagnostic")
end)

test "ipc backend accepts IPC resource annotations" (function()
  local app = m.app({ name = "ipc-resource-ok" })
  app:message({
    name = "docs.ok",
    pipeline = function(ctx)
      ctx:handle({ id = "handle", strat = "zig", symbol = "handlers.ok" })
      ctx:hook("post_handler", {
        id = "ipc_resource",
        strat = "zig",
        symbol = "handlers.ipc",
        reads = { "request.message", "request.metadata.id" },
        writes = { "response.result", "response.metadata.trace" },
      })
    end,
  })
  local graph = app:normalize({ mode = "dev", backend = "ipc_unixsocket" })
  test.assert_eq(#graph.messages, 1, "message graph builds")
end)

test "websocket routes fail with explicit unsupported diagnostic" (function()
  local app = m.app({ name = "websocket-fail" })
  test.assert_error(function()
    app:websocket("/ws", function() end)
  end, "does not support WebSocket routes", "websocket diagnostic")
end)

test "ws alias fails with same unsupported diagnostic" (function()
  local app = m.app({ name = "websocket-alias-fail" })
  test.assert_error(function()
    app:ws("/ws", function() end)
  end, "connection-upgrade lifecycle", "ws alias diagnostic")
end)

test.run()
