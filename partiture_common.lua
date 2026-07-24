local common = {
  server_output = "dist/server",
  dev = {
    input = "fixtures/apps/showcase-service/src/main.lua",
    graph_output = ".meteorite/graph/current",
  },
}

function common.dev_build_command()
  return table.concat({
    "zig build",
    "-Dgraph-input=" .. common.dev.input,
    "-Dgraph-output=" .. common.dev.graph_output,
    "-Dmode=hybrid_dev",
    "-Dbackend=std_http",
    "-Dhybrid-profile=optimized",
    "-Drouter-dispatch=param_matchers",
    "install-server -- " .. common.server_output,
  }, " ")
end

function common.dev_refresh_command()
  return "METEORITE_DEV_ONCE=1 METEORITE_BUILD_COMMAND='"
    .. common.dev_build_command()
    .. "' ./.moonstone/env/bin/lua src/cli/dev.lua "
    .. common.dev.input
    .. " "
    .. common.dev.graph_output
    .. " hybrid_dev"
end

function common.dev_watch_sources(p)
  return {
    application = p.source.files({ "**/*.lua" }, {
      root = "fixtures/apps/showcase-service/src",
    }),
    framework = p.source.files({ "**/*.lua" }, { root = "src" }),
    compiler = p.source.directory("zig"),
    configuration = p.source.files({ "build.zig", "moonstone.toml" }, {
      root = ".",
    }),
  }
end

function common.dev_watch_options()
  return {
    cleanup = "scripts/guard.sh cleanup >/dev/null 2>&1 || true; scripts/guard.sh cleanup-sessions >/dev/null 2>&1 || true",
    interval = 0.5,
    debounce = 0.15,
    once = os.getenv("BALLAD_WATCH_ONCE") == "1",
  }
end

function common.dev_bootstrap_command()
  return "METEORITE_GUARD_EXCLUDE_PID=$PPID scripts/guard.sh handoff && " .. common.dev_refresh_command()
end

return common
