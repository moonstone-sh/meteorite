# Meteorite Examples

Examples are copyable app shapes, not `meteorite init` templates. Init stays focused
on Meteorite execution modes: minimal hybrid, static Zig, and hybrid Lua+Zig.

## Tiny String Templates

Meteorite exposes `m.template.render()` as a dependency-free helper for simple
`{{name}}` string substitution. It is intentionally not an HTML/template engine:
escaping, loops, layouts, and partials belong to app-selected libraries such as
`etlua`.

```lua
local m = require("meteorite")

local app = m.app({ name = "template-example" })

app:get("/hello/:name", function(c)
  return c:text(m.template.render("Hello {{name}}!", {
    name = c:param("name"),
  }))
end)

return app
```

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
  local user = repo.find_user(tonumber(c:param("id")))
  if not user then return c:json({ error = "not found" }, { status = 404 }) end
  return c:json(user)
end)

app:patch("/users/:id", function(c)
  local repo = require("repo")
  local user = repo.update_user(tonumber(c:param("id")), repo.read_user_input(c))
  if not user then return c:json({ error = "not found" }, { status = 404 }) end
  return c:json(user)
end)

app:delete("/users/:id", function(c)
  local repo = require("repo")
  if not repo.delete_user(tonumber(c:param("id"))) then
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


## Handler Context API

### Parameter Convention and Context Shape

Meteorite determines the context shape from the **first parameter name** of your
inline Lua handler:

| First param | `arg_mode`         | Context shape                                   |
|-------------|--------------------|-------------------------------------------------|
| `ctx` / `c` | `lazy_context`     | Methods only: `ctx:query()`, `ctx:param()`, etc. |
| `req`       | `request_table`    | Pre-populated tables: `req.query.name`, `req.params.name` |
| (none)      | `no_args`          | No context passed                               |
| other       | `direct_params`    | Positional path-param arguments                 |

**Recommended**: use `ctx` or `c` as the first parameter. The `lazy_context`
mode gives you method-based access that works identically in compiled runtime
and local `meteorite invoke`:

```lua
app:get("/users/:id", { params = { id = m.u64() } }, function(ctx)
  return ctx:json({ id = ctx:param("id") })
end)
```

### String Return Sugar

Returning a bare string from a handler is sugar for `200 text/plain; charset=utf-8`:

```lua
app:get("/health", function()
  return "ok"
end)
```

This is equivalent to:

```lua
app:get("/health", function(ctx)
  return ctx:text(200, "ok")
end)
```

Use it for simple status/echo endpoints. For custom status codes, content types,
or headers, return a response table or use a helper:

```lua
app:get("/json", function(ctx)
  return ctx:json({ ok = true })
end)

app:get("/redirect", function()
  return { status = 302, content_type = "text/plain; charset=utf-8", body = "redirect", headers = { Location = "/" } }
end)
```

### Query Parameter Access

Query values are percent-decoded and returned as strings (or converted types
when declared with validators):

```lua
app:get("/search", { query = { q = m.string({ max = 100 }), page = m.u64({ optional = true }) } }, function(ctx)
  return ctx:json({ q = ctx:query("q"), page = ctx:query("page") })
end)
```

For repeated query parameters (`?tag=pepe&tag=pope`), use `ctx:query_all()`:

```lua
app:get("/filter", function(ctx)
  local tags = ctx:query_all("tag") or {}
  return ctx:json({ tags = tags })  -- { "pepe", "pope" }
end)
```

`ctx:query("tag")` returns the first value (`"pepe"`). `ctx:query_all("tag")`
returns all values as a Lua array.

## Route Priority and Matching Order

Meteorite routes are matched in **registration order** — the first route that
matches the request method and path wins. This is deterministic at compile time
because the graph preserves declaration order.

### Priority Rules

1. **Method-specific routes take priority over `app:all()` routes.**
   A `GET /users` route is checked before an `ALL /users` route for `GET` requests.
   The `ALL` route only matches methods that have no specific route at the same path.

2. **`GET` routes also serve `HEAD` requests** unless an explicit `HEAD` route
   is declared at the same path.

3. **Static (literal) segments match before param segments** within the same
   route iteration. Routes are iterated in registration order, so a more
   specific route declared first will always win.

4. **Wildcard `*` matches the final segment and all remaining path segments.**
   It must be the last segment in the path pattern (e.g. `/static/*`).

5. **Catch-all params (`:name*`) also match remaining segments** but capture
   the matched value into `ctx:param("name")`. Like wildcards, they must be
   the final segment.

6. **Duplicate routes (same method + path) are rejected** at graph build time
   with a diagnostic message.

### Example: Priority in Action

```lua
local m = require("meteorite")
local app = m.app({ name = "priority-demo" })

-- This specific GET route wins for GET /api/items
app:get("/api/items", function(c)
  return c:text("get-items")
end)

-- This ALL route is the fallback for other methods at /api/items
app:all("/api/items", function(c)
  return c:text("all-items:" .. c.request.method)
end)

-- Wildcard matches /files/css/app.css, /files/js/vendor/lib.js, etc.
app:get("/files/*", function(c)
  return c:text("file-served")
end)

-- Catch-all param captures the remaining path
app:get("/download/:path*", function(c)
  return c:text("downloading:" .. c:param("path"))
end)
```

### Matching Summary

| Pattern | Matches | Captures |
|---------|---------|----------|
| `/users` | exactly `/users` | — |
| `/users/:id` | `/users/42`, `/users/abc` | `id` = `42` or `abc` |
| `/static/*` | `/static/`, `/static/css/app.css` | — (wildcard, no capture) |
| `/files/:path*` | `/files/x`, `/files/a/b/c` | `path` = `x` or `a/b/c` |
| `app:all("/hook")` | any method at `/hook` | — |
