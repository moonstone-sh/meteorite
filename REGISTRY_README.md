# Meteorite

Meteorite is a Lua-first service compiler for Moonstone projects. You describe
routes and handlers in a small Lua surface; Meteorite produces an inspectable
service graph, generates the Zig bindings and server plan, then compiles a
bounded native service.

## Install

### Global CLI

Use a global tool when you want `meteorite init` available before a project
exists. The generated project then declares its own Meteorite and Ballad tools.

```sh
moon add --global --tool moonstone/meteorite
moon exec --global meteorite init my-service --hybrid
cd my-service
moon run dev
```

### Project-local CLI

Use an empty Moonstone project when the generator should stay inside that
project’s locked tool closure:

```sh
mkdir my-service
cd my-service
moon init . --empty --name my-service
moon add --tool moonstone/meteorite
moon exec meteorite init . --hybrid
moon run dev
```

`moon init --empty` creates only `moonstone.toml`: no placeholder application
files, no starter scripts. Meteorite then owns the application scaffold while
Moonstone owns the isolated tool environment.

## From Lua surface to native service

```mermaid
flowchart LR
  Lua[Lua routes and handlers] -->|analyze| Graph[Inspectable service graph]
  Graph -->|generate plan + bindings| Zig[Zig server source]
  Zig -->|compile selected profile| Binary[Native service binary]
  Binary -->|serve requests| Service[Bounded HTTP service]
  LuaChange[Lua or route change] -. rebuilds graph .-> Graph

  classDef lua fill:#1d4ed8,stroke:#93c5fd,color:#eff6ff
  classDef graph fill:#7c3aed,stroke:#c4b5fd,color:#f5f3ff
  classDef native fill:#047857,stroke:#6ee7b7,color:#ecfdf5
  classDef service fill:#b45309,stroke:#fcd34d,color:#fffbeb
  class Lua,LuaChange lua
  class Graph graph
  class Zig,Binary native
  class Service service
```

The graph is the handoff: it makes the route shape, handlers, generated Zig,
and selected release profile inspectable before the service runs. Use
`moon run build` for a production build and `moon exec meteorite doctor` to
check the project/tool setup. The repository includes fixture apps, benchmarks,
backend notes, and release-contract details for contributors.
