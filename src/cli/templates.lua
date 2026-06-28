--- Template strings for meteorite init: moonstone.toml, partiture.lua, etc.
--- Extracted from main.lua to keep init logic readable.

local templates = {}

function templates.moonstone_manifest(name, build_mode, dev_script)
  return table.concat({
    "[package]",
    'name = "' .. name .. '"',
    'version = "0.1.0"',
    'kind = "bin"',
    'description = "A new Meteorite app"',
    "",
    "[runtime]",
    'name = "lua"',
    'version = "5.4"',
    'abi = "5.4"',
    "",
    "[dependencies.tool]",
    '"moonstone/meteorite" = "^0.1.0"',
    '"moonstone/ballad" = "^0.2.0"',
    "",
    "[scripts]",
    '"generate-graph" = "meteorite graph src/main.lua .meteorite/graph/current ' .. build_mode .. '"',
    '"build" = "meteorite build --mode ' .. build_mode .. '"',
    '"dev" = "' .. dev_script .. '"',
    '"run" = "./dist/server"',
    '"release" = "moon exec ballad -- play partiture.lua"',
    "",
  }, "\n")
end

function templates.release_partiture(release_mode)
  return table.concat({
    'local ballad = require("ballad")',
    'local moonstone = require("ballad.plugins.moonstone")',
    '',
    'return ballad.partiture(function(p)',
    '  local meteorite = p:use("meteorite.ballad")',
    '  local project = moonstone.project_prepare({ root = ".", roles = { "runtime" } })',
    '  local release = meteorite.release({',
    '    project = project,',
    '    input = "src/main.lua",',
    '    graph_output = ".meteorite/graph/release",',
    '    mode = "' .. release_mode .. '",',
    '    bin = "bin/server",',
    '    backend = "std_http",',
    '  })',
    '  p.sink.directory(release, { out = "dist/release", file_graph = true })',
    'end)',
    '',
  }, "\n")
end

return templates
