package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local test = require("test")
local m = require("meteorite")
local lua_client = require("codegen.lua_client")

local app = m.app({ name = "client-test" })

app:get("/users", {
  operationId = "listUsers",
  message = "users.list",
  query = { page = m.u64({ optional = true }) },
}, function(c) return c:json({}) end)

app:get("/users/:id", {
  params = { id = m.u64() },
  message = "users.get",
}, function(c) return c:json({}) end)

app:post("/files/:path*", {
  operationId = "uploadFile",
  message = "files.upload",
}, function(c) return c:text("ok") end)

local graph = app:normalize({ mode = "dev" })
local source = lua_client.emit(graph, { module_name = "api" })

local function load_client()
  local chunk, err
  if _VERSION == "Lua 5.1" then
    chunk, err = loadstring(source, "generated-client")
    if chunk and setfenv then setfenv(chunk, _G) end
  else
    chunk, err = load(source, "generated-client", "t", _G)
  end
  assert(chunk, err)
  return chunk()
end

test "route names prefer operationId and message" (function()
  local names = table.concat(lua_client.route_names(graph), ",")
  test.assert_true(names:find("listUsers", 1, true), "operationId name")
  test.assert_true(names:find("users_get", 1, true), "message name")
  test.assert_true(names:find("uploadFile", 1, true), "upload operationId")
end)

test "generated client builds method path and query" (function()
  local api = load_client()
  local captured
  local instance = api.new({ request = function(opts) captured = opts; return opts end })
  local result = instance:listUsers({ query = { page = 2 } })
  test.assert_eq(result, captured, "transport result")
  test.assert_eq(captured.method, "GET", "method")
  test.assert_eq(captured.path, "/users?page=2", "query path")
end)

test "generated client substitutes encoded path params" (function()
  local api = load_client()
  local captured
  local instance = api.new({ request = function(opts) captured = opts; return opts end })
  instance:users_get({ params = { id = 42 } })
  test.assert_eq(captured.path, "/users/42", "path param")
  instance:uploadFile({ params = { path = "nested/a b.txt" }, body = "data" })
  test.assert_eq(captured.method, "POST", "post method")
  test.assert_eq(captured.path, "/files/nested/a%20b.txt", "catch-all path")
  test.assert_eq(captured.body, "data", "body forwarded")
end)

test "generated client reports missing path params" (function()
  local api = load_client()
  local instance = api.new({ request = function(opts) return opts end })
  test.assert_error(function() instance:users_get() end, "missing path param `id`", "missing id")
end)

test.run()
