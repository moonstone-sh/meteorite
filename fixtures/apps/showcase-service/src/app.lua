local m = require("meteorite")

local app = m.app({ name = "showcase-service", host = "127.0.0.1", port = 8080 })

app:capability("http", {
  db = {
    base_url = "http://localhost:8888",
    timeout_ms = 1500,
    max_response_bytes = 65536,
  },
})

app:capability("zig", {
  data_cruncher = "zig/helpers/data_cruncher.zig",
})

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
  body = { max = "8kb" },
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

local mode = _G.METEORITE_BUILD_MODE or "release-static"
local is_hybrid = mode == "release-hybrid" or mode == "hybrid" or mode == "hybrid_dev"
if is_hybrid then
  app:get("/hybrid-inline", function(ctx) return "ok" end)
else
  app:get("/hybrid-inline", "handlers.hybrid_inline")
end

return app
