package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local test = require("test")
local m = require("meteorite")
local typescript_client = require("codegen.typescript_client")
local luacats_client = require("codegen.luacats_client")

local contracts = m.contracts.from_document({
  format = "moonstone.contract-bundle.v1",
  namespace = "todo",
  version = "0.1.0",
  exports = {
    {
      id = "todo.CreateTodo",
      name = "CreateTodo",
      input = {
        type = "object", additionalProperties = false,
        properties = { title = { type = "string" }, done = { type = "boolean" } },
        required = { "title" },
      },
      output = {
        type = "object", additionalProperties = false,
        properties = { id = { type = "integer" }, title = { type = "string" }, labels = { type = "array", items = { type = "string" } } },
        required = { "id", "title", "labels" },
      },
    },
  },
})

local app = m.app({ name = "typescript-client-test" })
app:post("/todos/:id", {
  operationId = "createTodo",
  json = contracts:input("todo.CreateTodo"),
  responses = { [201] = contracts:response("todo.CreateTodo") },
}, function(c) return c:json({ id = 1, title = "ship", labels = {} }, { status = 201 }) end)

local source = typescript_client.emit(app:normalize({ mode = "dev" }))
local luacats = luacats_client.emit(app:normalize({ mode = "dev" }))

test "TypeScript client emits contract request and response DTOs" (function()
  test.assert_true(source:find("export type CreateTodoRequest = { done%?: boolean; title: string; };") ~= nil, "request DTO")
  test.assert_true(source:find("export type CreateTodoResponse = { id: number; labels: Array<string>; title: string; };") ~= nil, "response DTO")
  test.assert_true(source:find("export type CreateTodoArgs = { params: { id: string | number; }; query%?: Record<string, string | number | boolean | null | undefined>; body: CreateTodoRequest; headers%?: HeadersInit; signal%?: AbortSignal; };") ~= nil, "typed route arguments")
end)

test "LuaX can consume the same DTOs through ambient LuaCATS" (function()
  test.assert_true(luacats:find('---@meta "meteorite%-client"') ~= nil, "ambient declaration")
  test.assert_true(luacats:find("---@alias CreateTodoRequest { done%?: boolean, title: string }") ~= nil, "request alias")
  test.assert_true(luacats:find("---@alias CreateTodoResponse { id: number, labels: string%[%], title: string }") ~= nil, "response alias")
end)

test "TypeScript client is browser-native and routes through fetch" (function()
  test.assert_true(source:find("export function createClient", 1, true) ~= nil, "client factory")
  test.assert_true(source:find("globalThis.fetch", 1, true) ~= nil, "browser fetch")
  test.assert_true(source:find("async createTodo(args: CreateTodoArgs)", 1, true) ~= nil, "typed operation")
  test.assert_true(source:find('applyPath("/todos/:id", args.params)', 1, true) ~= nil, "path binding")
  test.assert_true(source:find("signal: args.signal", 1, true) ~= nil, "forwards abort signal")
end)

test.run()
