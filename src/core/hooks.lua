--- Hook phase enforcement and permissions.
--- Defines what each phase may do and validates at graph time.
---
--- @class HookPhaseModule
--- @field phases table  Valid phase definitions
--- @field validate fun(stage: table, route: table?): string|nil  Validate phase usage, return error if invalid
--- @field describe fun(phase: string): string  Get human-readable description of a phase

local hooks = {}

--- Phase permissions
---@type table<string, table>
hooks.phases = {
  pre_tree = {
    description = "Before route tree/DFA match",
    may = { "inspect_method", "inspect_path", "inspect_query", "inspect_headers", "short_circuit" },
    must_not = { "require_route_params", "mutate_response" },
  },
  post_match = {
    description = "Route matched, before body/handler work",
    may = { "inspect_route_params", "inspect_route_policy", "short_circuit" },
    must_not = { "mutate_response" },
  },
  pre_handler = {
    description = "Immediately before handle stage",
    may = { "inspect_route_params", "inspect_route_policy", "short_circuit" },
    must_not = { "mutate_response" },
  },
  post_handler = {
    description = "After handler/response producer",
    may = { "inspect_response", "mutate_response", "short_circuit" },
    must_not = {},
  },
  observe = {
    description = "After response commit, no mutation",
    may = { "inspect_response" },
    must_not = { "mutate_response", "short_circuit" },
  },
  error = {
    description = "Structured error handling",
    may = { "inspect_error", "produce_response", "short_circuit" },
    must_not = {},
  },
}

--- Validate a hook stage's phase usage.
---@param stage table  The hook stage to validate
---@param route? table  The route it's attached to (nil for global)
---@return string|nil  Error message if invalid, nil if valid
--- Validate a hook stage's phase usage.
---@param stage table  The hook stage to validate
---@param route? table  The route it's attached to (nil for global)
---@return string|nil  Error message if invalid, nil if valid
function hooks.validate(stage, route)
  if stage.kind ~= "hook" then return nil end

  local phase = stage.phase
  if not phase then
    return "hook stage requires a 'phase' field"
  end

  local phase_def = hooks.phases[phase]
  if not phase_def then
    return "invalid hook phase: " .. tostring(phase) ..
      " (expected: pre_tree, post_match, pre_handler, post_handler, observe, error)"
  end

  -- Check observe hooks cannot short-circuit
  if phase == "observe" and stage.may_short_circuit then
    return "observe hooks must not short-circuit (may_short_circuit must be false)"
  end

  -- Check observe hooks cannot mutate
  if phase == "observe" and stage.writes then
    for _, w in ipairs(stage.writes) do
      if w:find("response", 1, true) then
        return "observe hooks must not write to response"
      end
    end
  end

  -- Check pre_tree hooks must not require route params
  if phase == "pre_tree" and stage.reads then
    for _, r in ipairs(stage.reads) do
      if r:find("route_param", 1, true) or r:find("param", 1, true) then
        return "pre_tree hooks must not read route params (route not matched yet)"
      end
    end
  end

  return nil
end

--- Get a human-readable description of a phase.
---@param phase string  Phase name
---@return string  Description
--- Get a human-readable description of a phase.
---@param phase string  Phase name
---@return string  Description
function hooks.describe(phase)
  local def = hooks.phases[phase]
  if not def then return "unknown phase: " .. tostring(phase) end
  return def.description
end

--- Validate all hooks in a graph.
---@param graph table  Normalized route graph
---@return string[]  Array of error messages (empty if all valid)
--- Validate all hooks in a graph.
---@param graph table  Normalized route graph
---@return string[]  Array of error messages (empty if all valid)
function hooks.validate_graph(graph)
  local errors = {}

  -- Check global hooks
  for _, hook in ipairs(graph.hooks or {}) do
    local stage = hook.stage or hook
    local err = hooks.validate(stage)
    if err then
      errors[#errors + 1] = string.format("global hook in phase '%s': %s",
        hook.phase or stage.phase or "?", err)
    end
  end

  -- Check route-local hooks in pipelines
  for _, route in ipairs(graph.routes or {}) do
    if route.pipeline then
      for _, stage in ipairs(route.pipeline) do
        if stage.kind == "hook" then
          local err = hooks.validate(stage, route)
          if err then
            errors[#errors + 1] = string.format("route '%s' hook in phase '%s': %s",
              route.id or route.raw_path or "?", stage.phase or "?", err)
          end
        end
      end
    end
  end

  return errors
end

return hooks
