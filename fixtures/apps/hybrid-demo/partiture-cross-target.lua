local ballad = require("ballad")
local moonstone = require("ballad.plugins.moonstone")
local meteorite = require("meteorite.ballad")

local target = os.getenv("METEORITE_CROSS_TARGET") or "aarch64-linux-gnu"
local cmodule_source = os.getenv("METEORITE_CMODULE_SOURCE") or ""
local cmodule_rockspec = os.getenv("METEORITE_CMODULE_ROCKSPEC") or ""
local runtime_source = os.getenv("METEORITE_LUA_SOURCE") or ""
local runtime_source_kind = os.getenv("METEORITE_LUA_SOURCE_KIND") or ""

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
  local project = moonstone.project_prepare({ root = ".", roles = { "runtime" } })
  local release = m.release({
    project = project,
    root = ".",
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    output = ".meteorite/release/server-bin",
    mode = "hybrid",
    target = target,
    bin = "bin/server",
    backend = "std_http",
    router_dispatch = "param_matchers",
    packages = packages,
    runtime_source = runtime_source,
    runtime_source_kind = runtime_source_kind,
  })
  p.sink.directory(release, { out = "dist/release", file_graph = true, product = "release" })
end)
