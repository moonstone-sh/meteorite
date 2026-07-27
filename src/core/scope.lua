local scope = {}

local function copy_map(value)
  local out = {}
  for key, item in pairs(value or {}) do out[key] = item end
  return out
end

local function copy_list(value)
  local out = {}
  for _, item in ipairs(value or {}) do out[#out + 1] = item end
  return out
end

local function stable_equal(left, right, seen)
  if left == right then return true end
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return false end
  seen = seen or {}
  if seen[left] == right then return true end
  seen[left] = right
  for key, value in pairs(left) do
    if not stable_equal(value, right[key], seen) then return false end
  end
  for key, _ in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function source_label(source)
  source = source or {}
  return tostring(source.file or "?") .. ":" .. tostring(source.line or 0)
end

local function scope_label(value)
  return "scope `" .. tostring(value.id or value.path_prefix or "root") .. "`"
end

local function normalize_prefix(prefix)
  assert(type(prefix) == "string" and prefix:sub(1, 1) == "/", "mount prefix must start with /")
  assert(not prefix:find("//", 1, true), "mount prefix must not contain duplicate slashes: " .. prefix)
  if prefix ~= "/" then prefix = prefix:gsub("/+$", "") end
  return prefix
end

function scope.join_path(prefix, path)
  prefix = prefix or ""
  path = path or "/"
  if prefix == "" or prefix == "/" then return path end
  if path == "/" then return prefix end
  return prefix:gsub("/+$", "") .. "/" .. path:gsub("^/+", "")
end

function scope.generated_id(prefix)
  local value = tostring(prefix or "/"):gsub("^/", ""):gsub("/$", "")
  if value == "" then return "root" end
  return value:gsub("%W", "_")
end

function scope.source_info(level)
  local info = debug.getinfo(level or 3, "Sl") or {}
  local file = info.short_src or info.source or "?"
  if file:sub(1, 1) == "@" then file = file:sub(2) end
  return { file = file, line = info.currentline or 0, column = 1 }
end

local function validate_context(value, path, seen)
  local value_type = type(value)
  if value_type == "string" or value_type == "number" or value_type == "boolean" or value == nil then return end
  if value_type ~= "table" then
    error("scope context must contain only declarative values; invalid " .. value_type .. " at " .. path)
  end
  seen = seen or {}
  if seen[value] then error("scope context must not contain cycles at " .. path) end
  seen[value] = true
  for key, item in pairs(value) do
    local key_type = type(key)
    if key_type ~= "string" and key_type ~= "number" then
      error("scope context keys must be strings or numbers at " .. path)
    end
    validate_context(item, path .. "." .. tostring(key), seen)
  end
  seen[value] = nil
end

local function merge_fact_map(family, parent, child, owner, allow_equal)
  local out = copy_map(parent)
  for key, value in pairs(child or {}) do
    if out[key] ~= nil then
      if allow_equal and stable_equal(out[key], value) then
        -- Preserve the inherited value so graph provenance remains stable.
      else
        error(table.concat({
          "conflicting inherited " .. family .. " declaration",
          "",
          "key: " .. tostring(key),
          "scope: " .. scope_label(owner),
          "declared at: " .. source_label(owner.source),
          "",
          "hint: remove the duplicate declaration or introduce an explicit override contract.",
        }, "\n"))
      end
    else
      out[key] = value
    end
  end
  return out
end

local function plugin_definition(plugin)
  return plugin.definition or plugin
end

local function merge_plugins(parent, local_plugins, owner)
  local out = copy_list(parent)
  local by_id = {}
  for _, plugin in ipairs(out) do by_id[plugin.id] = plugin end
  for _, plugin in ipairs(local_plugins or {}) do
    if type(plugin) ~= "table" or not plugin.__meteorite_plugin then
      error("scope plugins must be m.plugin(...) definitions in " .. scope_label(owner))
    end
    local existing = by_id[plugin.id]
    if existing then
      if plugin_definition(existing) ~= plugin_definition(plugin) then
        error(table.concat({
          "conflicting request plugin identity",
          "",
          "plugin id: " .. tostring(plugin.id),
          "scope: " .. scope_label(owner),
          "",
          "hint: request-plugin IDs are global within an app; reuse the same definition or choose a distinct id.",
        }, "\n"))
      end
    else
      out[#out + 1] = plugin
      by_id[plugin.id] = plugin
    end
  end
  return out
end

local function effective_facts(parent, declared, owner)
  validate_context(declared.context or {}, "context")
  return {
    params = merge_fact_map("parameter", parent.params, declared.params, owner, true),
    query = merge_fact_map("query", parent.query, declared.query, owner, true),
    capabilities = merge_fact_map("capability", parent.capabilities, declared.capabilities, owner, true),
    context = merge_fact_map("context", parent.context, declared.context, owner, false),
    plugins = merge_plugins(parent.plugins, declared.plugins, owner),
  }
end

function scope.root()
  local declared = { params = {}, query = {}, capabilities = {}, context = {}, plugins = {} }
  return {
    id = "root",
    parent = "",
    local_prefix = "",
    path_prefix = "",
    source = { file = "<app>", line = 0, column = 1 },
    declared = declared,
    params = {},
    query = {},
    capabilities = {},
    context = {},
    plugins = {},
    chain = {},
    inherited = { params = {}, query = {}, capabilities = {}, context = {}, plugins = {} },
    path_params = {},
  }
end

function scope.attach_plugin(parent_scope, plugin, options)
  local definition = plugin_definition(plugin)
  local attachment = copy_map(plugin)
  attachment.definition = definition
  attachment.options = copy_map(plugin.options)
  for key, value in pairs(options or {}) do attachment.options[key] = value end
  local declared = copy_map(parent_scope.declared or {})
  declared.plugins = copy_list(declared.plugins)
  declared.plugins[#declared.plugins + 1] = attachment
  local effective = effective_facts({
    params = parent_scope.inherited and parent_scope.inherited.params or {},
    query = parent_scope.inherited and parent_scope.inherited.query or {},
    capabilities = parent_scope.inherited and parent_scope.inherited.capabilities or {},
    context = parent_scope.inherited and parent_scope.inherited.context or {},
    plugins = parent_scope.inherited and parent_scope.inherited.plugins or {},
  }, declared, parent_scope)
  parent_scope.declared = declared
  parent_scope.plugins = effective.plugins
  return attachment
end

function scope.new_child(parent, prefix, options, source)
  options = options or {}
  prefix = normalize_prefix(prefix)
  local full_prefix = scope.join_path(parent.path_prefix, prefix)
  local declared = {
    params = copy_map(options.params),
    query = copy_map(options.query),
    capabilities = copy_map(options.capabilities),
    context = copy_map(options.context),
    plugins = copy_list(options.plugins),
  }
  local child = {
    id = options.id or scope.generated_id(full_prefix),
    parent = parent.id,
    local_prefix = prefix,
    path_prefix = full_prefix,
    source = source or scope.source_info(3),
    declared = declared,
    inherited = {
      params = parent.params,
      query = parent.query,
      capabilities = parent.capabilities,
      context = parent.context,
      plugins = parent.plugins,
    },
  }
  local effective = effective_facts(parent, declared, child)
  child.params = effective.params
  child.query = effective.query
  child.capabilities = effective.capabilities
  child.context = effective.context
  child.plugins = effective.plugins
  child.path_params = copy_map(parent.path_params)
  for name in prefix:gmatch(":([%a_][%w_]*)%*?") do
    if child.path_params[name] then
      error(table.concat({
        "conflicting mounted path parameter",
        "",
        "parameter: " .. name,
        "scope: " .. scope_label(child),
        "",
        "hint: a mount cannot redeclare a parameter name from an ancestor scope.",
      }, "\n"))
    end
    child.path_params[name] = true
  end
  child.chain = copy_list(parent.chain)
  child.chain[#child.chain + 1] = { id = child.id, parent = child.parent, path_prefix = child.path_prefix }
  return child
end

function scope.merge_route(scope_value, declaration)
  declaration.params = merge_fact_map("parameter", scope_value.params, declaration.params, scope_value, true)
  declaration.query = merge_fact_map("query", scope_value.query, declaration.query, scope_value, true)
  declaration.capabilities = merge_fact_map("capability", scope_value.capabilities, declaration.capabilities, scope_value, true)
  for _, segment in ipairs((declaration.path and declaration.path.segments) or {}) do
    if segment.kind == "param" and scope_value.path_params[segment.name] then
      error(table.concat({
        "conflicting route path parameter",
        "",
        "parameter: " .. tostring(segment.name),
        "scope: " .. scope_label(scope_value),
        "route: " .. tostring(declaration.raw_path),
        "",
        "hint: a child route cannot redeclare a parameter name from its mounted scope chain.",
      }, "\n"))
    end
  end
  return declaration
end

function scope.snapshot(value)
  return {
    id = value.id,
    parent = value.parent,
    local_prefix = value.local_prefix,
    path_prefix = value.path_prefix,
    source = value.source,
    path_params = copy_map(value.path_params),
    chain = copy_list(value.chain),
    declared = {
      params = copy_map(value.declared and value.declared.params),
      query = copy_map(value.declared and value.declared.query),
      capabilities = copy_map(value.declared and value.declared.capabilities),
      context = copy_map(value.declared and value.declared.context),
      plugins = (function()
        local out = {}
        for _, plugin in ipairs((value.declared and value.declared.plugins) or {}) do out[#out + 1] = plugin.id end
        return out
      end)(),
    },
    effective = {
      params = copy_map(value.params),
      query = copy_map(value.query),
      capabilities = copy_map(value.capabilities),
      context = copy_map(value.context),
      plugins = (function()
        local out = {}
        for _, plugin in ipairs(value.plugins or {}) do out[#out + 1] = plugin.id end
        return out
      end)(),
    },
    params = copy_map(value.params),
    query = copy_map(value.query),
    capabilities = copy_map(value.capabilities),
    context = copy_map(value.context),
    plugins = (function()
      local out = {}
      for _, plugin in ipairs(value.plugins or {}) do out[#out + 1] = plugin.id end
      return out
    end)(),
  }
end

return scope
