return function(c)
  local user = c:http("db"):post("/get-user-from-db", {
    headers = c:auth("db"):headers(),
    body = {
      id = c.params.id,
    },
  })

  return c:json({
    id = c.params.id,
    user = user.body,
    message = "typed params from native graph",
  })
end
