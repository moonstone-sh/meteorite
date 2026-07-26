local ballad = require("ballad")

return ballad.partiture(function(p)
  local moonstone = p:use(ballad.plugins.moonstone)

  local examples = {
    {
      name = "basic-service",
      partiture = "partiture.lua",
      inputs = { "moonstone.toml", "partiture.lua", "src/**", "../../../src/**" },
      lua_paths = { "../../../src/ballad_plugin" },
    },
    {
      name = "ipc-native-service",
      partiture = "partiture.lua",
      inputs = { "moonstone.toml", "partiture.lua", "src/**", "../../../src/**" },
      lua_paths = { "../../../src/ballad_plugin" },
    },
  }

  for _, example in ipairs(examples) do
    local export = moonstone.orbit({
      name = example.name,
      partiture = example.partiture,
      inputs = example.inputs,
      lua_paths = example.lua_paths,
      sync = "update",
      cacheable = false,
      description = "export Meteorite example " .. example.name,
    })
    p.sink.directory(export, {
      out = "dist/examples/" .. example.name,
      file_graph = true,
    })
  end
end)
