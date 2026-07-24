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
  data_cruncher = "zig/helpers/data_cruncher.zig",
})

app:get("/health", {
  summary = "Report service health",
}, "handlers.health")
app:get("/users/:id", {
  summary = "Fetch one user",
  params = { id = m.u64() },
}, "handlers.get_user")

app:put("/users/:id", {
  summary = "Replace one user",
  params = { id = m.u64() },
}, "handlers.put_user")

app:patch("/users/:id", {
  summary = "Update one user",
  params = { id = m.u64() },
}, "handlers.patch_user")

app:delete("/users/:id", {
  summary = "Delete one user",
  params = { id = m.u64() },
}, "handlers.delete_user")

app:post("/echo", {
  summary = "Echo a request body",
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
  summary = "Fetch a device",
  params = {
    device_id = m.string({ max = 64, pattern = device_id }),
  },
}, "handlers.get_device")

app:get("/files/:name", {
  summary = "Fetch a named file",
  params = {
    name = m.string({ max = 80, pattern = m.pattern("^[a-z0-9_.-]{1,80}$") }),
  },
}, "handlers.file")

app:get("/slugs/:slug", {
  summary = "Fetch a slug resource",
  params = { slug = m.slug({ max = 64 }) },
}, "handlers.slug")

app:get("/uuids/:id", {
  summary = "Fetch a UUID resource",
  params = { id = m.uuid() },
}, "handlers.uuid")

app:get("/hex/:digest", {
  summary = "Fetch a hexadecimal digest",
  params = { digest = m.hex({ len = 32 }) },
}, "handlers.hex")

app:get("/search", {
  summary = "Search service records",
  query = {
    q = m.string({ max = 80 }),
    page = m.u64({ optional = true }),
    exact = m.bool({ optional = true }),
  },
}, "handlers.search")

return app
