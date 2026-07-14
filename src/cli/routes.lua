local routes = {}

local function schema_list(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    out[#out + 1] = {
      name = item.name,
      type = item.type or item.kind or "string",
      optional = item.optional == true,
      max_len = item.max_len,
      exact_len = item.exact_len,
      pattern_id = item.pattern_id,
    }
  end
  return out
end

local function validation_map(validation)
  validation = validation or {}
  return {
    headers = schema_list(validation.headers),
    cookies = schema_list(validation.cookies),
    json_body = schema_list(validation.json_body),
    form_body = schema_list(validation.form_body),
  }
end

local function response_keys(responses)
  local keys = {}
  for status, _ in pairs(responses or {}) do keys[#keys + 1] = tostring(status) end
  table.sort(keys)
  return keys
end

local function scope_summary(scope)
  local plugins = {}
  for _, plugin in ipairs((scope and scope.plugins) or {}) do
    if type(plugin) == "table" then
      plugins[#plugins + 1] = plugin.id or plugin.name or "plugin"
    else
      plugins[#plugins + 1] = tostring(plugin)
    end
  end
  table.sort(plugins)
  return { id = scope and scope.id or "root", plugins = plugins }
end

local function route_record(route)
  return {
    id = route.id,
    canonical_id = route.canonical_id,
    method = route.method,
    path = route.raw_path,
    http = route.http,
    message = route.message,
    handler_kind = route.handler.kind,
    params = schema_list(route.params),
    query = schema_list(route.query),
    validation = validation_map(route.validation),
    responses = response_keys(route.responses),
    runtime = route.runtime,
    scope = scope_summary(route.scope),
    source_form = route.source_form or "legacy",
    has_pipeline = route.pipeline ~= nil,
    pipeline = route.pipeline and (function()
      local stages = {}
      for _, stage in ipairs(route.pipeline) do
        stages[#stages + 1] = {
          id = stage.id,
          kind = stage.kind,
          strat = stage.strat,
          path = stage.path,
          symbol = stage.symbol,
          inline = stage.strat == "inline_lua",
          phase = stage.phase,
          owner = stage.owner,
          may_short_circuit = stage.may_short_circuit,
        }
      end
      return stages
    end)() or nil,
  }
end

local function message_record(route)
  return {
    id = route.id,
    canonical_id = route.canonical_id,
    message = route.message,
    handler_kind = route.handler.kind,
    metadata = schema_list(route.params),
    validation = validation_map(route.validation),
    runtime = route.runtime,
    scope = scope_summary(route.scope),
    source_form = route.source_form or "message",
  }
end

local function print_json(normalized)
  local json = require("utils.json")
  local route_records = {}
  for _, route in ipairs(normalized.routes) do
    route_records[#route_records + 1] = route_record(route)
  end
  local message_records = {}
  for _, route in ipairs(normalized.messages or {}) do
    message_records[#message_records + 1] = message_record(route)
  end
  print(json.encode({
    format = "meteorite.routes.v0",
    routes = route_records,
    messages = message_records,
  }))
end

local function print_human(normalized)
  for _, route in ipairs(normalized.routes) do
    local source = route.source_form or "legacy"
    local message = route.message and route.message.name or ""
    io.write(string.format("  %-6s %-30s  message=%-24s  handler=%-12s  source=%s\n",
      route.method, route.raw_path, message, route.handler.kind, source))
    if route.pipeline then
      for _, stage in ipairs(route.pipeline) do
        local detail = stage.strat
        if stage.path then detail = detail .. " " .. stage.path
        elseif stage.symbol then detail = detail .. " " .. stage.symbol
        elseif stage.strat == "inline_lua" then detail = detail .. " <inline>"
        end
        io.write(string.format("    %-10s %-8s  %s\n", stage.kind, stage.strat, detail))
      end
    end
  end
  for _, route in ipairs(normalized.messages or {}) do
    local source = route.source_form or "message"
    local message = route.message and route.message.name or ""
    io.write(string.format("  MESSAGE %-27s  handler=%-12s  source=%s\n", message, route.handler.kind, source))
  end
end

function routes.run(args)
  local show_graph = false
  local input = "src/main.lua"
  for i = 2, #args do
    local value = args[i]
    if value == "--graph" or value == "--json" then
      show_graph = true
    elseif value:sub(1, 1) ~= "-" and value ~= "routes" then
      input = value
    end
  end

  _G.METEORITE_BUILD_MODE = "dev"
  local input_dir = input:match("^(.*[/\\])") or ""
  if input_dir ~= "" then
    package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path
  end
  local chunk, err = loadfile(input)
  if not chunk then error(err) end
  local app = chunk()
  if type(app) ~= "table" or not app.__meteorite_app then
    error(input .. " must return a Meteorite app")
  end

  local route_mod = require("core.route")
  local normalized = route_mod.normalize_app(app, { mode = "dev" })
  if show_graph then
    print_json(normalized)
  else
    print_human(normalized)
  end
end

return routes
