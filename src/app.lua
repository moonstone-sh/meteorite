local m = require("meteorite")

local app = m.app({ name = "basic-service", host = "127.0.0.1", port = 8080 })

app:capability("http", {
  db = {
    base_url = "http://localhost:8888",
    timeout_ms = 1500,
    max_response_bytes = 65536,
  },
})

app:capability("zig", {
  data_cruncher = "native/src/helpers/data_cruncher.zig",
})

-- Benchmark routes (always static Zig handlers)
app:get("/__bench/plain", "handlers.plain")
app:get("/__bench/plain-static", "handlers.plain_static")
app:get("/__bench/hybrid-zig", "handlers.hybrid_zig")
app:get("/__bench/meta", "handlers.bench_meta")
app:get("/__bench/raw", "handlers.bench_raw")
app:get("/__bench/counters", "handlers.bench_counters")

app:get("/health", "handlers.health")
app:get("/users/:id", {
  params = { id = m.u64() },
}, "handlers.get_user")

app:put("/users/:id", {
  params = { id = m.u64() },
}, "handlers.put_user")

app:patch("/users/:id", {
  params = { id = m.u64() },
}, "handlers.patch_user")

app:delete("/users/:id", {
  params = { id = m.u64() },
}, "handlers.delete_user")

app:post("/echo", {
  body = {
    max = "8kb",
  },
  memory = { request_arena = "16kb" },
}, "handlers.echo")

local device_id = m.pattern("^[a-z0-9_-]{1,64}$", {
  max_dfa_states = 128,
  max_dfa_bytes = "8kb",
})

app:get("/devices/:device_id", {
  params = {
    device_id = m.string({ max = 64, pattern = device_id }),
  },
}, "handlers.get_device")

app:get("/files/:name", {
  params = {
    name = m.string({ max = 80, pattern = m.pattern("^[a-z0-9_.-]{1,80}$") }),
  },
}, "handlers.file")

app:get("/slugs/:slug", {
  params = { slug = m.slug({ max = 64 }) },
}, "handlers.slug")

app:get("/uuids/:id", {
  params = { id = m.uuid() },
}, "handlers.uuid")

app:get("/hex/:digest", {
  params = { digest = m.hex({ len = 32 }) },
}, "handlers.hex")

app:get("/emails/:email", {
  params = { email = m.email() },
}, "handlers.email")

app:get("/tokens/:token", {
  params = { token = m.token({ max = 64 }) },
}, "handlers.token")

app:get("/search", {
  query = {
    q = m.string({ max = 80 }),
    page = m.u64({ optional = true }),
    exact = m.bool({ optional = true }),
  },
}, "handlers.search")

-- Hybrid-inline benchmark route: inline Lua in hybrid mode, Zig in static mode.
local mode = _G.METEORITE_BUILD_MODE or "release-static"
local is_hybrid = mode == "release-hybrid" or mode == "hybrid" or mode == "hybrid_dev"
if is_hybrid then
  app:get("/hybrid-inline", function(ctx) return "ok" end)
  app:get("/__bench/hybrid-inline", function(ctx) return "ok" end)
  app:get("/__bench/hybrid-inline-text-literal", function(ctx) return ctx:text("ok") end)
  app:get("/__bench/hybrid-inline-params/:id", {
    params = { id = m.u64() },
  }, function(ctx) return tostring(ctx.params.id) end)
  app:post("/__bench/hybrid-inline-echo", {
    body = { max = "8kb" },
    memory = { request_arena = "16kb" },
  }, function(ctx) return ctx:body() end)
  app:get("/__bench/lua-debug-state", function(ctx)
    local d = ctx:debug()
    return tostring(d.lua_state_id)
  end)
  app:get("/__bench/lua-global-counter", function(ctx)
    _G.__meteorite_global_counter = (_G.__meteorite_global_counter or 0) + 1
    local d = ctx:debug()
    return tostring(d.lua_state_id) .. ":" .. tostring(_G.__meteorite_global_counter)
  end)
  app:get("/__bench/lua-state-leak", function(ctx)
    local before = ctx:get("leak")
    ctx:set("leak", "set")
    return before == nil and "clean" or "leaked"
  end)
  app:get("/__bench/lua-shared-store", function(ctx)
    return tostring(ctx:shared_counter())
  end)
  app:get("/__bench/lua-worker-store", function(ctx)
    local d = ctx:debug()
    return tostring(d.lua_state_id) .. ":" .. tostring(ctx:worker_counter())
  end)
  app:get("/__bench/lua-require-cache", function(ctx)
    local probe = require("bench_lua_probe")
    local d = ctx:debug()
    return tostring(d.lua_state_id) .. ":" .. probe.hit()
  end)
else
  app:get("/hybrid-inline", "handlers.hybrid_inline")
  app:get("/__bench/hybrid-inline", "handlers.bench_hybrid_inline")
  app:get("/__bench/hybrid-inline-text-literal", "handlers.bench_hybrid_inline_text_literal")
  app:get("/__bench/hybrid-inline-params/:id", {
    params = { id = m.u64() },
  }, "handlers.hybrid_inline_params")
  app:post("/__bench/hybrid-inline-echo", {
    body = { max = "8kb" },
    memory = { request_arena = "16kb" },
  }, "handlers.hybrid_inline_echo")
  app:get("/__bench/lua-debug-state", "handlers.bench_unavailable_state")
  app:get("/__bench/lua-global-counter", "handlers.bench_unavailable_global")
  app:get("/__bench/lua-state-leak", "handlers.bench_unavailable_leak")
  app:get("/__bench/lua-shared-store", "handlers.bench_unavailable_shared")
  app:get("/__bench/lua-worker-store", "handlers.bench_unavailable_worker")
  app:get("/__bench/lua-require-cache", "handlers.bench_unavailable_require")
end

return app
