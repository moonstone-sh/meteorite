package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local help = require("cli.help_text")
local test = require("test")

test "build help lists implemented unix socket HTTP backend" (function()
  test.assert_true(help.build:find("ipc_unixsocket_http  HTTP/1.1 over UNIX sockets", 1, true) ~= nil, "backend label")
  test.assert_false(help.build:find("ipc_unixsocket_http  HTTP/1.1 over UNIX sockets (planned)", 1, true) ~= nil, "not planned")
end)

test "build help requires explicit behavior" (function()
  test.assert_true(help.build:find("build --mode <mode> --backend <backend>", 1, true) ~= nil, "build usage")
  test.assert_true(help.check:find("without producing a", 1, true) ~= nil, "check help")
end)

test.run()
