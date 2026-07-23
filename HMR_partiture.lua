local ballad = require("ballad")

return ballad.partiture(function(p)
  local watcher = p:use(ballad.plugins.watcher)
  local input = "fixtures/apps/showcase-service/src/main.lua"
  local output = ".meteorite/graph/current"
  local build = "zig build -Dgraph-input=" .. input .. " -Dgraph-output=" .. output .. " -Dmode=hybrid_dev -Dbackend=std_http -Dhybrid-profile=optimized -Drouter-dispatch=param_matchers install-server -- dist/server"
  local refresh = "METEORITE_DEV_ONCE=1 METEORITE_BUILD_COMMAND='" .. build .. "' ./.moonstone/env/bin/lua src/cli/dev.lua " .. input .. " " .. output .. " hybrid_dev"
  local application = p.source.directory("fixtures/apps/showcase-service/src")
  local compiler = p.source.directory("zig")

  local session = watcher.watch({
    initial = {
      label = "Meteorite bootstrap",
      inputs = { "fixtures/apps/showcase-service/src/**/*.lua", "src/**/*.lua", "zig/**", "build.zig", "moonstone.toml" },
      depends_on = { application, compiler },
      outputs = { output, "dist/server" },
      effect = "METEORITE_GUARD_EXCLUDE_PID=$PPID scripts/guard.sh handoff && " .. refresh,
    },
    reactions = {
      {
        label = "application Lua",
        inputs = { "fixtures/apps/showcase-service/src/**/*.lua" },
        depends_on = { application },
        outputs = { output, "dist/server" },
        effect = refresh,
      },
      {
        label = "Meteorite compiler",
        inputs = { "src/**/*.lua", "zig/**", "build.zig", "moonstone.toml" },
        depends_on = { compiler },
        outputs = { output, "dist/server" },
        effect = refresh,
      },
    },
    options = {
      cleanup = "scripts/guard.sh cleanup >/dev/null 2>&1 || true; scripts/guard.sh cleanup-sessions >/dev/null 2>&1 || true",
      interval = 0.5,
      debounce = 0.15,
      once = os.getenv("BALLAD_WATCH_ONCE") == "1",
    },
  })

  p.sink.none(session)
end)
