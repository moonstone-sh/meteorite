---@class MeteoriteDevPartitureConfig
---@field input string Lua service entrypoint compiled by the development refresh.
---@field graph_output string Generated Meteorite graph directory.

---@class MeteoriteDevWatchSources
---@field application NodeHandle Lua application source files.
---@field framework NodeHandle Meteorite Lua compiler source files.
---@field compiler NodeHandle Meteorite Zig compiler source tree.
---@field configuration NodeHandle Build and Moonstone manifest files.

---@class MeteoritePartitureCommon
---@field server_output string Development and materialization server output path.
---@field dev MeteoriteDevPartitureConfig Shared development entrypoint and graph destination.
local common = {
  server_output = "dist/server",
  dev = {
    input = "fixtures/apps/showcase-service/src/main.lua",
    graph_output = ".meteorite/graph/current",
  },
}

---@return string command Deterministic Zig build command for the development server.
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

---@return string command One-shot Meteorite graph refresh command used by watcher effects.
function common.dev_refresh_command()
  return "METEORITE_DEV_ONCE=1 METEORITE_BUILD_COMMAND='"
    .. common.dev_build_command()
    .. "' ./.moonstone/env/bin/lua src/cli/dev.lua "
    .. common.dev.input
    .. " "
    .. common.dev.graph_output
    .. " hybrid_dev"
end

---@param p PipelineContext
---@return MeteoriteDevWatchSources sources Named source nodes shared by watcher reactions.
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

---@return WatcherOptions options Polling, debounce, cleanup, and CI once-mode configuration.
function common.dev_watch_options()
  return {
    cleanup = "scripts/guard.sh cleanup >/dev/null 2>&1 || true; scripts/guard.sh cleanup-sessions >/dev/null 2>&1 || true",
    interval = 0.5,
    debounce = 0.15,
    once = os.getenv("BALLAD_WATCH_ONCE") == "1",
  }
end

---@return string command Guard handoff followed by the initial Meteorite refresh.
function common.dev_bootstrap_command()
  return "METEORITE_GUARD_EXCLUDE_PID=$PPID scripts/guard.sh handoff && " .. common.dev_refresh_command()
end

return common
