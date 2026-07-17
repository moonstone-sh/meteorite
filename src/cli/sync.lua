local sync = {}

function sync.run(args, deps)
  local graph = require("cli.graph")
  local handler_sync = require("codegen.handler_sync")
  local input = args[2] or "src/main.lua"
  local output = args[3] or ".meteorite/graph/current"
  local mode = args[4] or "dev"
  local backend = args[5] or "fast_http"
  local result = graph.run({ "graph", input, output, mode, backend }, deps)
  handler_sync.sync_handler_files(result.graph, output, mode)
  handler_sync.sync_luarc(output)
  print("Meteorite sync: updated opted-in host aids and handler stubs")
  return result
end

return sync
