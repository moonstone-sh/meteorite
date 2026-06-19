local m = require("meteorite")

local app = m.app({ name = "basic-service" })

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
end

return app
