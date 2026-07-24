local ballad = require("ballad")
local common = require("partiture_common")

return ballad.partiture(function(p)
  local watcher = p:use(ballad.plugins.watcher)
  local sources = common.dev_watch_sources(p)
  local build = common.dev_build_action(p)

  local session = watcher.watch({
    initial = {
      label = "Meteorite bootstrap",
      before = common.dev_bootstrap_command(),
      run = build,
      effect = common.dev_server_command(),
    },
    reactions = {
      {
        label = "application Lua",
        watch = { sources.application },
        run = build,
        effect = common.dev_server_command(),
      },
      {
        label = "Meteorite compiler",
        watch = { sources.framework, sources.compiler, sources.configuration },
        run = build,
        effect = common.dev_server_command(),
      },
    },
    options = common.dev_watch_options(),
  })

  p.sink.none(session)
end)
