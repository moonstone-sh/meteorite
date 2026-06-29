--- First-party cache plugin for Meteorite.
--- Injects cache lookup and store stages into route pipelines.
---
--- @class CachePlugin
--- @field id string  Plugin identifier

local plugin_contract = require("core.plugin_contract")

local cache = {}

--- Create the cache plugin.
---@return PluginDefinition
--- Create the cache plugin.
---@return PluginDefinition
function cache.create()
  return plugin_contract.define({
    id = "meteorite.cache",
    version = "0.1.0",
    consumes_policy = { "cache" },
    phases = { "pre_tree", "post_handler" },
    graph_passes = { "validate", "transform" },

    validate = function(graph, diag)
      for _, route in ipairs(graph.routes or {}) do
        if route.policy and route.policy.cache then
          local policy = route.policy.cache
          if policy.mode and policy.mode ~= "public" and policy.mode ~= "private" then
            diag.emit("error", "cache policy mode must be 'public' or 'private', got: " .. tostring(policy.mode),
              { route = route.id })
          end
          if policy.ttl and type(policy.ttl) ~= "number" then
            diag.emit("error", "cache policy ttl must be a number (seconds), got: " .. type(policy.ttl),
              { route = route.id })
          end
          if policy.ttl and policy.ttl < 0 then
            diag.emit("error", "cache policy ttl must be non-negative, got: " .. tostring(policy.ttl),
              { route = route.id })
          end
        end
      end
    end,

    transform = function(graph, api)
      for _, route in ipairs(api:get_routes()) do
        local policy = api:get_policy(route.id, "cache")
        if policy and not policy.disabled then
          api:prepend_stage(route.id, {
            id = "cache_lookup",
            kind = "transform",
            strat = "lua",
            path = "meteorite/plugins/cache_lookup.lua",
            may_short_circuit = true,
            meta = { cache_key = policy.key or "method:path", ttl = policy.ttl or 60 },
          })
          api:append_stage(route.id, {
            id = "cache_store",
            kind = "transform",
            strat = "lua",
            path = "meteorite/plugins/cache_store.lua",
            may_short_circuit = false,
            meta = { cache_key = policy.key or "method:path", ttl = policy.ttl or 60 },
          })
          api:add_profile_counter("cache_hits_" .. route.id, "Cache hits for route " .. route.id)
          api:add_profile_counter("cache_misses_" .. route.id, "Cache misses for route " .. route.id)
        end
      end
    end,
  })
end

return cache
