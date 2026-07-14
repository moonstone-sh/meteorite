package.path = "src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;tests/?.lua;;"

local test = require("test")
local release_contract = require("ballad.release_contract")

local retained_lua_contract = {
  validation_mode = "hybrid",
  requires_target_lua = true,
  retained_lua_nodes = {
    { kind = "inline route handler", label = "GET /health", source = "src/main.lua:1:1" },
  },
}

local function ctx()
  return {
    fail = function(message) error(message, 0) end,
  }
end

test "cross-target LuaJIT fails with explicit diagnostic" (function()
  test.assert_error(function()
    release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
      target = "aarch64-linux-gnu",
      runtime = { kind = "luajit", version = "2.1" },
      runtime_source = "/tmp/not-used-for-luajit.tar.gz",
      runtime_source_kind = "luajit_source",
    })
  end, "cannot cross-compile LuaJIT yet", "luajit diagnostic")
end)

test "cross-target LuaJIT diagnostic mentions buildvm" (function()
  local ok, err = pcall(function()
    release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
      target = "x86_64-linux-gnu",
      runtime = { implementation = "LuaJIT" },
      lua_source = "/tmp/not-used-for-luajit.tar.gz",
      lua_source_kind = "source",
    })
  end)
  test.assert_false(ok, "expected LuaJIT rejection")
  test.assert_true(tostring(err):find("buildvm", 1, true) ~= nil, "mentions buildvm")
  test.assert_true(tostring(err):find("PUC Lua", 1, true) ~= nil, "mentions PUC Lua alternative")
end)

test "same-host LuaJIT hybrid does not require cross-target rebuild" (function()
  local result = release_contract.validate_target_lua(ctx(), ".", retained_lua_contract, {
    target = "native",
    runtime = { kind = "luajit", version = "2.1" },
  })
  test.assert_eq(result.status, "host_env", "same-host status")
end)

test.run()
