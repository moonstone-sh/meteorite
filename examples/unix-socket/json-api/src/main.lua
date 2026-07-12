local m = require("meteorite")

local app = m.app()

app:message("users.create", {
  body = { max = "64kb" },
  json = {
    id = m.u64(),
    name = m.token(),
  },
}, function(ctx)
  local body, err = ctx:json_body()
  if err then return ctx:text(400, err) end
  return ctx:json({ id = body.id, name = body.name, created = true })
end)

return app
