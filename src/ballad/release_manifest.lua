local manifest = {}

local json = require("utils.json")
local json_encode = json.encode

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

local function runtime_source_artifact_path(target_lua)
  local source_path = target_lua and target_lua.source_payload_path or ""
  if source_path == "" then return "" end
  local name = source_path:match("([^/]+)$") or "lua-source.tar.gz"
  return "runtime/source/" .. name
end

function manifest.build(result, release_mode, server_path, contract, target_lua)
  local retained = contract and contract.retained_lua_nodes or {}
  local manifest_obj = {
    format = "meteorite.release.v0",
    mode = release_mode,
    graph_hash = result.graph_hash or "",
    routes = #(result.graph.routes or {}),
    server = server_path,
    contract = {
      format = "ballad.release_contract.v0",
      validation_mode = contract and contract.validation_mode or release_mode,
      graph_may_be_produced_by_lua = true,
      retained_lua_nodes = #retained,
      requires_target_lua = contract and contract.requires_target_lua or false,
    },
    target_lua = {
      status = target_lua and target_lua.status or "not_required",
      target = target_lua and target_lua.target or "",
      source_payload_path = runtime_source_artifact_path(target_lua),
    },
  }
  -- Add static section for static releases
  if release_mode == "static" then
    local entries = static_entries(result.graph)
    if #entries > 0 then
      local assets = {}
      for _, entry in ipairs(entries) do
        local asset = {
          route = entry.route,
          request_path = entry.request_path,
          artifact_path = entry.artifact_path,
          content_type = entry.content_type,
          content_length = entry.content_length or 0,
          etag = entry.etag,
          cache_control = entry.cache_control,
        }
        if entry.compressed_br_path then asset.compressed_br_path = entry.compressed_br_path end
        if entry.compressed_gzip_path then asset.compressed_gzip_path = entry.compressed_gzip_path end
        assets[#assets + 1] = asset
      end
      manifest_obj.static = { count = #entries, assets = assets }
    end
  end
  return json_encode(manifest_obj)
end

return manifest
