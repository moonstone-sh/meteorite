local ballad = require("ballad")
local meteorite = require("meteorite.ballad")

return ballad.partiture(function(p)
	local fixture_root = "."

	local m = p:use(meteorite)
	local graph = m.graph({
		root = fixture_root,
		input = "src/main.lua",
		output = ".meteorite/graph/current",
		mode = "release-static",
		backend = "std_http",
	})
	local server = m.zig({
		root = fixture_root,
		graph = ".meteorite/graph/current",
		zig = "zig",
		output = "dist/server",
		target = "zig",
		mode = "release-static",
		backend = "std_http",
	})

	p.sink.artifact(graph, { out = fixture_root .. "/.meteorite/graph/current", product = "graph" })
	p.sink.artifact(server, { out = fixture_root .. "/dist/server", product = "server" })
end)
