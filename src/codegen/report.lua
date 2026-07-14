--- Build report, memory report, and LuaLS aids generation.
--- Extracted from emitter.lua.

local schema_ir = require("codegen.schema_ir")
local openapi_plan = require("codegen.openapi_plan")
local route_zon = require("codegen.route_zon")
local build_report = require("codegen.build_report")
local luals_aids = require("codegen.luals_aids")

local report = {}

function report.schema_to_zon(item)
  return route_zon.schema_to_zon(item)
end

function report.schema_ir(graph)
  return schema_ir.emit(graph)
end

function report.openapi_plan(graph)
  return openapi_plan.emit(graph)
end

function report.route_to_zon(route)
  return route_zon.route_to_zon(route)
end

function report.capability_names(capabilities, kind)
  return build_report.capability_names(capabilities, kind)
end

function report.format_bytes(bytes)
  return build_report.format_bytes(bytes)
end

function report.memory_report(graph, routes_text)
  return build_report.memory_report(graph, routes_text)
end

function report.emit_build_report(graph, output, mode, backend)
  return build_report.emit(graph, output, mode, backend)
end

function report.emit_luals_aids(graph, output)
  return luals_aids.emit(graph, output)
end

return report
