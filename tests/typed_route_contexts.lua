package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;" .. package.path

local test = require("test")
local lifter = require("codegen.lifter")
local luals_aids = require("codegen.luals_aids")

--- Regression coverage for two bugs where Meteorite's own generated code did
--- not work against Meteorite's own runtime:
---
--- Bug 1: `luals_aids.lua` typed a `u64` param as `integer` and a `bool` query
---        field as `boolean`, but the runtime pushed every request value with
---        `lua_pushlstring`, so handlers actually received strings and
---        `c.params.id == 42` was false.
---
--- Bug 2: `luals_aids.lua` generates every typed route overload as
---        `fun(c: MeteoriteContext_<route>)`, and `lifter.lua` maps a first
---        parameter named `c` to the `lazy_context` calling convention, which
---        pushed no `params` table at all. A handler written exactly the way
---        the generated types instruct returned HTTP 500 with
---        "attempt to index field 'params' (a nil value)".
---
--- A green suite missed both, so these tests pin the contract from both ends:
--- the name codegen emits must select a params-bearing convention, and the
--- declared schema type must match what the runtime coerces to.

local function mkdir_p(path)
  os.execute("mkdir -p " .. string.format("%q", path))
end

local function write_file(path, content)
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
end

local function read_file(path)
  local file = assert(io.open(path, "rb"), "cannot read " .. path)
  local data = file:read("*a")
  file:close()
  return data
end

local function temp_root()
  local root = os.tmpname()
  os.remove(root)
  mkdir_p(root .. "/.meteorite/graph/current")
  return root
end

--- Lift an inline handler declared with `params_src` as its parameter list and
--- report the calling convention the lifter selected for it.
local function arg_mode_for(params_src, route_params)
  local root = temp_root()
  local source = root .. "/handler.lua"
  write_file(source, "return function(" .. params_src .. ") return nil end\n")
  local handler = assert(loadfile(source))()
  local lifted = lifter.lift({
    id = "route_1",
    method = "GET",
    raw_path = "/users/:id",
    params = route_params or { { name = "id", type = "u64" } },
    source = { file = source, line = 1, column = 1 },
    handler = { value = handler },
  }, { output = root .. "/.meteorite/graph/current" })
  return lifted.arg_mode
end

--- Emit the LuaLS aids for `graph` and return the generated files.
local function emit_aids(graph)
  local root = temp_root()
  luals_aids.emit(graph, root .. "/.meteorite/graph/current")
  return {
    meteorite = read_file(root .. "/.meteorite/aids/lua/meteorite.lua"),
    routes = read_file(root .. "/.meteorite/aids/lua/routes.meta.lua"),
  }
end

--- Slice one top-level Zig function out of a source file. Top-level functions
--- close with `}` in column zero, so that terminator delimits the body.
local function zig_function(source, name)
  local start = assert(source:find("fn " .. name .. "%("), "missing fn " .. name)
  local stop = assert(source:find("\n}", start, true), "unterminated fn " .. name)
  return source:sub(start, stop + 1)
end

local lua_context_src = read_file("zig/bridge/lua_context.zig")

-- Bug 2 ---------------------------------------------------------------------

test "context parameter names select the context calling convention" (function()
  for _, name in ipairs({ "c", "ctx", "context" }) do
    test.assert_eq(arg_mode_for(name), "lazy_context", name .. " selects lazy_context")
  end
end)

test "the parameter name codegen generates selects a params-bearing convention" (function()
  -- This is the exact coupling that broke: luals_aids picks the handler
  -- parameter name in the overloads it generates, and lifter decides the
  -- calling convention from that name. If either side changes independently,
  -- the framework's own generated pattern fails at runtime. Read the name back
  -- out of real generated output rather than hardcoding it here.
  local aids = emit_aids({
    routes = {
      { id = "route_1", method = "GET", raw_path = "/users/:id",
        params = { { name = "id", type = "u64" } }, query = {} },
    },
  })
  local generated_name = aids.meteorite:match("handler: fun%((%a[%w_]*):%s*MeteoriteContext_")
  test.assert_true(generated_name ~= nil, "generated overload names its context parameter")
  test.assert_eq(arg_mode_for(generated_name), "lazy_context",
    "generated parameter name '" .. tostring(generated_name) .. "' selects lazy_context")
end)

test "other documented calling conventions still dispatch as documented" (function()
  test.assert_eq(arg_mode_for("req"), "request_table", "req selects request_table")
  test.assert_eq(arg_mode_for("request"), "request_table", "request selects request_table")
  test.assert_eq(arg_mode_for(""), "no_args", "no parameters selects no_args")
  test.assert_eq(arg_mode_for("id"), "direct_params", "matching arity selects direct_params")
end)

