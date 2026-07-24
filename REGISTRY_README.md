# Meteorite

Meteorite is a Lua-first service compiler for Moonstone projects. It analyzes
routes and handlers, generates a Zig server, and keeps the generated graph
inspectable for development and release work.

## Install

```sh
moon add moonstone/meteorite --tool
moon exec meteorite help
```

## Start a project

```sh
moon exec meteorite init my-service --hybrid
cd my-service
moon sync
moon run dev
```

The generated project keeps application routes in Lua while Meteorite produces
the server graph and Zig bindings. Use `moon run build` for a production build
and `moon exec meteorite doctor` to check the project/tool setup.

## Release shape

Meteorite favors bounded, inspectable work: route declarations become a graph,
the graph drives code generation, and the selected release profile controls the
server backend and queue behavior. The repository includes fixture apps,
benchmarking, implementation notes, and backend details for contributors.
