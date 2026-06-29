--- First-party idempotency plugin for Meteorite.
--- Ensures safe replay of side-effecting requests using Idempotency-Key.
---
--- @class IdempotencyPlugin
--- @field id string  Plugin identifier

local plugin_contract = require("core.plugin_contract")

local idempotency = {}

--- Create the idempotency plugin.
---@return PluginDefinition
--- Create the idempotency plugin.
---@return PluginDefinition
function idempotency.create()
  return plugin_contract.define({
    id = "meteorite.idempotency",
    version = "0.1.0",
    consumes_policy = { "idempotency" },
    phases = { "post_match", "post_handler" },
    graph_passes = { "validate", "transform" },

    validate = function(graph, diag)
      for _, route in ipairs(graph.routes or {}) do
        if route.policy and route.policy.idempotency then
          local policy = route.policy.idempotency
          if not policy.header then
            diag.emit("error", "idempotency policy requires a 'header' field (e.g. \"Idempotency-Key\")",
              { route = route.id })
          end
          if policy.ttl and type(policy.ttl) ~= "number" then
            diag.emit("error", "idempotency policy ttl must be a number (seconds)",
              { route = route.id })
          end
          if policy.cache_status then
            for _, status in ipairs(policy.cache_status) do
              if type(status) ~= "number" or status < 100 or status > 599 then
                diag.emit("error", "idempotency cache_status must contain valid HTTP status codes",
                  { route = route.id, status = status })
              end
            end
          end
        end
      end
    end,

    transform = function(graph, api)
      for _, route in ipairs(api:get_routes()) do
        local policy = api:get_policy(route.id, "idempotency")
        if policy then
          -- Inject idempotency lookup before handler
          api:prepend_stage(route.id, {
            id = "idempotency_lookup",
            kind = "transform",
            strat = "lua",
            path = "meteorite/plugins/idempotency_lookup.lua",
            may_short_circuit = true,
            meta = {
              header = policy.header or "Idempotency-Key",
              ttl = policy.ttl or 86400,
              fingerprint = policy.fingerprint or "method:path:body_hash",
              cache_status = policy.cache_status or { 200, 201, 202, 409 },
            },
          })

          -- Inject response persistence after handler
          api:append_stage(route.id, {
            id = "idempotency_store",
            kind = "transform",
            strat = "lua",
            path = "meteorite/plugins/idempotency_store.lua",
            may_short_circuit = false,
            meta = {
              header = policy.header or "Idempotency-Key",
              ttl = policy.ttl or 86400,
              cache_status = policy.cache_status or { 200, 201, 202, 409 },
            },
          })
        end
      end
    end,
  })
end

return idempotency
