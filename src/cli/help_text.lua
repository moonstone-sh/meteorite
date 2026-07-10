--- Help text templates for meteorite CLI commands.
--- Extracted from main.lua to keep command dispatch readable.

local help = {}

help.main = [[Meteorite

Usage:
  meteorite <command> [args]

Commands:
  init      Create or adapt a Meteorite app
  dev       Run graph-aware live reload
  build     Build the server with Meteorite's packaged Zig driver
  graph     Generate the Meteorite graph
  doctor    Check local project/tool readiness
  invoke    Invoke a route in-process for diagnostics

Examples:
  meteorite init my-app
  meteorite init my-app --static
  meteorite init my-app --hybrid
  meteorite dev
  meteorite build --mode hybrid
  meteorite build --mode release-static
  meteorite doctor

Run `meteorite help <command>` for command-specific help.]]

help.init = [[Meteorite init

Usage:
  meteorite init [path] [flags]

Flags:
  --minimal             Create the default Lua-first hybrid app
  --static              Create a pure Zig-handler app; build mode release-static
  --hybrid              Create a mixed Lua + Zig handler app
  --template <name>     One of: minimal, static, hybrid, middleware, cors, json-api, static-site
  --with-zig            Add central zig/handlers.zig and zig/validators.zig scaffolding
  --name <name>         Override package/app name
  --force               Overwrite generated files
  --no-sync             Do not run moon sync after init

Examples:
  meteorite init my-app
  meteorite init my-app --static
  meteorite init . --hybrid --no-sync]]

help.build = [[Meteorite build

Usage:
  meteorite build [--mode <mode>] [zig build args...]

Modes:
  hybrid          Include Lua runtime for inline/module Lua handlers
  release-static  Require Zig/static handlers only; no Lua runtime in output

Examples:
  meteorite build
  meteorite build --mode hybrid
  meteorite build --mode release-static
  meteorite build --mode hybrid -Dtarget=aarch64-linux-gnu]]

help.dev = [[Meteorite dev

Usage:
  meteorite dev

Runs the graph-aware live reload loop:
  - regenerates graph on source changes
  - reloads Lua-only edits in-process
  - rebuilds for route shape, Zig, or build-affecting changes
  - keeps the previous server alive on graph/build failure

Environment:
  METEORITE_DEV_PORT  Port for the dev server, default 8080]]

help.graph = [[Meteorite graph

Usage:
  meteorite graph [input] [output] [mode]

Defaults:
  input   src/main.lua
  output  .meteorite/graph/current
  mode    release-static

Examples:
  meteorite graph src/main.lua .meteorite/graph/current hybrid
  meteorite graph src/main.lua .meteorite/graph/release release-static]]

help.doctor = [[Meteorite doctor

Usage:
  meteorite doctor

Checks:
  - Moonstone project shape
  - src/main.lua
  - Moonstone env and Lua runtime
  - Meteorite CLI visibility
  - Zig availability
  - Ballad plugin visibility
  - generated graph/aids presence
  - static/hybrid release readiness
  - dev port listener state]]

help.invoke = [[Meteorite invoke

Usage:
  meteorite invoke [--json] [-H "Name: value"] [input] [method] [path] [body]

Example:
  meteorite invoke src/main.lua GET /health
  meteorite invoke --json -H "Origin: https://app.example" src/main.lua GET /security/cors]]

return help
