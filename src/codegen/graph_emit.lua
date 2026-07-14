--- Compatibility facade for graph emission modules.
---
--- @class GraphEmitModule
--- @field prepare_graph fun(graph: table, output: string, mode: string): table  Prepare and clean graph data
--- @field emit_bindings fun(graph: table, output: string): void  Emit graph_bindings.zig
--- @field emit_pattern_modules fun(graph: table, output: string): void  Emit pattern/*.zig modules
--- @field emit_route_modules fun(graph: table, output: string): void  Emit routes/*.zig modules
--- @field emit_graph_zig fun(graph: table, output: string): void  Emit main graph.zig

---@type GraphEmitModule
local graph_prepare = require("codegen.graph_prepare")
local graph_patterns = require("codegen.graph_patterns")
local graph_capabilities = require("codegen.graph_capabilities")
local graph_bindings = require("codegen.graph_bindings")
local graph_routes = require("codegen.graph_routes")
local graph_zig = require("codegen.graph_zig")

local graph_emit = {}

function graph_emit.scan_capabilities(source)
  return graph_prepare.scan_capabilities(source)
end

function graph_emit.validate_capability_refs(graph, route, refs)
  return graph_prepare.validate_capability_refs(graph, route, refs)
end

function graph_emit.prepare_graph(graph, output, mode)
  return graph_prepare.prepare_graph(graph, output, mode)
end

function graph_emit.sorted_handler_infos(routes)
  return graph_bindings.sorted_handler_infos(routes)
end

function graph_emit.sorted_route_handler_infos(routes)
  return graph_bindings.sorted_route_handler_infos(routes)
end

function graph_emit.relative_path(from_dir, to_path)
  return graph_bindings.relative_path(from_dir, to_path)
end

function graph_emit.emit_bindings(graph, output)
  return graph_bindings.emit(graph, output)
end

function graph_emit.pattern_class_map(pattern)
  return graph_patterns.pattern_class_map(pattern)
end

function graph_emit.pattern_module_name(pattern)
  return graph_patterns.pattern_module_name(pattern)
end

function graph_emit.pattern_module_content(pattern)
  return graph_patterns.pattern_module_content(pattern)
end

function graph_emit.emit_pattern_modules(graph, output)
  return graph_patterns.emit_pattern_modules(graph, output)
end

function graph_emit.emit_pattern_tables(graph, lines, output)
  return graph_patterns.emit_pattern_tables(graph, lines, output)
end

function graph_emit.is_array_table(value)
  return graph_capabilities.is_array_table(value)
end

function graph_emit.capability_value_to_zig(value, indent)
  return graph_capabilities.value_to_zig(value, indent)
end

function graph_emit.emit_capabilities(graph, lines)
  return graph_capabilities.emit(graph, lines)
end

function graph_emit.route_module_name(route)
  return graph_routes.route_module_name(route)
end

function graph_emit.param_pattern_zig(param)
  return graph_routes.param_pattern_zig(param)
end

function graph_emit.route_handler_zig(route)
  return graph_routes.route_handler_zig(route)
end

function graph_emit.route_runtime_zig(route)
  return graph_routes.route_runtime_zig(route)
end

function graph_emit.route_execution_zig(route)
  return graph_routes.route_execution_zig(route)
end

function graph_emit.route_memory_zig(route)
  return graph_routes.route_memory_zig(route)
end

function graph_emit.route_scope_zig(scope)
  return graph_routes.route_scope_zig(scope)
end

function graph_emit.plugin_handler_zig(plugin)
  return graph_routes.plugin_handler_zig(plugin)
end

function graph_emit.static_asset_zig(asset)
  return graph_routes.static_asset_zig(asset)
end

function graph_emit.route_module_content(route)
  return graph_routes.route_module_content(route)
end

function graph_emit.emit_route_modules(graph, output)
  return graph_routes.emit_route_modules(graph, output)
end

function graph_emit.emit_graph_zig(graph, output)
  return graph_zig.emit(graph, output)
end

return graph_emit
