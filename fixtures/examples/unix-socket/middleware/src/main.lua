local m = require("meteorite")

local app = m.app()

local require_token = m.plugin({
  kind = "ipc-auth",
  id = "require_token",
  execute = function(ctx)
    if ctx:metadata("token") ~= "dev" then
      return ctx:text(401, "missing token")
    end
  end,
})

local mark_scope = m.plugin({
  kind = "ipc-state",
  id = "mark_scope",
  execute = function(ctx)
    ctx:set("scope", ctx.scope.name or "root")
  end,
})

app:mount("/secure", {
  id = "secure_messages",
  context = { name = "secure" },
  plugins = { require_token, mark_scope },
}, function(scope)
  scope:message("secure.echo", { body = { max = "8kb" } }, function(ctx)
    return ctx:json({ scope = ctx:get("scope"), body = ctx:body() })
  end)
end)

return app
