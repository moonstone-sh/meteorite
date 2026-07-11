local m = require("meteorite")

local app = m.app()

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

return app
