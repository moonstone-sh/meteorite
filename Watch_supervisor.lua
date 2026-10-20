require("moonstone.variants").install()
local process = require("clingy.process")
local platform = require("clingy.platform")
local argv = { "moon", "exec", "--", "ballad", "play", "Watch_partiture.lua", "--" }
for _, value in ipairs(arg) do argv[#argv + 1] = value end
local script = process.supervisor_script({
  argv = argv, label = "Meteorite watch", stdin_eof = true,
  lock_dir = ".meteorite/dev/session.lock",
  cleanup_files = { ".meteorite/dev/server.pid" },
})
platform.mkdir(".meteorite/dev")
local path = ".meteorite/dev/watch-supervisor" .. process.supervisor_extension()
local file = assert(io.open(path, "wb"))
assert(file:write(platform.windows and "\239\187\191" .. script or script)); assert(file:close())
local code = require("clingy.compat").exit_status(os.execute(process.supervisor_command(path)))
os.exit(code)
