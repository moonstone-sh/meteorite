local graph = {}

local function print_result(result, mode, backend)
  print("Meteorite graph")
  print("  graph: " .. result.graph_hash)
  print("  mode: " .. mode)
  print("  backend: " .. backend)
  print("  routes: " .. tostring(#result.graph.routes))
  print("  messages: " .. tostring(#(result.graph.messages or {})))
  if result.partitions then
    print("  partitions:")
    print("    route graph: " .. result.partitions.route_graph_hash)
    print("    handlers: " .. result.partitions.handler_hash)
    print("    patterns: " .. result.partitions.pattern_hash)
    print("    lua chunks: " .. result.partitions.lua_chunk_hash)
    print("    capabilities: " .. result.partitions.capability_hash)
    print("    runtime: " .. result.partitions.runtime_hash)
  end
  if result.partition_changes then
    if #result.partition_changes == 0 then
      print("  changed partitions: none")
    else
      print("  changed partitions: " .. tostring(#result.partition_changes))
      local max_changes = 12
      for i, change in ipairs(result.partition_changes) do
        if i > max_changes then
          print("    ... " .. tostring(#result.partition_changes - max_changes) .. " more")
          break
        end
        print("    " .. change.status .. " " .. change.kind .. ":" .. change.id)
      end
    end
  end
  if result.graph.memory_report then
    local memory = result.graph.memory_report
    print("  memory profile: " .. tostring(memory.profile))
    print("  peak memory: " .. tostring(memory.estimated_peak_bytes) .. " bytes (" .. tostring(memory.peak_route) .. ")")
    print("  uri limit: " .. tostring(memory.max_uri_bytes) .. " bytes")
    print("  dfa tables: " .. tostring(memory.dfa_bytes) .. " bytes")
  end
  local capability_kinds = {}
  for kind, _ in pairs(result.graph.capabilities or {}) do capability_kinds[#capability_kinds + 1] = kind end
  table.sort(capability_kinds)
  if #capability_kinds > 0 then
    print("  capabilities: " .. table.concat(capability_kinds, ", "))
  end
end

function graph.run(args, deps)
  deps = deps or {}
  local assert_backend = assert(deps.build_request, "build_request required").assert_backend
  local input = args[2] or "src/main.lua"
  local output = args[3] or ".meteorite/graph/current"
  local mode = args[4]
  local backend = args[5] and assert_backend(args[5]) or nil
  if not mode or not backend then
    error("meteorite graph requires explicit <mode> <backend>; use a Moonstone script or pass both values")
  end
  local app = require("cli.app_loader").load(input, mode)
  local result = require("codegen.emitter").emit(app, { output = output, mode = mode, backend = backend })
  print_result(result, mode, backend)
  return result
end

return graph
