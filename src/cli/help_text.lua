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
  client    Generate client code from the route graph
  openapi   Generate OpenAPI-adjacent static assets
  ipc       Send native IPC messages over UNIX sockets

Examples:
  meteorite init my-app
  meteorite init my-app --static
  meteorite init my-app --hybrid
  meteorite dev
  meteorite build --mode hybrid
  meteorite build --mode release-static
  meteorite doctor
  meteorite client lua src/main.lua .meteorite/client.lua
  meteorite openapi swagger-ui public/docs.html ./openapi.json
  meteorite ipc send --socket /tmp/meteorite.sock --message health.get

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
  meteorite build [--mode <mode>] [--backend <backend>] [zig build args...]

Modes:
  hybrid          Include Lua runtime for inline/module Lua handlers
  release-static  Require Zig/static handlers only; no Lua runtime in output

Backends:
  fast_http            High-performance HTTP backend
  std_http             Zig std HTTP backend
  ipc_unixsocket       Native Meteorite IPC over UNIX sockets
  ipc_unixsocket_http  HTTP/1.1 over UNIX sockets (planned)

Unix socket flags:
  --unix-socket-path <path>
  --unix-socket-mode <mode>
  --unix-socket-unlink-stale
  --no-unix-socket-unlink-stale

Examples:
  meteorite build
  meteorite build --mode hybrid
  meteorite build --backend ipc_unixsocket
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
  meteorite invoke [--json] [--headers] [-H "Name: value"] [input] [method] [path] [body]

Flags:
  --json       Print structured JSON with request and response details
  --headers    Print response headers after the status/content-type/body line
  -H, --header "Name: value"  Add a request header (repeatable)
  --body <text>               Set the request body

Example:
  meteorite invoke src/main.lua GET /health
  meteorite invoke --headers src/main.lua GET /security/cors
  meteorite invoke --json -H "Origin: https://app.example" src/main.lua GET /security/cors]]

help.client = [[Meteorite client

Usage:
  meteorite client lua [input] [output]

Targets:
  lua    Generate a transport-agnostic Lua client module

Examples:
  meteorite client lua src/main.lua .meteorite/client.lua]]

help.openapi = [[Meteorite OpenAPI

Usage:
  meteorite openapi swagger-ui [output] [spec-url]

Commands:
  swagger-ui  Write a static Swagger UI HTML asset that loads openapi.json

Examples:
  meteorite openapi swagger-ui public/docs.html ./openapi.json]]

help.ipc = [[Meteorite IPC

Usage:
  meteorite ipc send --socket <path> --message <name> [flags]
  meteorite ipc send --socket <path> --route users/get [flags]
  meteorite ipc send --socket <path> --method GET --path /users/123 [flags]
  meteorite ipc stats --socket <path>
  meteorite ipc inspect --socket <path>

Flags:
  --json                       Print structured JSON
  --body <text>                Send a request body
  --body-file <path>           Read request body from a file
  --content-type <type>        Add content_type IPC metadata
  --metadata key=value         Add IPC metadata; repeatable

Notes:
  --message sends an exact native message name such as users.get.
  --route normalizes slash form like users/get to users.get for local tooling.
  --method/--path sends an explicit compatibility target such as GET /users/123.

Examples:
  meteorite ipc send --socket /tmp/meteorite.sock --message health.get
  meteorite ipc send --socket /tmp/meteorite.sock --route users/get --metadata id=42
  meteorite ipc send --socket /tmp/meteorite.sock --message users.create --content-type application/json --body '{"id":7,"name":"alice"}' --json
  meteorite ipc stats --socket /tmp/meteorite.sock
  meteorite ipc inspect --socket /tmp/meteorite.sock]]

return help
