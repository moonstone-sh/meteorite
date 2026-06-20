local m = require("meteorite")

local app = m.app({ name = "demo" })

app:capability("http", {
  db = {
    base_url = "http://localhost:8888",
    timeout_ms = 1500,
    max_response_bytes = 65536,
  },
})

app:capability("auth", {
  db = {
    token_url = "http://localhost:8888/token",
    audience = "db",
    refresh_before_seconds = 30,
  },
})

app:capability("zig", {
  data_cruncher = "native/src/helpers/data_cruncher.zig",
})

app:get("/", function(c)
  return c:text("hello from meteorite")
end)

app:get("/health", function(c)
  return c:json({
    ok = true,
    runtime = "lua",
  })
end)

app:get("/users/:id", {
  params = {
    id = m.u64(),
  },
}, function(c)
  local user = c:http("db"):post("/get-user-from-db", {
    headers = c:auth("db"):headers(),
    body = {
      id = c.params.id,
    },
  })

  return c:json({
    id = c.params.id,
    user = user.body,
    message = "typed params from native graph",
  })
end)

app:post("/echo", {
  body = {
    max = 8192,
  },
}, function(c)
  return c:text(c:body())
end)

app:get("/devices/:device_id", {
  params = {
    device_id = m.string({ max = 64 }),
  },
}, function(c)
  local cruncher = c:zig("data_cruncher")

  return c:json({
    device = cruncher.device_name(c.params.device_id),
  })
end)

return app
