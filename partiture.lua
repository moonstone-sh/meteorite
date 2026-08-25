local ballad = require("ballad")

return ballad.partiture(function(p)
	local moonstone = p:use(ballad.plugins.moonstone)
	local convention = ballad.conventions
	local project = moonstone.project({ root = "." })

	local source_artifact = moonstone.registry.source_package(project, {
		name = project.registry_name or "moonstone/meteorite",
		kind = "bin",
		include = {
			"Watch_partiture.lua",
			"partiture_common.lua",
			"build.zig",
			"bin/**",
			"src/**",
			"zig/**",
			"scripts/**",
			"templates/**",
			"docs/**",
			"README.md",
			"REGISTRY_README.md",
		},
		exclude = {
			"fixtures/**",
			"**/.moonstone",
			"**/.moonstone/**",
			"**/.meteorite",
			"**/.meteorite/**",
			"**/.ballad",
			"**/.ballad/**",
		},
		collect = {
			bins = {
				convention.file("bin/meteorite", "bin/meteorite"),
			},
			lua_modules = {
				convention.tree("src", {
					prefix = "meteorite",
					strip_prefix = "meteorite/",
					root_module = "meteorite.lua",
					overrides = {
						["ballad_plugin/meteorite/ballad.lua"] = "meteorite/ballad.lua",
					},
				}),
				convention.tree("zig", { prefix = "meteorite/zig" }),
				convention.tree("scripts", {
					prefix = "meteorite/scripts",
					include = { "guard.sh" },
				}),
				convention.tree("templates", {
					prefix = "meteorite/templates",
					include = { "project/**", "static/**", "hybrid/**" },
				}),
				convention.tree("docs", {
					prefix = "meteorite/docs",
					include = { "examples.md" },
				}),
				convention.file("meteorite/build.zig", "build.zig"),
			},
		},
	})

	p.sink.artifact(source_artifact, {
		out = "dist/registry/meteorite",
	})
end)
