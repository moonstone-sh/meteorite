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

local function retained_lua_nodes(contract)
  local out = {}
  for _, ref in ipairs((contract and contract.retained_lua_nodes) or {}) do
    out[#out + 1] = {
      kind = ref.kind,
      label = ref.label,
      source = ref.source,
      hint = ref.hint,
    }
  end
  return out
end

local function target_abi(opts, target_lua)
  local runtime = (opts and opts.runtime) or {}
  return (target_lua and target_lua.target) or (opts and opts.target) or runtime.target or runtime.abi_target or "native"
end

function manifest.build(result, release_mode, server_path, contract, target_lua, opts)
  local retained = contract and contract.retained_lua_nodes or {}
  local retained_nodes = retained_lua_nodes(contract)
  local static = static_entries(result.graph)
  local runtime_source_path = runtime_source_artifact_path(target_lua)
  local abi = target_abi(opts, target_lua)
  local manifest_obj = {
    format = "meteorite.release.v0",
    mode = release_mode,
    graph_hash = result.graph_hash or "",
    route_count = #(result.graph.routes or {}),
    routes = #(result.graph.routes or {}),
    server = server_path,
    target = {
      abi = abi,
    },
    contract = {
      format = "ballad.release_contract.v0",
      validation_mode = contract and contract.validation_mode or release_mode,
      graph_may_be_produced_by_lua = true,
      retained_lua_nodes = #retained,
      retained_lua_node_details = retained_nodes,
      requires_target_lua = contract and contract.requires_target_lua or false,
    },
    retained_lua_nodes = {
      count = #retained,
      nodes = retained_nodes,
    },
    static = {
      count = #static,
      assets = {},
    },
    runtime_source = {
      status = runtime_source_path ~= "" and "packaged" or "not_required",
      artifact_path = runtime_source_path,
      source_kind = target_lua and target_lua.source_kind or "",
    },
    target_lua = {
      status = target_lua and target_lua.status or "not_required",
      target = abi,
      source_payload_path = runtime_source_path,
      source_kind = target_lua and target_lua.source_kind or "",
    },
  }
  for _, entry in ipairs(static) do
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
    manifest_obj.static.assets[#manifest_obj.static.assets + 1] = asset
  end
  if release_mode == "static" then
    manifest_obj.static.lua_runtime_execution_nodes = #retained
    manifest_obj.static.guarantee = #retained == 0 and "no_lua_runtime_execution_nodes" or "violated"
  end
  if runtime_source_path == "" and release_mode == "hybrid" and target_lua and target_lua.status == "host_env" then
    manifest_obj.runtime_source.status = "host_env"
  end
  return json_encode(manifest_obj)
end

return manifest
