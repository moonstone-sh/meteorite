local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

app:get("/health", function(ctx)
  return ctx:json({ ok = true })
end)

app:get("/api/todos/:id", {
  params = { id = m.u64() },
  query = { verbose = m.bool({ optional = true }) },
  responses = { [200] = { json = { ok = m.bool() } } },
}, function(ctx)
  if ctx.params.id ~= "1" then return ctx:json(404, { error = "not_found" }) end
  local todo = { id = "1", title = "ship Meteorite", done = false }
  return ctx:json({ ok = true, todo = todo, verbose = ctx.query.verbose == true })
end)

app:post("/api/todos", {
  json = {
    title = m.string({ max_len = 120 }),
    done = m.bool({ optional = true }),
  },
  responses = { [201] = { json = { ok = m.bool() } } },
}, function(ctx)
  local body = ctx:json_body()
  return ctx:json(201, { ok = true, todo = { id = "2", title = body.title, done = body.done == true } })
end)

return app
