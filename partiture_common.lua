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

---@return string command Deterministic Zig compilation command for the development server.
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

---@return string command Deterministic Meteorite graph generation command.
function common.dev_graph_command()
  return "./.moonstone/env/bin/lua src/cli/main.lua graph "
    .. common.dev.input
    .. " "
    .. common.dev.graph_output
    .. " hybrid_dev"
end

---@return string command Start or restart the development server after Ballad materializes its build products.
function common.dev_server_command()
  return "METEORITE_DEV_PREBUILT=1 METEORITE_DEV_ONCE=1 ./.moonstone/env/bin/lua src/cli/dev.lua "
    .. common.dev.input
    .. " "
    .. common.dev.graph_output
    .. " hybrid_dev"
end

---Declare the deterministic Meteorite build shared by finite and watch partitures.
---The action owns graph generation plus Zig compilation. Dev-server supervision is
---a separate post-build effect and intentionally never participates in this cache.
---@param p PipelineContext
---@return NativeAction action
function common.dev_build_action(p)
  return p.task.native({
    id = "meteorite.build-server.v1",
    tool = "sh",
    args = { "-c", common.dev_graph_command() .. " && " .. common.dev_build_command() },
    inputs = {
      "fixtures/apps/showcase-service/src/**/*.lua",
      "src/**/*.lua",
      "zig/**",
      "build.zig",
      "moonstone.toml",
      "moonstone.lock",
    },
    outputs = { common.dev.graph_output, common.server_output },
    toolchain = { command = "zig version" },
    description = "build Meteorite development server",
  })
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

---@return string command Guard handoff performed before the initial declared action.
function common.dev_bootstrap_command()
  return "METEORITE_GUARD_EXCLUDE_PID=$PPID scripts/guard.sh handoff"
end

return common
