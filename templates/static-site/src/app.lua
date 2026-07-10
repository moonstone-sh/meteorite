local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

m.site(app, {
  root = "site/dist",
  html = {
    ["/"] = "index.html",
    ["/docs/:route*"] = "index.html",
  },
  files = {
    ["/manifest.json"] = {
      file = "manifest.json",
      content_type = "application/json; charset=utf-8",
      cache = "public, max-age=3600",
    },
  },
  assets = {
    ["/assets/:path*"] = {
      dir = "assets",
      param = "path",
      immutable = true,
      compressed = { gzip = true },
    },
  },
})

return app
