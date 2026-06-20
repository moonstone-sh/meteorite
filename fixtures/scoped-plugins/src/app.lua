local m = require("meteorite")

local app = m.app({ name = "scoped-plugins" })

local require_auth = m.plugin({
  kind = "auth",
  id = "require_auth",
  execute = function(ctx)
    if not ctx:header("authorization") then
      return { status = 401, content_type = "text/plain", body = "unauthorized" }
    end
  end,
})

local set_tenant = m.plugin({
  kind = "tenant",
  id = "set_tenant",
  execute = function(ctx)
    ctx:set("tenant", ctx.scope.tenant)
  end,
})

app:get("/health", function(c)
  return c:text("ok")
end)

app:mount("/orgs/:org_id", {
  id = "org",
  params = { org_id = m.u64() },
  context = { tenant = "org" },
  plugins = { require_auth, set_tenant },
}, function(org)
  org:get("/", function(c)
    return c:json({ scope = c.scope.tenant, state = c:get("tenant") })
  end)

  org:mount("/projects/:project_id", {
    id = "project",
    params = { project_id = m.u64() },
    context = { tenant = "project" },
  }, function(project)
    project:get("/", function(c)
      return c:json({ scope = c.scope.tenant, state = c:get("tenant") })
    end)
  end)
end)

return app
