local ballad = require("ballad")

return ballad.partiture(function(p)
  local moonstone = p:use(ballad.plugins.moonstone)

  local examples = {
    {
      name = "basic-service",
      partiture = "partiture.lua",
      inputs = { "moonstone.toml", "partiture.lua", "src/**", "../../../src/**" },
      lua_paths = { "../../../src/ballad_plugin" },
      products = { "graph", "server" },
    },
    {
      name = "ipc-native-service",
      partiture = "partiture.lua",
      inputs = { "moonstone.toml", "partiture.lua", "src/**", "../../../src/**" },
      lua_paths = { "../../../src/ballad_plugin" },
      products = { "release" },
    },
  }

  for _, example in ipairs(examples) do
    local export = moonstone.orbit(example.name):partiture(example.partiture):run({
      inputs = example.inputs,
      lua_paths = example.lua_paths,
      sync = "update",
      cacheable = false,
      description = "export Meteorite example " .. example.name,
    })
    for _, product in ipairs(example.products) do
      p.sink.directory(export.product(product), {
        out = "dist/examples/" .. example.name .. "/" .. product,
        file_graph = true,
      })
    end
  end
end)
