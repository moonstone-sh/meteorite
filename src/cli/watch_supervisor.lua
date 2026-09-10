-- Preflight for the repository's Ballad watcher, which owns rebuild decisions.
local process = require("clingy.process")
assert(process.supervisor_script, "Meteorite watch requires Clingy >= 0.5.0; run moon sync")
local argv = { "moon", "exec", "ballad", "--", "play", "Watch_partiture.lua", "--" }
for _, value in ipairs(arg) do argv[#argv + 1] = value end
local script = process.supervisor_script({
  argv = argv,
  label = "Meteorite watch",
  stdin_eof = true,
  lock_dir = ".meteorite/dev/session.lock",
  cleanup_files = { ".meteorite/dev/server.pid" },
})
local ok = os.execute("mkdir -p .meteorite/dev")
assert(ok == true or ok == 0, "cannot create Meteorite dev state directory")
local file = assert(io.open(".meteorite/dev/watch-supervisor.sh", "w"))
assert(file:write(script))
assert(file:close())
