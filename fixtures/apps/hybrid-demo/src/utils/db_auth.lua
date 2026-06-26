local db_auth = {}

function db_auth.shared(c)
  local existing = c:get("auth")
  if existing then return existing end
  local auth = {
    headers = {
      authorization = "Bearer demo-token",
    },
  }
  return c:set("auth", auth)
end

return db_auth
