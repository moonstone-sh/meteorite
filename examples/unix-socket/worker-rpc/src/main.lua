local m = require("meteorite")

local app = m.app()

app:message("worker.render.thumbnail", {
  metadata = {
    image_id = m.token(),
    size = m.u64(),
  },
}, function(ctx)
  ctx:log("info", "thumbnail requested", { image_id = ctx:metadata("image_id") })
  return ctx:json({
    job = "thumbnail",
    image_id = ctx:metadata("image_id"),
    size = tonumber(ctx:metadata("size")),
    request_id = ctx:request_id(),
  })
end)

app:message("cache.invalidate", {
  metadata = { key = m.token() },
}, function(ctx)
  return ctx:text("invalidated:" .. ctx:metadata("key"))
end)

return app
