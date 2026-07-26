local ballad = require("ballad")
local common = require("partiture_common")

---Finite companion to Watch_partiture.lua.
---It materializes exactly the same dev-server action, so a previous watcher run
---can satisfy this graph from Ballad's local action cache and vice versa.
return ballad.partiture(function(p)
  local request = common.request(p)
  local build = common.dev_build_action(p, request)
  p.sink.none(p.task.run(build, {
    label = "Meteorite development build",
  }))
end)
