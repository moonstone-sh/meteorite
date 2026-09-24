package.path = "src/?.lua;src/?/init.lua;" .. package.path

local m = require("meteorite")
local openapi = require("codegen.openapi")

local bundle = m.contracts.from_document({
  format = "moonstone.contract-bundle.v1",
  namespace = "todo",
  version = "0.1.0",
  exports = {
    {
      id = "todo.CreateTodo",
      name = "CreateTodo",
      input = {
        type = "object", additionalProperties = false,
        properties = { title = { type = "string", minLength = 1 }, done = { type = "boolean" } },
        required = { "title" },
      },
      output = {
        type = "object", additionalProperties = false,
        properties = { id = { type = "integer", minimum = 1 }, title = { type = "string" } },
        required = { "id", "title" },
      },
    },
  },
})

local app = m.app({ name = "contract-test" })
app:post("/todos", {
  json = bundle:input("todo.CreateTodo"),
  responses = { [201] = bundle:response("todo.CreateTodo", { description = "Created" }) },
}, function(c) return c:json({ id = 1, title = "hello" }, { status = 201 }) end)

local graph = app:normalize({ mode = "dev" })
local route = graph.routes[1]
assert(route.validation.json_body[1].name == "done")
assert(route.validation.json_body[1].optional == true)
assert(route.validation.json_body[2].name == "title")
assert(route.validation.json_body[2].min_len == 1)

local doc = openapi.emit(graph)
local operation = doc.paths["/todos"].post
assert(operation.requestBody.required == true)
assert(operation.requestBody.content["application/json"].schema.properties.done.type == "boolean")
assert(operation.responses["201"].content["application/json"].schema.properties.id.type == "integer")

local unsupported = m.contracts.from_document({
  format = "moonstone.contract-bundle.v1", namespace = "bad", version = "0.1.0",
  exports = {{ id = "bad.Nested", input = { type = "object", additionalProperties = false, properties = { tags = { type = "array", items = { type = "string" } } } }, output = {} }},
})
local ok, err = pcall(function() return unsupported:input("bad.Nested") and m.app({ name = "bad" }):post("/bad", { json = unsupported:input("bad.Nested") }, function() end) end)
assert(not ok and tostring(err):find("supported: string, integer, boolean", 1, true))

print("contract OpenAPI integration: OK")
