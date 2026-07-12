local m = require("meteorite")

local app = m.app()

local set_scope = m.plugin({
  kind = "ipc-middleware-state",
  id = "ipc_native_set_scope",
  execute = function(ctx)
    ctx:set("middleware_scope", ctx.scope.middleware or "missing")
  end,
})

local short_circuit = m.plugin({
  kind = "ipc-middleware-short-circuit",
  id = "ipc_native_short_circuit",
  execute = function(ctx)
    if ctx:metadata("allow") ~= "yes" then
      return ctx:text(401, "middleware:blocked")
    end
  end,
})

local failing_middleware = m.plugin({
  kind = "ipc-middleware-error",
  id = "ipc_native_failing_middleware",
  execute = function()
    error("ipc middleware boom")
  end,
})

app:message("health.get", function(ctx)
  return ctx:text("ok:" .. ctx:message())
end)

app:message({
  name = "system.ping",
  handler = function(ctx)
    return ctx:text("pong:" .. ctx:message())
  end,
})

app:message("users.get", {
  metadata = {
    id = m.u64(),
  },
}, function(ctx)
  return ctx:json({
    id = tonumber(ctx:metadata("id")),
    param_id = tonumber(ctx:param("id")),
    query_verbose = ctx:query("verbose") == "true",
    message = ctx:message(),
    header_is_http_only = ctx:header("id") == nil,
  })
end)

app:message("users.create", {
  body = { max = "64kb" },
  json = {
    id = m.u64(),
    name = m.token(),
  },
}, function(ctx)
  local body, err = ctx:json_body()
  if err then return ctx:text(400, err) end
  return ctx:json({
    id = body.id,
    name = body.name,
    message = ctx:message(),
  })
end)

app:message("bench.stats.check", function(ctx)
  return ctx:text(ctx:request_id())
end)

app:mount("/native-middleware", {
  id = "native_middleware",
  context = { middleware = "ipc" },
  plugins = { set_scope, short_circuit },
}, function(scope)
  scope:message("middleware.state", function(ctx)
    ctx:log("info", "native middleware state", { message = ctx:message() })
    return ctx:json({
      message = ctx:message(),
      state = ctx:get("middleware_scope"),
      request_id = ctx:request_id(),
    })
  end)

  scope:message("middleware.bytes", { body = { max = "1kb" } }, function(ctx)
    return ctx:bytes(200, "application/octet-stream", ctx:body())
  end)
end)

app:mount("/native-middleware-error", {
  id = "native_middleware_error",
  plugins = { failing_middleware },
}, function(scope)
  scope:message("middleware.error", function(ctx)
    return ctx:text("unreachable")
  end)
end)

return app
