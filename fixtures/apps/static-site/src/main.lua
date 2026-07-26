local m = require("meteorite")
local app = m.app({ name = "static-site-basic" })

m.site(app, {
  root = "site/dist",
  html = {
    ["/"] = "index.html",
    ["/docs/:route*"] = "index.html",
  },
  files = {
    ["/benchmarks.json"] = {
      file = "benchmarks.json",
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
