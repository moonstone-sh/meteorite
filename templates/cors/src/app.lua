local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

app:get("/health", function(ctx)
  return ctx:json({ ok = true }, { headers = ctx:cors_headers({
    origins = { "https://app.example" },
    methods = { "GET", "POST", "OPTIONS" },
    headers = { "Content-Type", "Authorization" },
    expose_headers = { "X-Request-ID" },
    credentials = true,
    max_age = 600,
  }) })
end)

app:post("/api/messages", {
  json = { message = m.string({ max_len = 280 }) },
  responses = { [200] = { json = { ok = m.bool() } } },
}, function(ctx)
  return ctx:json({ ok = true }, { headers = ctx:cors_headers({
    origins = { "https://app.example" },
    methods = { "GET", "POST", "OPTIONS" },
    headers = { "Content-Type", "Authorization" },
    expose_headers = { "X-Request-ID" },
    credentials = true,
    max_age = 600,
  }) })
end)

app:route("OPTIONS", "/api/messages", function(ctx)
  return ctx:bytes(204, "text/plain; charset=utf-8", "", { headers = ctx:cors_headers({
    origins = { "https://app.example" },
    methods = { "GET", "POST", "OPTIONS" },
    headers = { "Content-Type", "Authorization" },
    expose_headers = { "X-Request-ID" },
    credentials = true,
    max_age = 600,
  }) })
end)

return app
