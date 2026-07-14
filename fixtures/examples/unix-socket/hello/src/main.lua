local m = require("meteorite")

local app = m.app()

app:message("health.get", function(ctx)
  return ctx:text("ok:" .. ctx:message())
end)

app:message("users.get", {
  metadata = { id = m.u64() },
}, function(ctx)
  return ctx:json({
    id = tonumber(ctx:param("id")),
    message = ctx:message(),
  })
end)

return app
