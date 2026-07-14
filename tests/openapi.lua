--- OpenAPI 3.1 spec generation tests.
--- Validates that the generated openapi.json is structurally correct.

package.path = "src/?.lua;src/?/init.lua;" .. package.path

local m = require("meteorite")
local openapi = require("codegen.openapi")
local report = require("codegen.report")
local json = require("utils.json")

local passed, failed = 0, 0

local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg .. " expected=" .. tostring(expected) .. " got=" .. tostring(actual))
  end
end

local function assert_truthy(value, msg)
  if value then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

-- Build a test app with various route shapes
local app = m.app({ name = "openapi-test" })

app:get("/users", {
  summary = "List users",
  tags = { "users" },
  operationId = "listUsers",
  query = { page = m.u64({ optional = true }) },
  responses = {
    [200] = { description = "User list", json = { count = m.u64() } },
  },
}, function(c) return c:json({ count = 0 }) end)

app:post("/users", {
  summary = "Create user",
  tags = { "users" },
  operationId = "createUser",
  json = { name = m.string({ max = 100 }), email = m.email() },
  responses = {
    [201] = { description = "Created", json = { id = m.u64() } },
    [400] = { description = "Validation error" },
  },
}, function(c) return c:json({ id = 1 }, { status = 201 }) end)

app:get("/users/:id", {
  params = { id = m.u64() },
  message = "users.get.by_id",
  responses = {
    [200] = { description = "User detail", json = { id = m.u64(), name = m.string() } },
    [404] = { description = "Not found" },
  },
}, function(c) return c:json({ id = c:param("id"), name = "test" }) end)

app:all("/webhook", {
  summary = "Webhook receiver (any method)",
  tags = { "webhooks" },
}, function(c) return c:text("ok") end)

app:get("/static/*", {
  summary = "Static file serving",
}, function(c) return c:text("file") end)

app:delete("/users/:id", {
  operationId = "deleteUser",
  message = "users.delete.by_id",
  responses = {
    [204] = { description = "Deleted" },
  },
}, function(c) return c:text(204, "") end)

local graph = app:normalize({ mode = "dev" })
local doc = openapi.emit(graph, { title = "openapi-test", version = "1.0.0" })

-- Test: basic structure
assert_eq(doc.openapi, "3.1.0", "openapi version")
assert_eq(doc.info.title, "openapi-test", "info.title")
assert_eq(doc.info.version, "1.0.0", "info.version")

-- Test: paths exist
assert_truthy(doc.paths["/users"], "/users path exists")
assert_truthy(doc.paths["/users/{id}"], "/users/{id} path exists")
assert_truthy(doc.paths["/webhook"], "/webhook path exists")
assert_truthy(doc.paths["/static/{wildcard}"], "/static/{wildcard} path exists")

-- Test: GET /users operation
local get_users = doc.paths["/users"]["get"]
assert_truthy(get_users, "GET /users operation exists")
assert_eq(get_users.summary, "List users", "GET /users summary")
assert_eq(get_users.operationId, "listUsers", "GET /users operationId")

-- Test: query parameter
local has_page_param = false
for _, p in ipairs(get_users.parameters or {}) do
  if p.name == "page" and p["in"] == "query" then
    has_page_param = true
    assert_eq(p.required, false, "page param not required")
    assert_eq(p.schema.type, "integer", "page param type integer")
    assert_eq(p.schema.minimum, 0, "page param minimum 0 (u64)")
  end
end
assert_truthy(has_page_param, "page query parameter exists")

-- Test: POST /users with request body
local post_users = doc.paths["/users"]["post"]
assert_truthy(post_users, "POST /users operation exists")
assert_truthy(post_users.requestBody, "POST /users has requestBody")
assert_truthy(post_users.requestBody.content["application/json"], "POST /users has JSON content")

local json_schema = post_users.requestBody.content["application/json"].schema
assert_eq(json_schema.type, "object", "POST /users body type object")
assert_truthy(json_schema.properties.name, "POST /users body has name property")
assert_truthy(json_schema.properties.email, "POST /users body has email property")
assert_eq(json_schema.properties.email.format, "email", "email field has format=email")

-- Test: required fields
local required_has_name = false
local required_has_email = false
for _, req in ipairs(json_schema.required or {}) do
  if req == "name" then required_has_name = true end
  if req == "email" then required_has_email = true end
end
assert_truthy(required_has_name, "name is required")
assert_truthy(required_has_email, "email is required")

-- Test: responses
assert_truthy(get_users.responses["200"], "GET /users has 200 response")
assert_eq(get_users.responses["200"].description, "User list", "GET /users 200 description")
assert_truthy(get_users.responses["200"].content["application/json"], "GET /users 200 has JSON content")
assert_eq(get_users.responses["200"].content["application/json"].schema.properties.count.type, "integer", "GET /users 200 count is integer")
assert_truthy(post_users.responses["201"], "POST /users has 201 response")
assert_eq(post_users.responses["201"].content["application/json"].schema.properties.id.minimum, 0, "POST /users 201 id is u64")
assert_truthy(post_users.responses["400"], "POST /users has 400 response")
assert_eq(post_users.responses["400"].description, "Validation error", "POST /users 400 description")

