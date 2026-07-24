local ballad = require("ballad")
local common = require("partiture_common")

return ballad.partiture(function(p)
  local watcher = p:use(ballad.plugins.watcher)
  local sources = common.dev_watch_sources(p)
  local refresh = common.dev_refresh_command()

  local session = watcher.watch({
    initial = {
      label = "Meteorite bootstrap",
      outputs = { common.dev.graph_output, common.server_output },
      effect = common.dev_bootstrap_command(),
    },
    reactions = {
      {
        label = "application Lua",
        watch = { sources.application },
        outputs = { common.dev.graph_output, common.server_output },
        effect = refresh,
      },
      {
        label = "Meteorite compiler",
        watch = { sources.framework, sources.compiler, sources.configuration },
        outputs = { common.dev.graph_output, common.server_output },
        effect = refresh,
      },
    },
    options = common.dev_watch_options(),
  })

  p.sink.none(session)
end)
