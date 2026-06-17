local m = require("meteorite")

local app = m.app({ name = "basic-service" })

app:get("/health", "handlers.health")
app:get("/users/:id", {
  params = { id = m.u64() },
}, "handlers.get_user")

app:post("/echo", {
  memory = {
    max_body = "8kb",
    request_arena = "16kb",
  },
}, "handlers.echo")

local device_id = m.pattern("device_id", "^[a-z0-9_-]{1,64}$", {
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
    name = m.string({ max = 80, pattern = m.pattern("file_name", "^[a-z0-9_.-]{1,80}$") }),
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

return app
