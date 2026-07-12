package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local m = require("meteorite")
local route = require("core.route")
local manifest = require("ballad.release_manifest")
local test = require("test")

local function build_ipc_manifest()
  local app = m.app({ name = "release-manifest" })
  app:message("users.get", {
    metadata = { id = m.u64() },
  }, function(ctx)
    return ctx:json({ id = tonumber(ctx:metadata("id")) })
  end)
  local graph = route.normalize_app(app, { mode = "dev" })
  return manifest.build({ graph = graph, graph_hash = "b3:test" }, "hybrid", "bin/server", {
    retained_lua_nodes = {},
    validation_mode = "hybrid",
    requires_target_lua = false,
  }, nil, {
    backend = "ipc_unixsocket",
    unix_socket_path = "/tmp/meteorite-release-test.sock",
    unix_socket_mode = "0660",
    unix_socket_unlink_stale = true,
  })
end

test "ipc release manifest records backend transport protocol and socket config" (function()
  local encoded = build_ipc_manifest()
  test.assert_true(encoded:find('"name":"ipc_unixsocket"', 1, true) ~= nil, "backend name")
  test.assert_true(encoded:find('"transport":"unix"', 1, true) ~= nil, "unix transport")
  test.assert_true(encoded:find('"protocol":"meteorite.ipc.v0"', 1, true) ~= nil, "ipc protocol")
  test.assert_true(encoded:find('"path":"/tmp/meteorite-release-test.sock"', 1, true) ~= nil, "socket path")
  test.assert_true(encoded:find('"mode":"0660"', 1, true) ~= nil, "socket mode")
  test.assert_true(encoded:find('"unlink_stale":true', 1, true) ~= nil, "socket stale unlink")
end)

test "ipc release manifest records native message metadata without handler source paths" (function()
  local encoded = build_ipc_manifest()
  test.assert_true(encoded:find('"messages":{"count":1', 1, true) ~= nil, "message count")
  test.assert_true(encoded:find('"name":"users.get"', 1, true) ~= nil, "message name")
  test.assert_true(encoded:find('"source":"message"', 1, true) ~= nil, "message source class")
  test.assert_false(encoded:find('handler', 1, true) ~= nil, "handler source should not be serialized")
  test.assert_false(encoded:find(debug.getinfo(1, "S").source:gsub("^@", ""), 1, true) ~= nil, "test path should not be serialized")
end)

test "ipc release manifest exposes native capabilities" (function()
  local encoded = build_ipc_manifest()
  test.assert_true(encoded:find('"ipc_metadata":true', 1, true) ~= nil, "ipc metadata capability")
  test.assert_true(encoded:find('"http_headers":false', 1, true) ~= nil, "http headers disabled")
  test.assert_true(encoded:find('"cookies":false', 1, true) ~= nil, "cookies disabled")
  test.assert_true(encoded:find('"cors":false', 1, true) ~= nil, "cors disabled")
  test.assert_true(encoded:find('"static_files":false', 1, true) ~= nil, "static files disabled")
end)

test "http over unix socket release manifest keeps HTTP capabilities" (function()
  local app = m.app({ name = "release-manifest-http-uds" })
  app:get("/health", function(ctx) return ctx:text("ok") end)
  local graph = route.normalize_app(app, { mode = "dev" })
  local encoded = manifest.build({ graph = graph, graph_hash = "b3:http-uds" }, "hybrid", "bin/server", {
    retained_lua_nodes = {},
    validation_mode = "hybrid",
    requires_target_lua = false,
  }, nil, {
    backend = "ipc_unixsocket_http",
    unix_socket_path = "/tmp/meteorite-http-release-test.sock",
    unix_socket_mode = "0660",
    unix_socket_unlink_stale = true,
  })
  test.assert_true(encoded:find('"name":"ipc_unixsocket_http"', 1, true) ~= nil, "backend name")
  test.assert_true(encoded:find('"transport":"unix"', 1, true) ~= nil, "unix transport")
  test.assert_true(encoded:find('"protocol":"http/1.1"', 1, true) ~= nil, "http protocol")
  test.assert_true(encoded:find('"path":"/tmp/meteorite-http-release-test.sock"', 1, true) ~= nil, "socket path")
  test.assert_true(encoded:find('"http_headers":true', 1, true) ~= nil, "http headers enabled")
  test.assert_true(encoded:find('"cookies":true', 1, true) ~= nil, "cookies enabled")
  test.assert_true(encoded:find('"cors":true', 1, true) ~= nil, "cors enabled")
  test.assert_true(encoded:find('"redirects":true', 1, true) ~= nil, "redirects enabled")
  test.assert_true(encoded:find('"static_files":true', 1, true) ~= nil, "static files enabled")
  test.assert_true(encoded:find('"ipc_metadata":false', 1, true) ~= nil, "native ipc metadata disabled")
end)

test.run()
