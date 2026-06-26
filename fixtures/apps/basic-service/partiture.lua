-- TODO: check if sensible
package.path = package.path .. ";src/?.lua;src/?/init.lua"

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
		native = "native",
		output = "dist/server",
		target = "native",
	})

	p.sink.artifact(graph, { out = fixture_root .. "/.meteorite/graph/current" })
	p.sink.artifact(server, { out = fixture_root .. "/dist/server" })
end)
