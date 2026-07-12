local m = require("meteorite")

local app = m.app()
local fixture_root = "fixtures/apps/ipc-unixsocket-http-service"

app:get("/health", function(ctx)
  return ctx:text("ok")
end)

app:get("/users/:id", {
  params = { id = m.u64() },
  query = { verbose = m.bool({ optional = true }) },
}, function(ctx)
  return ctx:json({
    id = tonumber(ctx:param("id")),
    verbose = ctx:query("verbose") == "true",
  })
end)

app:post("/echo", {
  json = {
    message = m.token(),
  },
}, function(ctx)
  local body, err = ctx:json_body()
  if err then return ctx:text(400, err) end
  return ctx:json({ message = body.message })
end)

app:get("/headers", function(ctx)
  return ctx:text(200, "headers", {
    headers = {
      ["Access-Control-Allow-Origin"] = "*",
      ["X-Meteorite-Fixture"] = "ipc_unixsocket_http",
    },
  })
end)

app:get("/cookies/set", function(ctx)
  return ctx:text(200, "cookie:set", {
    headers = { ["Set-Cookie"] = ctx:set_cookie("session", "uds") },
  })
end)

app:get("/redirect", function()
  return {
    status = 302,
    content_type = "text/plain; charset=utf-8",
    body = "redirect",
    headers = { Location = "/health" },
  }
end)

app:get("/secure", function(ctx)
  return ctx:text(200, "secure", { headers = ctx:secure_headers() })
end)

app:get("/headable", function(ctx)
  return ctx:text(200, "headable", { headers = { ["X-Meteorite-Head"] = "ok" } })
end)

app:get("/static/hello.txt", m.file(fixture_root .. "/public/hello.txt", {
  content_type = "text/plain; charset=utf-8",
  cache = "public, max-age=60",
}))

return app
