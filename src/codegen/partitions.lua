local partitions = {}

function partitions.rows(snapshot)
  local rows = {}
  local function add(kind, id, hash)
    rows[#rows + 1] = { key = kind .. "\t" .. id, kind = kind, id = id, hash = hash }
  end
  add("route_graph", "all", snapshot.route_graph_hash)
  add("handlers", "all", snapshot.handler_hash)
  add("patterns", "all", snapshot.pattern_hash)
  add("lua_chunks", "all", snapshot.lua_chunk_hash)
  add("plugins", "all", snapshot.plugin_hash)
  add("capabilities", "all", snapshot.capability_hash)
  add("runtime", "all", snapshot.runtime_hash)
  for _, route in ipairs(snapshot.routes or {}) do add("route", route.id, route.hash) end
  for _, handler in ipairs(snapshot.handlers or {}) do add("handler", handler.id, handler.hash) end
  for _, chunk in ipairs(snapshot.lua_chunks or {}) do add("lua_chunk", chunk.id, chunk.hash) end
  for _, asset in ipairs(snapshot.static_assets or {}) do add("static_asset", asset.id, asset.hash) end
  for _, plugin in ipairs(snapshot.plugins or {}) do add("plugin", plugin.id, plugin.hash) end
  for _, pattern in ipairs(snapshot.patterns or {}) do add("pattern", pattern.id, pattern.hash) end
  table.sort(rows, function(a, b) return a.key < b.key end)
  return rows
end

function partitions.encode_tsv(snapshot)
  local lines = { "kind\tid\thash" }
  for _, row in ipairs(partitions.rows(snapshot)) do
    lines[#lines + 1] = row.kind .. "\t" .. row.id .. "\t" .. row.hash
  end
  return table.concat(lines, "\n") .. "\n"
end

function partitions.parse_tsv(text)
  local rows = {}
  if not text then return rows end
  for line in text:gmatch("[^\n]+") do
    if line ~= "kind\tid\thash" then
      local kind, id, hash = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
      if kind and id and hash then rows[kind .. "\t" .. id] = { kind = kind, id = id, hash = hash } end
    end
  end
  return rows
end

function partitions.diagnostics(previous_text, snapshot)
  local previous = partitions.parse_tsv(previous_text)
  local rows = partitions.rows(snapshot)
  local changed = {}
  local current = {}
  for _, row in ipairs(rows) do
    current[row.key] = true
    local old = previous[row.key]
    if not old then
      changed[#changed + 1] = { status = "added", kind = row.kind, id = row.id, hash = row.hash }
    elseif old.hash ~= row.hash then
      changed[#changed + 1] = { status = "changed", kind = row.kind, id = row.id, old_hash = old.hash, hash = row.hash }
    end
  end
  for key, row in pairs(previous) do
    if not current[key] then changed[#changed + 1] = { status = "removed", kind = row.kind, id = row.id, old_hash = row.hash } end
  end
  table.sort(changed, function(a, b)
    local ak = a.kind .. "\t" .. a.id .. "\t" .. a.status
    local bk = b.kind .. "\t" .. b.id .. "\t" .. b.status
    return ak < bk
  end)
  return changed
end

return partitions
