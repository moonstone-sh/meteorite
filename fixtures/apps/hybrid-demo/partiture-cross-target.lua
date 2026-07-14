local ballad = require("ballad")
local meteorite = require("meteorite.ballad")

local target = os.getenv("METEORITE_CROSS_TARGET") or "aarch64-linux-gnu"
local lua_source = os.getenv("METEORITE_LUA_SOURCE") or ""
local cmodule_source = os.getenv("METEORITE_CMODULE_SOURCE") or ""
local cmodule_rockspec = os.getenv("METEORITE_CMODULE_ROCKSPEC") or ""

local packages = nil
if cmodule_source ~= "" or cmodule_rockspec ~= "" then
  packages = {
    {
      name = "mockcmodule",
      kind = "lua_cmodule",
      source_payload_path = cmodule_source,
      rockspec_payload_path = cmodule_rockspec,
    },
  }
end

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
    packages = packages,
  })
  p.sink.directory(release, { out = "fixtures/apps/hybrid-demo/dist/release", file_graph = true })
end)
