--- Plugin contract and graph mutation API.
--- Makes plugins graph authors, not invisible middleware.
---
--- A plugin may:
--- - inspect the whole graph
--- - validate policies
--- - inject hooks
--- - inject pipeline stages
--- - generate code
--- - add macro routes
--- - emit diagnostics
---
--- @class PluginContractModule
--- @field define fun(spec: table): PluginDefinition  Create a plugin definition
--- @field create_graph_api fun(graph: table, plugin_id: string): GraphAPI  Create a graph mutation API for a plugin

local plugin_contract = {}

--- @class PluginDefinition
--- @field id string  Unique plugin identifier (e.g. "meteorite.cache")
--- @field version? string  Plugin version
--- @field consumes_policy? string[]  Policy keys this plugin owns (e.g. {"cache"})
--- @field phases? string[]  Hook phases this plugin may inject into
--- @field graph_passes? string[]  Graph passes (validate, transform, codegen, profile)
--- @field capabilities? string[]  Required capabilities
--- @field validate? fun(graph: table, diag: DiagnosticEmitter): void  Validation pass
--- @field transform? fun(graph: table, api: GraphAPI): void  Transformation pass
--- @field codegen? fun(graph: table, api: GraphAPI): void  Code generation pass

--- @class GraphAPI
--- @field add_route fun(route: RouteContract): void  Add a macro route
--- @field add_hook fun(phase: string, hook: HookContract): void  Add a global hook
--- @field prepend_stage fun(route_id: string, stage: StageContract): void  Prepend stage to route pipeline
--- @field append_stage fun(route_id: string, stage: StageContract): void  Append stage to route pipeline
--- @field insert_stage_before fun(route_id: string, target_id: string, stage: StageContract): void  Insert before target
--- @field insert_stage_after fun(route_id: string, target_id: string, stage: StageContract): void  Insert after target
--- @field add_diagnostic fun(severity: string, message: string, context?: table): void  Emit diagnostic
--- @field add_codegen_unit fun(name: string, content: string): void  Add codegen output
--- @field add_profile_counter fun(name: string, description: string): void  Add profile counter
--- @field get_route fun(route_id: string): table|nil  Get route by id
--- @field get_routes fun(): table[]  Get all routes
--- @field get_policy fun(route_id: string, key: string): table|nil  Get route policy by key

--- @class DiagnosticEmitter
--- @field emit fun(severity: string, message: string, context?: table): void

--- Valid graph passes
plugin_contract.valid_passes = {
  validate = true,
  transform = true,
  codegen = true,
  profile = true,
}

--- Create a plugin definition.
---@param spec table  Plugin specification
---@return PluginDefinition
--- Create a plugin definition.
---@param spec table  Plugin specification
---@return PluginDefinition
function plugin_contract.define(spec)
  spec = spec or {}
  assert(type(spec.id) == "string" and spec.id ~= "", "plugin requires an 'id' field (e.g. \"meteorite.cache\")")

  local plugin = {
    id = spec.id,
    version = spec.version or "0.1.0",
    consumes_policy = spec.consumes_policy or {},
    phases = spec.phases or {},
    graph_passes = spec.graph_passes or {},
    capabilities = spec.capabilities or {},
    validate = spec.validate,
    transform = spec.transform,
    codegen = spec.codegen,
    __meteorite_graph_plugin = true,
  }

  -- Validate graph passes
  for _, pass in ipairs(plugin.graph_passes) do
    if not plugin_contract.valid_passes[pass] then
      error("invalid graph pass: " .. tostring(pass) .. " for plugin " .. plugin.id ..
        " (expected: validate, transform, codegen, profile)")
    end
  end

  return plugin
end