-- Test: OpenAPI plan uses the same response schema mapping
local plan = report.openapi_plan(graph)
local plan_get_users
for _, route in ipairs(plan.routes or {}) do
  if route.operationId == "listUsers" then plan_get_users = route end
end
assert_truthy(plan_get_users, "OpenAPI plan has listUsers route")
assert_eq(plan_get_users.responses["200"].properties.count.type, "integer", "OpenAPI plan count response is integer")

-- Test: path parameter
local get_user_id = doc.paths["/users/{id}"]["get"]
assert_truthy(get_user_id, "GET /users/{id} operation exists")
local has_id_param = false
for _, p in ipairs(get_user_id.parameters or {}) do
  if p.name == "id" and p["in"] == "path" then
    has_id_param = true
    assert_eq(p.required, true, "id path param required")
    assert_eq(p.schema.type, "integer", "id path param type integer")
  end
end
assert_truthy(has_id_param, "id path parameter exists")

-- Test: ALL method expands to all operations
local webhook = doc.paths["/webhook"]
assert_truthy(webhook["get"], "webhook has GET")
assert_truthy(webhook["post"], "webhook has POST")
assert_truthy(webhook["put"], "webhook has PUT")
assert_truthy(webhook["delete"], "webhook has DELETE")
assert_truthy(webhook["patch"], "webhook has PATCH")
assert_truthy(webhook["head"], "webhook has HEAD")
assert_truthy(webhook["options"], "webhook has OPTIONS")

-- Test: wildcard path
assert_truthy(doc.paths["/static/{wildcard}"], "wildcard path template correct")

-- Test: DELETE /users/{id} with 204
local delete_user = doc.paths["/users/{id}"]["delete"]
assert_truthy(delete_user, "DELETE /users/{id} operation exists")
assert_eq(delete_user.operationId, "deleteUser", "DELETE /users/{id} operationId")
assert_truthy(delete_user.responses["204"], "DELETE has 204 response")

-- Test: JSON serialization works
local json_str = openapi.emit_json(graph, { title = "test" })
assert_truthy(json_str and #json_str > 0, "emit_json produces non-empty string")

-- Test: pretty JSON serialization works
local pretty_str = openapi.emit_json(graph, { title = "test", pretty = true })
assert_truthy(pretty_str and pretty_str:find("\n"), "pretty JSON contains newlines")

-- Test: tags from route options
assert_eq(#get_users.tags, 1, "GET /users has 1 tag")
assert_eq(get_users.tags[1], "users", "GET /users tag is 'users'")

-- Test: security schemes inferred from headers
local app2 = m.app({ name = "auth-test" })
app2:get("/protected", {
  headers = { ["Authorization"] = m.token() },
}, function(c) return c:text("protected") end)
local graph2 = app2:normalize({ mode = "dev" })
local doc2 = openapi.emit(graph2)
assert_truthy(doc2.components, "doc has components")
assert_truthy(doc2.components.securitySchemes, "doc has securitySchemes")
assert_truthy(doc2.components.securitySchemes["bearerAuth"], "bearerAuth scheme exists")
assert_eq(doc2.components.securitySchemes["bearerAuth"].type, "http", "bearerAuth type is http")
assert_eq(doc2.components.securitySchemes["bearerAuth"].scheme, "bearer", "bearerAuth scheme is bearer")

-- Test: cookie-based security scheme
local app3 = m.app({ name = "cookie-test" })
app3:get("/dashboard", {
  cookies = { session = m.token() },
}, function(c) return c:text("dashboard") end)
local graph3 = app3:normalize({ mode = "dev" })
local doc3 = openapi.emit(graph3)
assert_truthy(doc3.components.securitySchemes["cookie_session"], "cookie_session scheme exists")
assert_eq(doc3.components.securitySchemes["cookie_session"].type, "apiKey", "cookie scheme type apiKey")
assert_eq(doc3.components.securitySchemes["cookie_session"]["in"], "cookie", "cookie scheme in cookie")

-- Test: paths are sorted alphabetically
local sorted_paths = {}
for path, _ in pairs(doc.paths) do sorted_paths[#sorted_paths + 1] = path end
table.sort(sorted_paths)
assert_eq(sorted_paths[1], "/static/{wildcard}", "first sorted path")
assert_eq(sorted_paths[2], "/users", "second sorted path")
assert_eq(sorted_paths[3], "/users/{id}", "third sorted path")
assert_eq(sorted_paths[4], "/webhook", "fourth sorted path")

print(string.format("PASSED=%d FAILED=%d", passed, failed))
if failed > 0 then os.exit(1) end
