local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

app:get("/", function(c)
  return c:json({ service = "{{name}}", runtime = "lua", note = "inline Lua handler" })
end)

app:get("/zig", m.zig("zig/handlers/zig.zig"))

app:get("/health", function(c)
  return c:json({ ok = true, mode = "hybrid" })
end)

return app