--- Create a graph mutation API for a plugin.
---@param graph table  The normalized route graph
---@param plugin_id string  The plugin id (for ownership tracking)
---@return GraphAPI
--- Create a graph mutation API for a plugin.
---@param graph table  The normalized route graph
---@param plugin_id string  The plugin id (for ownership tracking)
---@return GraphAPI
function plugin_contract.create_graph_api(graph, plugin_id)
  local diagnostics = {}
  local codegen_units = {}
  local profile_counters = {}

  local function find_route(route_id)
    for _, route in ipairs(graph.routes or {}) do
      if route.id == route_id then return route end
    end
    return nil
  end

  local function ensure_pipeline(route)
    if not route.pipeline then route.pipeline = {} end
    return route.pipeline
  end

  local api = {}

  --- Add a macro route.
  function api:add_route(route_contract)
    route_contract._owner_plugin = plugin_id
    graph.routes = graph.routes or {}
    graph.routes[#graph.routes + 1] = route_contract
  end

  --- Add a global hook.
  function api:add_hook(phase, hook)
    hook.owner_plugin = plugin_id
    graph.hooks = graph.hooks or {}
    graph.hooks[#graph.hooks + 1] = { phase = phase, owner_plugin = plugin_id, stage = hook }
  end

  --- Prepend a stage to a route's pipeline.
  function api:prepend_stage(route_id, stage)
    local route = find_route(route_id)
    if not route then
      error("plugin " .. plugin_id .. " cannot prepend stage: route not found: " .. route_id)
    end
    stage.owner = plugin_id
    local pipeline = ensure_pipeline(route)
    table.insert(pipeline, 1, stage)
  end

  --- Append a stage to a route's pipeline.
  function api:append_stage(route_id, stage)
    local route = find_route(route_id)
    if not route then
      error("plugin " .. plugin_id .. " cannot append stage: route not found: " .. route_id)
    end
    stage.owner = plugin_id
    local pipeline = ensure_pipeline(route)
    pipeline[#pipeline + 1] = stage
  end

  --- Insert a stage before a target stage.
  function api:insert_stage_before(route_id, target_id, stage)
    local route = find_route(route_id)
    if not route then
      error("plugin " .. plugin_id .. " cannot insert stage: route not found: " .. route_id)
    end
    stage.owner = plugin_id
    local pipeline = ensure_pipeline(route)
    for i, s in ipairs(pipeline) do
      if s.id == target_id then
        table.insert(pipeline, i, stage)
        return
      end
    end
    error("plugin " .. plugin_id .. " cannot insert before: stage not found: " .. target_id)
  end

  --- Insert a stage after a target stage.
  function api:insert_stage_after(route_id, target_id, stage)
    local route = find_route(route_id)
    if not route then
      error("plugin " .. plugin_id .. " cannot insert stage: route not found: " .. route_id)
    end
    stage.owner = plugin_id
    local pipeline = ensure_pipeline(route)
    for i, s in ipairs(pipeline) do
      if s.id == target_id then
        table.insert(pipeline, i + 1, stage)
        return
      end
    end
    error("plugin " .. plugin_id .. " cannot insert after: stage not found: " .. target_id)
  end

  --- Emit a diagnostic.
  function api:add_diagnostic(severity, message, context)
    diagnostics[#diagnostics + 1] = {
      severity = severity,
      message = message,
      plugin = plugin_id,
      context = context,
    }
  end

  --- Add a codegen unit.
  function api:add_codegen_unit(name, content)
    codegen_units[#codegen_units + 1] = { name = name, content = content, owner = plugin_id }
  end

  --- Add a profile counter.
  function api:add_profile_counter(name, description)
    profile_counters[#profile_counters + 1] = { name = name, description = description, owner = plugin_id }
  end

  --- Get a route by id.
  function api:get_route(route_id)
    return find_route(route_id)
  end

  --- Get all routes.
  function api:get_routes()
    return graph.routes or {}
  end

  --- Get a route policy by key.
  function api:get_policy(route_id, key)
    local route = find_route(route_id)
    if not route or not route.policy then return nil end
    return route.policy[key]
  end

  -- Expose collected data
  api._diagnostics = diagnostics
  api._codegen_units = codegen_units
  api._profile_counters = profile_counters
  api._plugin_id = plugin_id

  return api
end

--- Run all registered graph plugins against the graph.
---@param graph table  Normalized route graph
---@param plugins PluginDefinition[]  Registered plugins
---@return table  Collected diagnostics, codegen units, profile counters
--- Run all registered graph plugins against the graph.
---@param graph table  Normalized route graph
---@param plugins PluginDefinition[]  Registered plugins
---@return table  Collected diagnostics, codegen units, profile counters
function plugin_contract.run_passes(graph, plugins)
  local all_diagnostics = {}
  local all_codegen_units = {}
  local all_profile_counters = {}

  -- Check policy ownership conflicts
  local policy_owners = {}
  for _, plugin in ipairs(plugins) do
    for _, policy_key in ipairs(plugin.consumes_policy or {}) do
      if policy_owners[policy_key] then
        all_diagnostics[#all_diagnostics + 1] = {
          severity = "error",
          message = "policy ownership conflict: '" .. policy_key .. "' is consumed by both '" ..
            policy_owners[policy_key] .. "' and '" .. plugin.id .. "'",
          plugin = plugin.id,
        }
      else
        policy_owners[policy_key] = plugin.id
      end
    end
  end

  -- Run passes in order: validate -> transform -> codegen -> profile
  for _, pass in ipairs({ "validate", "transform", "codegen", "profile" }) do
    for _, plugin in ipairs(plugins) do
      local fn = plugin[pass]
      if type(fn) == "function" then
        local diag_emitter = {
          emit = function(severity, message, context)
            all_diagnostics[#all_diagnostics + 1] = {
              severity = severity,
              message = message,
              plugin = plugin.id,
              context = context,
            }
          end,
        }
        local api = plugin_contract.create_graph_api(graph, plugin.id)

        if pass == "validate" then
          fn(graph, diag_emitter)
        else
          fn(graph, api)
        end

        -- Collect API outputs
        for _, d in ipairs(api._diagnostics) do all_diagnostics[#all_diagnostics + 1] = d end
        for _, u in ipairs(api._codegen_units) do all_codegen_units[#all_codegen_units + 1] = u end
        for _, c in ipairs(api._profile_counters) do all_profile_counters[#all_profile_counters + 1] = c end
      end
    end
  end

  return {
    diagnostics = all_diagnostics,
    codegen_units = all_codegen_units,
    profile_counters = all_profile_counters,
  }
end

return plugin_contract
