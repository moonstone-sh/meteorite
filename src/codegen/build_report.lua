--- Build and memory report generation.

local helpers = require("codegen.helpers")
local schema_doc = require("codegen.schema_doc")

local build_report = {}

function build_report.capability_names(capabilities, kind)
  local out = {}
  for name, _ in pairs((capabilities or {})[kind] or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function build_report.format_bytes(bytes)
  bytes = tonumber(bytes or 0) or 0
  if bytes >= 1024 * 1024 and bytes % (1024 * 1024) == 0 then return tostring(bytes / (1024 * 1024)) .. "mb" end
  if bytes >= 1024 and bytes % 1024 == 0 then return tostring(bytes / 1024) .. "kb" end
  return tostring(bytes) .. "b"
end

function build_report.memory_report(graph, routes_text)
  local peak_route = nil
  local peak_bytes = 0
  local max_uri_bytes, max_path_bytes, max_query_bytes = 0, 0, 0
  local max_query_pairs, max_path_segments = 0, 0
  for _, route in ipairs(graph.nodes or graph.routes or {}) do
    local memory = route.memory or {}
    if (memory.estimated_peak_bytes or 0) > peak_bytes then
      peak_route = route
      peak_bytes = memory.estimated_peak_bytes or 0
    end
    if (memory.max_uri_bytes or 0) > max_uri_bytes then max_uri_bytes = memory.max_uri_bytes or 0 end
    if (memory.max_path_bytes or 0) > max_path_bytes then max_path_bytes = memory.max_path_bytes or 0 end
    if (memory.max_query_bytes or 0) > max_query_bytes then max_query_bytes = memory.max_query_bytes or 0 end
    if (memory.max_query_pairs or 0) > max_query_pairs then max_query_pairs = memory.max_query_pairs or 0 end
    if (memory.max_path_segments or 0) > max_path_segments then max_path_segments = memory.max_path_segments or 0 end
  end
  local dfa_bytes = 0
  local dfa_states = 0
  for _, pattern in ipairs(graph.patterns or {}) do
    local report = pattern.report or {}
    dfa_bytes = dfa_bytes + (report.estimated_bytes or 0)
    dfa_states = dfa_states + (report.dfa_states or 0)
  end
  local profile = graph.profile or {}
  return {
    profile = profile.name or ((peak_route and peak_route.memory and peak_route.memory.profile_name) or "default"),
    peak_route = peak_route and (peak_route.method .. " " .. peak_route.raw_path) or "none",
    estimated_peak_bytes = peak_bytes,
    max_uri_bytes = max_uri_bytes,
    max_path_bytes = max_path_bytes,
    max_query_bytes = max_query_bytes,
    max_query_pairs = max_query_pairs,
    max_path_segments = max_path_segments,
    dfa_bytes = dfa_bytes,
    dfa_states = dfa_states,
    graph_bytes = #(routes_text or ""),
  }
end

function build_report.emit(graph, output, mode, backend)
  backend = backend or "fast_http"
  local inline, zig = 0, 0
  local validation_counts = { params = 0, query = 0, headers = 0, cookies = 0, json_body = 0, form_body = 0 }
  local missing_response_schemas = 0
  local undocumented_routes = {}
  for _, route in ipairs(graph.nodes or graph.routes) do
    if route.handler.kind == "inline_lua" then inline = inline + 1 end
    if route.handler.kind == "zig" or route.handler.kind == "zig_file" then zig = zig + 1 end
    validation_counts.params = validation_counts.params + #(route.params or {})
    validation_counts.query = validation_counts.query + #(route.query or {})
    local validation = route.validation or {}
    validation_counts.headers = validation_counts.headers + #(validation.headers or {})
    validation_counts.cookies = validation_counts.cookies + #(validation.cookies or {})
    validation_counts.json_body = validation_counts.json_body + #(validation.json_body or {})
    validation_counts.form_body = validation_counts.form_body + #(validation.form_body or {})
    if schema_doc.response_count(route.responses) == 0 then missing_response_schemas = missing_response_schemas + 1 end
    if not route.summary and not route.description and schema_doc.response_count(route.responses) == 0 then
      undocumented_routes[#undocumented_routes + 1] = route.method .. " " .. route.raw_path
    end
  end
  local memory = graph.memory_report or build_report.memory_report(graph)
  local http_capabilities = build_report.capability_names(graph.capabilities, "http")
  local auth_capabilities = build_report.capability_names(graph.capabilities, "auth")
  local zig_capabilities = build_report.capability_names(graph.capabilities, "zig")
  local lines = {
    "Meteorite build",
    "  mode: " .. (mode == "release-static" and "static" or "hybrid"),
    "  backend: " .. backend,
    "  transport: " .. ((backend == "ipc_unixsocket" or backend == "ipc_unixsocket_http") and "unix" or "tcp"),
    "  protocol: " .. (backend == "ipc_unixsocket" and "meteorite.ipc.v0" or "http/1.1"),
    "  Lua runtime: " .. (mode == "release-static" and "removed" or "included"),
    "  Lua state: single_locked",
    "  workers: auto",
    "  inline Lua handlers: " .. tostring(inline),
    "  Zig handlers: " .. tostring(zig),
    "  HTTP capabilities: " .. (#http_capabilities > 0 and table.concat(http_capabilities, ", ") or "none"),
    "  Auth capabilities: " .. (#auth_capabilities > 0 and table.concat(auth_capabilities, ", ") or "none"),
    "  Zig capabilities: " .. (#zig_capabilities > 0 and table.concat(zig_capabilities, ", ") or "none"),
    "  patterns: " .. tostring(#graph.patterns),
    "  validators: params=" .. tostring(validation_counts.params) .. " query=" .. tostring(validation_counts.query) .. " headers=" .. tostring(validation_counts.headers) .. " cookies=" .. tostring(validation_counts.cookies) .. " json=" .. tostring(validation_counts.json_body) .. " form=" .. tostring(validation_counts.form_body),
    "  response schemas: declared=" .. tostring(#graph.routes - missing_response_schemas) .. " missing=" .. tostring(missing_response_schemas),
    "  undocumented routes: " .. tostring(#undocumented_routes) .. (#undocumented_routes > 0 and (" (" .. table.concat(undocumented_routes, ", ") .. ")") or ""),
    "  memory profile: " .. tostring(memory.profile),
    "  peak route memory: " .. build_report.format_bytes(memory.estimated_peak_bytes) .. " (" .. tostring(memory.peak_route) .. ")",
    "  max URI: " .. build_report.format_bytes(memory.max_uri_bytes),
    "  max path: " .. build_report.format_bytes(memory.max_path_bytes),
    "  max query: " .. build_report.format_bytes(memory.max_query_bytes) .. " / " .. tostring(memory.max_query_pairs) .. " pairs",
    "  DFA tables: " .. build_report.format_bytes(memory.dfa_bytes) .. " / " .. tostring(memory.dfa_states) .. " states",
    "  graph data: ~" .. build_report.format_bytes(memory.graph_bytes),
    "  artifact: dist/server",
    "",
  }
  helpers.write_file(output .. "/build-report.txt", table.concat(lines, "\n"))
end

return build_report
