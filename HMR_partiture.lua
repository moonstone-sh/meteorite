local ballad = require("ballad")
local common = require("partiture_common")

return ballad.partiture(function(p)
  local watcher = p:use(ballad.plugins.watcher)
  local request = common.request(p)
  local sources = common.dev_watch_sources(p)
  local build = common.dev_build_action(p, request)

  local session = watcher.watch({
    initial = {
      label = "Meteorite bootstrap",
      before = common.dev_bootstrap_command(),
      run = build,
      effect = common.dev_server_command(request),
    },
    reactions = {
      {
        label = "application Lua",
        watch = { sources.application },
        run = build,
        effect = common.dev_server_command(request),
      },
      {
        label = "Meteorite compiler",
        watch = { sources.framework, sources.compiler, sources.configuration },
        run = build,
        effect = common.dev_server_command(request),
      },
    },
    options = common.dev_watch_options(),
  })

  p.sink.none(session)
end)
