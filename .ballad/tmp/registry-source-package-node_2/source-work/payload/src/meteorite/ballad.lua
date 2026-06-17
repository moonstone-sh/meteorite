local graph_mod = require("ballad.graph")
local path = require("ballad.path")
local emitter = require("meteorite.emitter")

local function join(root, value)
  if not value or value == "" then return root end
  if value:sub(1, 1) == "/" then return value end
  return path.join(root, value)
end

local function with_package_path(root, fn)
  local previous_path = package.path
  package.path = table.concat({
    path.join(root, "src/?.lua"),
    path.join(root, "src/?/init.lua"),
    "src/?.lua",
    "src/?/init.lua",
    previous_path,
  }, ";")
  local ok, a, b, c = pcall(fn)
  package.path = previous_path
  if not ok then error(a) end
  return a, b, c
end

return {
  name = "meteorite.ballad",
  version = "0.1.0",
  methods = {
    graph = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
    zig = { inputs = {}, outputs = { "asset_set" }, cacheable = false, parallel_safe = false },
  },

  graph = function(ctx, inputs, opts)
    opts = opts or {}
    local root = opts.root or "."
    local input = join(root, opts.input or "src/main.lua")
    local output = join(root, opts.output or ".meteorite/graph/current")
    local chunk, err = with_package_path(root, function()
      return loadfile(input)
    end)
    if not chunk then ctx.fail(err) end
    local app = with_package_path(root, chunk)
    if type(app) ~= "table" or not app.__meteorite_app then ctx.fail(input .. " must return a Meteorite app") end
    local result = emitter.emit(app, { output = output, mode = opts.mode or "dev" })
    local assets = graph_mod.AssetSet.new()
    assets:add(ctx.graph:add_asset({ kind = "meteorite_graph", output_path = result.output, virtual_path = result.output, metadata = { graph_hash = result.graph_hash, routes = #result.graph.routes } }))
    return assets
  end,

  zig = function(ctx, inputs, opts)
    opts = opts or {}
    local root = opts.root or "."
    local tool = opts.tool or "zig"
    local output = opts.output or "dist/server"
    local output_path = join(root, output)
    local task_assets = ctx:native_task({
      tool = tool,
      args = { "build", "install-server", "--", output },
      cwd = root,
      outputs = { output_path },
      cacheable = false,
      parallel_safe = false,
      description = "Build Meteorite server",
    })
    return task_assets
  end,
}
