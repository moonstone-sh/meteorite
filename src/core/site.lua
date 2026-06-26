local site = {}

local function path_join(root, leaf)
  root = tostring(root or "")
  leaf = tostring(leaf or "")
  if root == "" or root == "." then return leaf end
  if leaf == "" then return root end
  if leaf:sub(1, 1) == "/" or leaf:match("^%a:[/\\]") then return leaf end
  return root:gsub("[/\\]$", "") .. "/" .. leaf
end

local function sorted_keys(table_value)
  local keys = {}
  for key, _ in pairs(table_value or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function catch_all_prefix(path)
  local prefix = tostring(path):match("^(.-)/:[%a_][%w_]*%*$")
  if prefix == "" then return "/" end
  return prefix
end

local function routes_overlap(a, b)
  if a == b then return true end
  local ap = catch_all_prefix(a)
  local bp = catch_all_prefix(b)
  if ap and (b == ap or b:sub(1, #ap + 1) == ap .. "/") then return true end
  if bp and (a == bp or a:sub(1, #bp + 1) == bp .. "/") then return true end
  return false
end

local function assert_no_site_conflict(seen, site_seen, method, path, declared_by)
  local key = method .. " " .. path
  if seen[key] then
    error(table.concat({
      "m.site route conflict",
      "",
      "Route:",
      "  " .. key,
      "",
      "Defined by:",
      "  " .. seen[key],
      "  " .. declared_by,
      "",
      "Fix:",
      "  choose a different prefix or remove one declaration",
    }, "\n"))
  end
  for _, item in ipairs(site_seen) do
    if item.method == method and routes_overlap(item.path, path) then
      error(table.concat({
        "m.site route conflict",
        "",
        "Route:",
        "  " .. key,
        "",
        "Overlaps:",
        "  " .. item.method .. " " .. item.path,
        "",
        "Defined by:",
        "  " .. item.declared_by,
        "  " .. declared_by,
        "",
        "Fix:",
        "  choose a different prefix or remove one declaration",
      }, "\n"))
    end
  end
  seen[key] = declared_by
  site_seen[#site_seen + 1] = { method = method, path = path, declared_by = declared_by }
end

local function existing_route_keys(app)
  local seen = {}
  for _, declaration in ipairs(app.routes or {}) do
    seen[tostring(declaration.method) .. " " .. tostring(declaration.raw_path)] = "user route"
  end
  return seen
end

function site.apply(app, opts, handlers)
  assert(type(app) == "table" and app.__meteorite_app, "m.site requires a Meteorite app")
  opts = opts or {}
  local root = opts.root or "."
  local defaults = opts.defaults or {}
  local seen = existing_route_keys(app)
  local site_seen = {}

  for _, route_path in ipairs(sorted_keys(opts.files or {})) do
    local spec = opts.files[route_path]
    assert(type(spec) == "table" and type(spec.file) == "string", "m.site files[" .. tostring(route_path) .. "] requires file")
    assert_no_site_conflict(seen, site_seen, "GET", route_path, "m.site files[\"" .. tostring(route_path) .. "\"]")
    app:get(route_path, handlers.file(path_join(root, spec.file), {
      content_type = spec.content_type,
      cache = spec.cache or defaults.file_cache or "no-cache",
      only = spec.only,
      name = spec.name,
    }))
  end

  for _, route_path in ipairs(sorted_keys(opts.assets or {})) do
    local spec = opts.assets[route_path]
    assert(type(spec) == "table" and type(spec.dir) == "string", "m.site assets[" .. tostring(route_path) .. "] requires dir")
    assert_no_site_conflict(seen, site_seen, "GET", route_path, "m.site assets[\"" .. tostring(route_path) .. "\"]")
    app:get(route_path, handlers.dir(path_join(root, spec.dir), {
      param = spec.param or "path",
      cache = spec.cache or defaults.asset_cache or (spec.immutable and "public, max-age=31536000, immutable" or "no-cache"),
      immutable = spec.immutable,
      types = spec.types,
      compressed = spec.compressed,
      index = spec.index,
      name = spec.name,
    }))
  end

  for _, route_path in ipairs(sorted_keys(opts.html or {})) do
    local file = opts.html[route_path]
    local spec = type(file) == "table" and file or { file = file }
    assert(type(spec.file) == "string", "m.site html[" .. tostring(route_path) .. "] requires a file")
    assert_no_site_conflict(seen, site_seen, "GET", route_path, "m.site html[\"" .. tostring(route_path) .. "\"]")
    app:get(route_path, handlers.file(path_join(root, spec.file), {
      content_type = spec.content_type or "text/html; charset=utf-8",
      cache = spec.cache or defaults.html_cache or "no-cache",
      only = spec.only or { accept = "text/html" },
      name = spec.name,
    }))
  end

  return app
end

return site
