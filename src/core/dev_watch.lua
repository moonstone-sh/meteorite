local dev_watch = {}

dev_watch.default_graph = {
  "src", "zig", "public", "static", "site", "assets", "build.zig", "moonstone.toml",
}

local function validate_path(path)
  assert(type(path) == "string" and path ~= "", "dev_watch paths must be non-empty strings")
  assert(path:sub(1, 1) ~= "/" and not path:match("^%a:[/\\]"), "dev_watch paths must be project-relative: " .. path)
  assert(not path:find("[\r\n%z]") and not path:find("\\", 1, true), "invalid dev_watch path: " .. path)
  assert(not path:match("^%.%./") and path ~= ".." and not path:match("/%.%./") and not path:match("/%.%.$"), "dev_watch path escapes project: " .. path)
  assert(not path:find("*", 1, true) and not path:find("?", 1, true), "dev_watch paths are literal files or directories: " .. path)
  assert(path:sub(1, 1) ~= "-", "dev_watch paths cannot start with '-': " .. path)
  return path
end

local function normalize_list(paths, label)
  assert(type(paths) == "table", "dev_watch." .. label .. " must be a list")
  local result, seen = {}, {}
  for index, path in ipairs(paths) do
    validate_path(path)
    if not seen[path] then result[#result + 1], seen[path] = path, true end
    assert(index <= 256, "too many dev_watch." .. label .. " paths")
  end
  table.sort(result)
  return result
end

function dev_watch.normalize(value)
  if value == nil then value = { graph = dev_watch.default_graph } end
  assert(type(value) == "table", "dev_watch must be a table")
  assert(value.graph ~= nil, "dev_watch.graph is required")
  local graph = normalize_list(value.graph, "graph")
  local runtime = normalize_list(value.runtime or {}, "runtime")
  assert(#graph > 0, "dev_watch.graph cannot be empty")
  return { graph = graph, runtime = runtime }
end

function dev_watch.encode(value)
  local lines = { "meteorite.dev_watch.v1", tostring(#value.graph), tostring(#value.runtime) }
  for _, path in ipairs(value.graph) do lines[#lines + 1] = path end
  for _, path in ipairs(value.runtime) do lines[#lines + 1] = path end
  return table.concat(lines, "\n") .. "\n"
end

function dev_watch.decode(content)
  if not content then return dev_watch.normalize(nil) end
  local lines = {}
  for line in content:gmatch("[^\n]+") do lines[#lines + 1] = line end
  local graph_count, runtime_count = tonumber(lines[2]), tonumber(lines[3])
  assert(lines[1] == "meteorite.dev_watch.v1" and graph_count and runtime_count
    and graph_count >= 1 and graph_count <= 256 and graph_count % 1 == 0
    and runtime_count >= 0 and runtime_count <= 256 and runtime_count % 1 == 0
    and #lines == 3 + graph_count + runtime_count,
    "invalid dev-watch.paths header or counts")
  local value = { graph = {}, runtime = {} }
  for i = 1, graph_count do value.graph[#value.graph + 1] = lines[3 + i] end
  for i = 1, runtime_count do
    value.runtime[#value.runtime + 1] = lines[3 + graph_count + i]
  end
  return dev_watch.normalize(value)
end

return dev_watch
