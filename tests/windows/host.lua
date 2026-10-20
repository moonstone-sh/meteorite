if arg[1] == "--child" then print("quoted launcher"); return end
local root = assert(os.getenv("METEORITE_TEST_ROOT"))
local clingy = assert(os.getenv("CLINGY_TEST_ROOT"))
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. clingy .. "/src/?.lua;" .. clingy .. "/src/?/init.lua;" .. package.path
require("moonstone.variants").install()
local shell = require("cli.shell")
local host = require("cli.dev_host")
assert(shell.windows)
local output = shell.capture(shell.quote("lua") .. " " .. shell.quote(root .. "/tests/windows/host.lua") .. " --child")
assert(output:find("quoted launcher", 1, true), output)
local fingerprint = host.fingerprint({root .. "/src/cli/main.lua"}, {})
assert(fingerprint:match("|%x%x%x%x%x%x%x%x"), fingerprint)
print("PASS: Windows quoted executable capture and source fingerprint")
