package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local contract = require("core.contract")
local test = require("test")

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

test.run()
