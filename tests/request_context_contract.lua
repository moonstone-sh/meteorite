package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local hybrid = require("cli.hybrid")
local m = require("meteorite")
local test = require("test")

test "invoke exposes the same routing context contract as compiled Lua" (function()
  local app = m.app({ name = "request-context-contract" })
  app:get("/users/:id", { id = "page.users.show" }, function(c)
    return c:text(table.concat({ c:target(), c:path(), c:route_id(), c:param("id"), c:query("tab") }, "|"))
  end)

  local response = hybrid.invoke(app, {
    method = "GET",
    path = "/users/42?tab=activity",
  })
  test.assert_eq(response.status, 200, "context route response status")
  test.assert_eq(response.body, "/users/42?tab=activity|/users/42|page.users.show|42|activity", "target, path, id, params, and query are distinct")
end)

test "invoke redirect validates and stages the same redirect response" (function()
  local app = m.app({ name = "request-context-redirect" })
  app:post("/submit", { id = "submit" }, function(c)
    c:redirect(303, "/done")
  end)
  local response = hybrid.invoke(app, { method = "POST", path = "/submit" })
  test.assert_eq(response.status, 303, "redirect status")
  test.assert_eq(response.headers.Location, "/done", "redirect location")
  test.assert_eq(response.body, "", "redirect body")
end)

test "form bodies preserve textarea newlines and repeated successful controls" (function()
  local app = m.app({ name = "request-context-form" })
  app:post("/form", function(c)
    local form, err = c:form_body()
    assert(form, err)
    return c:text(form.note .. "|" .. table.concat(form.tag, ","))
  end)
  local response = hybrid.invoke(app, {
    method = "POST",
    path = "/form",
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    body = "note=one%0Atwo&tag=lua&tag=zig",
  })
  test.assert_eq(response.status, 200, "form response status")
  test.assert_eq(response.body, "one\ntwo|lua,zig", "one value stays scalar and repeated values become an ordered array")
end)

test "Lua file handler argument metadata survives declaration normalization" (function()
  local app = m.app({ name = "handler-metadata" })
  app:get("/users/:id", { id = "typed" }, m.lua("handlers.user", {
    nparams = 1,
    arg_mode = "lazy_context",
  }))
  local graph = app:normalize({ mode = "dev" })
  local handler = graph.routes[1].handler
  test.assert_eq(handler.nparams, 1, "nparams retained")
  test.assert_eq(handler.arg_mode, "lazy_context", "arg mode retained")
end)

test.run()
