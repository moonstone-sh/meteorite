local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

app:get("/", m.zig("zig/handlers/root.zig"))
app:get("/health", m.zig("zig/handlers/health.zig"))

return app
