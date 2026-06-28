local ballad = require("ballad")
local meteorite = require("meteorite.ballad")

return ballad.partiture(function(p)
	local fixture_root = "fixtures/apps/basic-service"

	local m = p:use(meteorite)
	local graph = m.graph({
		root = fixture_root,
		input = "src/main.lua",
		output = ".meteorite/graph/current",
		mode = "release-static",
	})
	local server = m.zig({
		root = fixture_root,
		graph = ".meteorite/graph/current",
		zig = "zig",
		output = "dist/server",
		target = "zig",
	})

	p.sink.artifact(graph, { out = fixture_root .. "/.meteorite/graph/current" })
	p.sink.artifact(server, { out = fixture_root .. "/dist/server" })
end)