test "lazy context pushes the declared params and query tables" (function()
  -- The runtime half of Bug 2: this convention previously discarded ctx
  -- entirely and pushed methods only, so `c.params` was nil.
  local body = zig_function(lua_context_src, "pushLazyContextTable")
  test.assert_true(body:find("pushParamsTable", 1, true) ~= nil, "lazy context builds params")
  test.assert_true(body:find("pushQueryTable", 1, true) ~= nil, "lazy context builds query")
end)

test "params table is always emitted so indexing it cannot fail" (function()
  local body = zig_function(lua_context_src, "pushParamsTable")
  test.assert_true(body:find('lua_setfield(L, -2, "params")', 1, true) ~= nil, "sets params field")
  -- Guarded on the context carrying captures at all, never on the route
  -- happening to declare params, so `c.params` is a table even for a
  -- parameterless route rather than nil.
  test.assert_true(body:find("captures", 1, true) ~= nil, "params come from path captures")
end)

-- Bug 1 ---------------------------------------------------------------------

test "schema kinds map to the Lua types the runtime coerces to" (function()
  test.assert_eq(luals_aids.lua_type_for("u64"), "integer", "u64 is an integer")
  test.assert_eq(luals_aids.lua_type_for("i32"), "integer", "i32 is an integer")
  test.assert_eq(luals_aids.lua_type_for("bool"), "boolean", "bool is a boolean")
  test.assert_eq(luals_aids.lua_type_for("string"), "string", "string stays a string")
  test.assert_eq(luals_aids.lua_type_for("uuid"), "string", "uuid stays a string")
end)

test "path params and query fields share one type mapping" (function()
  -- A `bool` path param used to be typed `string` while a `bool` query field
  -- was typed `boolean`, even though the runtime treats both identically.
  local aids = emit_aids({
    routes = {
      { id = "route_1", method = "GET", raw_path = "/f/:active",
        params = { { name = "active", type = "bool" }, { name = "id", type = "u64" } },
        query = { { name = "on", type = "bool" }, { name = "n", type = "i32" } } },
    },
  })
  test.assert_true(aids.routes:find("---@field active boolean", 1, true) ~= nil, "bool param is boolean")
  test.assert_true(aids.routes:find("---@field id integer", 1, true) ~= nil, "u64 param is integer")
  test.assert_true(aids.routes:find("---@field on boolean", 1, true) ~= nil, "bool query is boolean")
  test.assert_true(aids.routes:find("---@field n integer", 1, true) ~= nil, "i32 query is integer")
end)

test "optional query fields stay nilable in the generated types" (function()
  local aids = emit_aids({
    routes = {
      { id = "route_1", method = "GET", raw_path = "/q", params = {},
        query = { { name = "opt", type = "string", optional = true } } },
    },
  })
  test.assert_true(aids.routes:find("---@field opt string|nil", 1, true) ~= nil, "optional query is nilable")
end)

test "the runtime coerces validated values to their declared schema type" (function()
  local body = zig_function(lua_context_src, "pushSchemaValue")
  test.assert_true(body:find(".u64", 1, true) ~= nil, "handles u64")
  test.assert_true(body:find(".i32", 1, true) ~= nil, "handles i32")
  test.assert_true(body:find(".bool", 1, true) ~= nil, "handles bool")
  test.assert_true(body:find("lua_pushinteger", 1, true) ~= nil, "pushes real numbers")
  test.assert_true(body:find("lua_pushboolean", 1, true) ~= nil, "pushes real booleans")
end)

test "every request-value push path routes through schema coercion" (function()
  -- Params and query were verified to behave identically, so both must coerce;
  -- positional handlers receive the same values and must not diverge.
  for _, name in ipairs({ "pushParamValue", "pushQueryTable", "pushDirectParamArgs" }) do
    local body = zig_function(lua_context_src, name)
    test.assert_true(body:find("pushSchemaValue", 1, true) ~= nil, name .. " coerces by schema")
  end
end)

test "a missing optional query field is left unset so it reads back as nil" (function()
  -- The one part of the original behaviour that was already honest; keep it.
  local body = zig_function(lua_context_src, "pushQueryTable")
  test.assert_true(body:find("if (vtable.query(ctx, spec.name))", 1, true) ~= nil,
    "query fields are only set when actually present")
end)

test.run()
