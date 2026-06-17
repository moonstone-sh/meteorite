local ballad = require("ballad")

return ballad.partiture(function(p)
  local moonstone = p:use(ballad.plugins.moonstone)
  local registry = p:use(ballad.plugins.registry)

  local project = moonstone.project({ root = "." })
  local source_artifact = registry.source_package(project, {
    name = project.registry_name or "moonstone/meteorite",
    version = project.version,
    kind = "bin",
    include = {
      "moonstone.toml",
      "moonstone.lock",
      "build.zig",
      "src/**",
      "native/**",
      "README.md",
    },
    exclude = {
      ".meteorite/**",
      ".moonstone/**",
      ".ballad/**",
      ".zig-cache/**",
      "zig-cache/**",
      "zig-out/**",
      "dist/**",
      ".git/**",
    },
    materialize = {
      type = "command",
      command = "zig build install-server -- dist/server",
      collect = {
        bins = {
          { name = "meteorite", path = "dist/server" },
        },
        headers = {},
        lua_modules = {
          { name = "meteorite/init.lua", path = "src/meteorite/init.lua" },
          { name = "meteorite/route.lua", path = "src/meteorite/route.lua" },
          { name = "meteorite/schema.lua", path = "src/meteorite/schema.lua" },
          { name = "meteorite/patterns.lua", path = "src/meteorite/patterns.lua" },
          { name = "meteorite/zon.lua", path = "src/meteorite/zon.lua" },
          { name = "meteorite/emitter.lua", path = "src/meteorite/emitter.lua" },
          { name = "meteorite/ballad.lua", path = "src/meteorite/ballad.lua" },
        },
      },
    },
  })

  p.sink.artifact(source_artifact, { out = "dist/registry/meteorite" })
end)
