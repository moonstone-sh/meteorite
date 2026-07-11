local m = require("meteorite")

local app = m.app()

app:message("health.get", function(ctx)
  return ctx:text("ok:" .. ctx:message())
end)

app:message({
  name = "system.ping",
  handler = function(ctx)
    return ctx:text("pong:" .. ctx:message())
  end,
})

app:message("users.get", {
  metadata = {
    id = m.u64(),
  },
}, function(ctx)
  return ctx:json({
    id = tonumber(ctx:metadata("id")),
    message = ctx:message(),
    header_is_http_only = ctx:header("id") == nil,
  })
end)

app:message("users.create", {
  body = { max = "64kb" },
  json = {
    id = m.u64(),
    name = m.token(),
  },
}, function(ctx)
  local body, err = ctx:json_body()
  if err then return ctx:text(400, err) end
  return ctx:json({
    id = body.id,
    name = body.name,
    message = ctx:message(),
  })
end)

app:message("bench.stats.check", function(ctx)
  return ctx:text(ctx:request_id())
end)

return app
