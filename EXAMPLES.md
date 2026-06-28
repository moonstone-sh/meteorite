# Meteorite Examples

Examples are copyable app shapes, not `meteorite init` templates. Init stays focused
on Meteorite execution modes: minimal hybrid, static Zig, and hybrid Lua+Zig.

## CRUD-Shaped Service

Meteorite is database agnostic. The repository methods below are placeholders:
replace them with SQLite, Postgres, MySQL, file storage, an HTTP API, or any
storage/validation layer you prefer.

### `src/main.lua`

```lua
return require("app")
```

### `src/app.lua`

```lua
local m = require("meteorite")

---@type MeteoriteApp
local app = m.app({ name = "crud-service" })

app:get("/", function(c)
  return c:json({ service = "crud-service", routes = { "/users" } })
end)

app:get("/users", function(c)
  local repo = require("repo")
  return c:json(repo.list_users())
end)

app:post("/users", function(c)
  local repo = require("repo")
  return c:json(repo.create_user(repo.read_user_input(c)), { status = 201 })
end)

app:get("/users/:id", function(c)
  local repo = require("repo")
  local user = repo.find_user(tonumber(c.params.id))
  if not user then return c:json({ error = "not found" }, { status = 404 }) end
  return c:json(user)
end)

app:patch("/users/:id", function(c)
  local repo = require("repo")
  local user = repo.update_user(tonumber(c.params.id), repo.read_user_input(c))
  if not user then return c:json({ error = "not found" }, { status = 404 }) end
  return c:json(user)
end)

app:delete("/users/:id", function(c)
  local repo = require("repo")
  if not repo.delete_user(tonumber(c.params.id)) then
    return c:json({ error = "not found" }, { status = 404 })
  end
  return c:json({ ok = true })
end)

return app
```

### `src/repo.lua`

```lua
local repo = {}

local users = {}
local next_id = 1

function repo.read_user_input(c)
  -- TODO: decode JSON/form data with your preferred package or validation layer.
  -- This placeholder keeps the example dependency-free and storage-agnostic.
  local raw = c:body() or ""
  return {
    name = raw:match('"name"%s*:%s*"([^"]+)"') or "Anonymous",
    email = raw:match('"email"%s*:%s*"([^"]+)"') or "anonymous@example.test",
  }
end

function repo.list_users()
  -- TODO: SELECT/list records from your storage layer.
  local rows = {}
  for _, user in pairs(users) do rows[#rows + 1] = user end
  table.sort(rows, function(a, b) return a.id < b.id end)
  return rows
end

function repo.create_user(input)
  -- TODO: INSERT/create a record using your storage layer.
  local user = {
    id = next_id,
    name = input.name or "Anonymous",
    email = input.email or "anonymous@example.test",
  }
  next_id = next_id + 1
  users[user.id] = user
  return user
end

function repo.find_user(id)
  -- TODO: SELECT/find a record by primary key.
  return users[id]
end

function repo.update_user(id, input)
  -- TODO: UPDATE/patch a record using your storage layer.
  local user = users[id]
  if not user then return nil end
  user.name = input.name or user.name
  user.email = input.email or user.email
  return user
end

function repo.delete_user(id)
  -- TODO: DELETE/remove a record using your storage layer.
  local user = users[id]
  users[id] = nil
  return user ~= nil
end

return repo
```
