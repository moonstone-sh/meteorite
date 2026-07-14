package.path = "src/?.lua;src/?/init.lua;tests/?.lua;fixtures/apps/web-standards/src/?.lua;;" .. package.path

local test = require("test")
local route_mod = require("core.route")
local routes_cli = require("cli.routes")
local app = require("fixtures/apps/web-standards/src/app")

local normalized = route_mod.normalize_app(app, { mode = "dev" })
local graph = routes_cli.to_graph(normalized)

local function find_route(method, path)
  for _, route in ipairs(graph.routes or {}) do
    if route.method == method and route.path == path then return route end
  end
  return nil
end

test "routes graph snapshot has stable envelope" (function()
  test.assert_eq(graph.format, "meteorite.routes.v0", "format")
  test.assert_true(type(graph.routes) == "table", "routes table")
  test.assert_true(#graph.routes > 20, "web standards routes included")
  test.assert_true(type(graph.messages) == "table", "messages table")
end)

test "validation route exposes schema and runtime facts" (function()
  local route = assert(find_route("POST", "/validation/contracts/:id"), "missing validation route")
  test.assert_eq(route.handler_kind, "inline_lua", "handler kind")
  test.assert_eq(route.source_form, "legacy_signature", "source form")
  test.assert_true(route.runtime.requires_lua, "requires Lua runtime")
  test.assert_eq(route.params[1].name, "id", "param name")
  test.assert_eq(route.params[1].type, "u64", "param type")
  test.assert_eq(route.query[1].name, "verbose", "query name")
  test.assert_eq(route.query[1].type, "bool", "query type")
  test.assert_eq(route.query[1].optional, true, "query optional")
  test.assert_eq(route.validation.headers[1].name, "x-meteorite-token", "header validator")
  test.assert_eq(route.validation.cookies[1].name, "session", "cookie validator")
  test.assert_eq(route.validation.json_body[1].name, "email", "json validator")
  test.assert_eq(route.validation.form_body[1].name, "csrf", "form validator")
  test.assert_eq(route.responses[1], "200", "response status key")
  test.assert_eq(route.scope.id, "root", "scope id")
  test.assert_eq(route.has_pipeline, false, "legacy routes omit explicit pipeline snapshot")
  test.assert_eq(route.pipeline, nil, "legacy pipeline omitted")
end)

test "canonical pipeline route exposes stage snapshot" (function()
  local route = assert(find_route("GET", "/middleware/post-header"), "missing canonical route")
  test.assert_eq(route.source_form, "canonical", "source form")
  test.assert_eq(route.has_pipeline, true, "has pipeline")
  test.assert_eq(#route.pipeline, 2, "stage count")
  test.assert_eq(route.pipeline[1].id, "post_header_handle", "handler stage id")
  test.assert_eq(route.pipeline[1].kind, "handle", "handler stage kind")
  test.assert_eq(route.pipeline[1].strat, "zig", "handler stage strat")
  test.assert_eq(route.pipeline[1].symbol, "response_post_header_base", "handler symbol")
  test.assert_eq(route.pipeline[2].id, "post_header_hook", "hook stage id")
  test.assert_eq(route.pipeline[2].kind, "hook", "hook stage kind")
  test.assert_eq(route.pipeline[2].phase, "post_handler", "hook phase")
  test.assert_eq(route.pipeline[2].strat, "zig", "hook strat")
  test.assert_eq(route.pipeline[2].symbol, "response_post_header_hook", "hook symbol")
  test.assert_eq(route.pipeline[2].may_short_circuit, false, "hook short circuit flag")
end)

test.run()
