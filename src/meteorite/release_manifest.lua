local manifest = {}

local function json_string(value)
  return "\"" .. tostring(value or ""):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. "\""
end

local function static_entries(graph)
  local entries = {}
  for _, route in ipairs(graph.routes or {}) do
    local handler = route.handler or {}
    if handler.kind == "file" then
      entries[#entries + 1] = {
        route = route.method .. " " .. route.raw_path,
        request_path = route.raw_path,
        artifact_path = handler.artifact_path,
        content_type = handler.content_type,
        content_length = handler.content_length,
        etag = handler.etag,
        cache_control = handler.cache_control,
      }
    elseif handler.kind == "dir" then
      for _, asset in ipairs(handler.manifest or {}) do
        entries[#entries + 1] = {
          route = route.method .. " " .. route.raw_path,
          request_path = asset.request_path,
          artifact_path = asset.artifact_path,
          content_type = asset.content_type,
          content_length = asset.content_length,
          etag = asset.etag,
          cache_control = asset.cache_control,
          compressed_br_path = asset.compressed_br_path,
          compressed_gzip_path = asset.compressed_gzip_path,
        }
      end
    end
  end
  table.sort(entries, function(a, b)
    return tostring(a.route) .. "\t" .. tostring(a.request_path) < tostring(b.route) .. "\t" .. tostring(b.request_path)
  end)
  return entries
end

local function static_json(graph)
  local entries = static_entries(graph)
  local lines = {
    "  \"static\": {",
    "    \"count\": " .. tostring(#entries) .. ",",
    "    \"assets\": [",
  }
  for index, entry in ipairs(entries) do
    local fields = {
      "\"route\": " .. json_string(entry.route),
      "\"request_path\": " .. json_string(entry.request_path),
      "\"artifact_path\": " .. json_string(entry.artifact_path),
      "\"content_type\": " .. json_string(entry.content_type),
      "\"content_length\": " .. tostring(entry.content_length or 0),
      "\"etag\": " .. json_string(entry.etag),
      "\"cache_control\": " .. json_string(entry.cache_control),
    }
    if entry.compressed_br_path then fields[#fields + 1] = "\"compressed_br_path\": " .. json_string(entry.compressed_br_path) end
    if entry.compressed_gzip_path then fields[#fields + 1] = "\"compressed_gzip_path\": " .. json_string(entry.compressed_gzip_path) end
    lines[#lines + 1] = "      { " .. table.concat(fields, ", ") .. " }" .. (index < #entries and "," or "")
  end
  lines[#lines + 1] = "    ]"
  lines[#lines + 1] = "  }"
  return table.concat(lines, "\n")
end

function manifest.build(result, release_mode, server_path, contract, target_lua)
  local retained = contract and contract.retained_lua_nodes or {}
  local lines = {
    "{",
    "  \"format\": \"meteorite.release.v0\",",
    "  \"mode\": " .. json_string(release_mode) .. ",",
    "  \"graph_hash\": " .. json_string(result.graph_hash) .. ",",
    "  \"routes\": " .. tostring(#(result.graph.routes or {})) .. ",",
    "  \"server\": " .. json_string(server_path) .. ",",
    "  \"contract\": {",
    "    \"format\": \"meteorite.release_contract.v0\",",
    "    \"validation_mode\": " .. json_string(contract and contract.validation_mode or release_mode) .. ",",
    "    \"graph_may_be_produced_by_lua\": true,",
    "    \"retained_lua_nodes\": " .. tostring(#retained) .. ",",
    "    \"requires_target_lua\": " .. tostring(contract and contract.requires_target_lua or false),
    "  },",
    "  \"target_lua\": {",
    "    \"status\": " .. json_string(target_lua and target_lua.status or "not_required") .. ",",
    "    \"target\": " .. json_string(target_lua and target_lua.target or "") .. ",",
    "    \"source_payload_path\": " .. json_string(target_lua and target_lua.source_payload_path or ""),
    "  },",
    static_json(result.graph),
    "}",
    "",
  }
  return table.concat(lines, "\n")
end

return manifest
