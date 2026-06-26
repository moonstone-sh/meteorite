package.path = "src/?.lua;src/?/init.lua;" .. package.path
local hybrid = require("cli.hybrid")
local m = require("meteorite")

local app = m.app({ name = "test" })

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

local function assert_eq(name, actual, expected)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", name, tostring(expected), tostring(actual)))
  end
end

local r1 = hybrid.invoke(app, { method = "GET", path = "/health" }, { mode = "dev" })
assert_eq("/health status", r1.status, 200)
assert_eq("/health body", r1.body, "ok")

local r2 = hybrid.invoke(app, { method = "GET", path = "/orgs/123" }, { mode = "dev" })
assert_eq("missing auth status", r2.status, 401)
assert_eq("missing auth body", r2.body, "unauthorized")

local r3 = hybrid.invoke(app, { method = "GET", path = "/orgs/123", headers = { authorization = "Bearer x" } }, { mode = "dev" })
assert_eq("/orgs/123 status", r3.status, 200)
local body3 = r3.body or ""
if not body3:find('"scope":"org"', 1, true) then error("expected scope org in body: " .. body3) end
if not body3:find('"state":"org"', 1, true) then error("expected state org in body: " .. body3) end

local r4 = hybrid.invoke(app, { method = "GET", path = "/orgs/123/projects/456", headers = { authorization = "Bearer x" } }, { mode = "dev" })
assert_eq("nested status", r4.status, 200)
local body4 = r4.body or ""
if not body4:find('"scope":"project"', 1, true) then error("expected scope project in body: " .. body4) end
if not body4:find('"state":"project"', 1, true) then error("expected state project in body: " .. body4) end

print("scope plugin tests passed")
