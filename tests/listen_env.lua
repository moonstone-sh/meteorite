package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local m = require("meteorite")
local test = require("test")

-- A built server's address is fixed at build time unless the app names
-- environment variables to read at start-up (zig/main.zig applyListenEnv).

local function graph_for(options)
  local app = m.app(options)
  app:get("/", "handlers.ok")
  return app:normalize({ mode = "release-static" })
end

test "listen keeps the declared address and no env names by default" (function()
  local graph = graph_for({ name = "plain", host = "127.0.0.1", port = 9001 })
  test.assert_eq(graph.listen.port, 9001, "declared port")
  test.assert_eq(graph.listen.port_env, nil, "no port_env unless declared")
  test.assert_eq(graph.listen.host_env, nil, "no host_env unless declared")
end)

test "listen carries opted-in env variable names" (function()
  local graph = graph_for({ name = "env", port = 8080, port_env = "PORT", host_env = "HOST" })
  test.assert_eq(graph.listen.port, 8080, "declared port is still the default")
  test.assert_eq(graph.listen.port_env, "PORT", "port_env")
  test.assert_eq(graph.listen.host_env, "HOST", "host_env")
end)

test "listen rejects env names that are not variable names" (function()
  test.assert_error(function() graph_for({ name = "bad", port_env = "PORT=1" }) end,
    "port_env must be an environment variable name", "invalid port_env")
  test.assert_error(function() graph_for({ name = "bad2", host_env = 7 }) end,
    "host_env must be an environment variable name", "invalid host_env")
end)

test.run()
