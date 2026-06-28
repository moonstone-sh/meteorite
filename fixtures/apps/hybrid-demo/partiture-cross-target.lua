local ballad = require("ballad")
local meteorite = require("meteorite.ballad")

local target = os.getenv("METEORITE_CROSS_TARGET") or "aarch64-linux-gnu"
local lua_source = os.getenv("METEORITE_LUA_SOURCE") or ""

return ballad.partiture(function(p)
  local m = p:use(meteorite)
  local release = m.release({
    root = "fixtures/apps/hybrid-demo",
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    output = ".meteorite/release/server-bin",
    mode = "hybrid",
    target = target,
    bin = "bin/server",
    backend = "std_http",
    router_dispatch = "param_matchers",
    runtime = {
      source_payload_path = lua_source,
      source_kind = "puc_lua_source",
    },
  })
  p.sink.directory(release, { out = "fixtures/apps/hybrid-demo/dist/release", file_graph = true })
end)
