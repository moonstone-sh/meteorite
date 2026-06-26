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
      "scripts/**",
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
          { name = "meteorite.lua", path = "src/meteorite.lua" },
          { name = "meteorite/core/route.lua", path = "src/core/route.lua" },
          { name = "meteorite/core/schema.lua", path = "src/core/schema.lua" },
          { name = "meteorite/core/profile.lua", path = "src/core/profile.lua" },
          { name = "meteorite/core/patterns.lua", path = "src/core/patterns.lua" },
          { name = "meteorite/core/handler_factories.lua", path = "src/core/handler_factories.lua" },
          { name = "meteorite/core/site.lua", path = "src/core/site.lua" },
          { name = "meteorite/codegen/emitter.lua", path = "src/codegen/emitter.lua" },
          { name = "meteorite/codegen/lifter.lua", path = "src/codegen/lifter.lua" },
          { name = "meteorite/codegen/static.lua", path = "src/codegen/static.lua" },
          { name = "meteorite/codegen/partitions.lua", path = "src/codegen/partitions.lua" },
          { name = "meteorite/codegen/zon.lua", path = "src/codegen/zon.lua" },
          { name = "meteorite/cli/main.lua", path = "src/cli/main.lua" },
          { name = "meteorite/cli/dev.lua", path = "src/cli/dev.lua" },
          { name = "meteorite/cli/hybrid.lua", path = "src/cli/hybrid.lua" },
          { name = "meteorite/cli/http_client.lua", path = "src/cli/http_client.lua" },
          { name = "meteorite/utils/json.lua", path = "src/utils/json.lua" },
          { name = "meteorite/ballad.lua", path = "src/meteorite/ballad.lua" },
          { name = "ballad/init.lua", path = "src/ballad/init.lua" },
          { name = "ballad/release_assets.lua", path = "src/ballad/release_assets.lua" },
          { name = "ballad/release_contract.lua", path = "src/ballad/release_contract.lua" },
          { name = "ballad/release_manifest.lua", path = "src/ballad/release_manifest.lua" },
          { name = "ballad/release_tasks.lua", path = "src/ballad/release_tasks.lua" },
        },
      },
    },
  })

  p.sink.artifact(source_artifact, { out = "dist/registry/meteorite" })
end)
