local ballad = require("ballad")

return ballad.partiture(function(p)
  local meteorite = p:use("meteorite.ballad")
  local release = meteorite.release({
    input = "fixtures/static/site_basic/src/main.lua",
    output = ".meteorite/release/static-site-basic/server",
    graph_output = ".meteorite/graph/static-site-basic-release",
    mode = "static",
    backend = "std_http",
    router_dispatch = "param_matchers",
  })
  p.sink.directory(release, { out = "fixtures/static/site_basic/dist/release", file_graph = true })
end)
