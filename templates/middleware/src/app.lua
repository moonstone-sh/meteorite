local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "{{name}}" })

local require_auth = m.plugin({
  kind = "auth",
  id = "require_auth",
  execute = function(ctx)
    if not ctx:header("authorization") then
      return ctx:text(401, "unauthorized", {
        headers = { ["WWW-Authenticate"] = 'Bearer realm="{{name}}"' },
      })
    end
  end,
})

local attach_scope = m.plugin({
  kind = "state",
  id = "attach_scope",
  execute = function(ctx)
    ctx:set("tenant", ctx.scope.tenant or "public")
  end,
})

app:get("/health", function(ctx)
  return ctx:json({ ok = true })
end)

app:mount("/api", {
  id = "api",
  context = { tenant = "demo" },
  plugins = { require_auth, attach_scope },
}, function(api)
  api:get("/me", function(ctx)
    return ctx:json({ tenant = ctx:get("tenant") })
  end)
end)

return app
