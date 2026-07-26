# Stateful HMR Supervisor Intent

## Status

This is an implementation intent, not a current Meteorite feature or runtime
guarantee. Today, `Watch_partiture.lua` provides restart-safe live reload:
Ballad watches declared source nodes, materializes a fresh graph and development
binary when required, then hands the server over under guard control.

Meteorite's direct `meteorite dev` loop can reload Lua-only handler chunks in
process when graph partitions permit it. That narrow optimization is not yet a
stateful, worker-aware HMR contract and must not be advertised as one.

## Goal

Provide opt-in, generation-based HMR for compatible hybrid Lua services without
making HTTP backends, Ballad, or application code responsible for hidden state
resurrection.

The first supported scope is a running process with an unchanged executable,
route graph ABI, and runtime topology. A new Lua handler generation is staged,
validated, and atomically selected for new requests while existing requests
finish on their prior generation.

## Boundary of Responsibility

### Ballad

- Watches declared source inputs, debounces changes, and owns process traps.
- Materializes graph/build products and exposes immutable fingerprints.
- Emits a refresh request with the changed product partitions.
- Does not own sockets, worker state, request draining, or application state.

### Meteorite supervisor

- Owns the listening server process, generation lifecycle, and worker fleet.
- Classifies a refresh as in-process reload, rolling restart, or rejected.
- Stages a candidate handler generation before it becomes visible.
- Drains in-flight work and rolls back a failed generation without losing the
  previous healthy generation.

### Application state provider

- Is explicit and opt-in; Meteorite must not infer serializable application
  state from Lua globals or closures.
- May be an external database/cache, or a project-declared provider with
  `snapshot`, `restore`, `migrate`, and `health` operations.
- Owns state schema versions and migration policy.
- Is required only when a reload crosses a process or worker-runtime boundary.

## Reload Classes

1. **Chunk swap** — only lifted Lua handler products change and the graph ABI is
   identical. The supervisor stages the new chunks, atomically updates the
   active generation, and retains the existing process state.
2. **Worker refresh** — the graph ABI is compatible but there are multiple Lua
   states. Every worker acknowledges staging the same generation before the
   supervisor makes it active. A failed or timed-out worker aborts the refresh.
3. **Rolling restart** — executable, route graph, native module, backend, or
   configuration changes require a new process generation. The old generation
   drains after the replacement passes readiness checks.
4. **Rejected refresh** — incompatible graph contracts, missing state-provider
   migration, or failed staging preserve the current healthy generation.

## Generation Protocol

1. Ballad or `meteorite dev` produces a graph/product fingerprint and a change
   partition report.
2. The supervisor accepts only known compatible reload classes.
3. Candidate Lua chunks load in an isolated staging environment; syntax,
   declared exports, and optional application health checks must pass.
4. The supervisor assigns a monotonic generation ID and broadcasts it to all
   relevant workers.
5. Workers acknowledge readiness. New requests then select the new generation;
   requests already executing retain their captured generation.
6. The old generation is reclaimed only after its request count reaches zero or
   after an explicit bounded drain policy.
7. The supervisor records outcome, timings, active generation, rollback reason,
   and worker acknowledgements for diagnostics.

## State and Worker Rules

- Lua globals, upvalues, open sockets, and native module state are not portable
  state-provider data by default.
- The first implementation should support one locked Lua runtime before
  promising arbitrary worker pools.
- Multi-worker reload requires a bounded acknowledgement protocol and a clear
  policy for requests arriving during refresh; it must never silently run mixed
  handler generations for one request.
- Process restarts require either stateless application behavior, externalized
  state, or a declared state provider whose migration succeeds before traffic
  moves to the replacement.
- Static-only outputs never participate in HMR.

## Safety Constraints

- No generation becomes active before all required validation succeeds.
- Reload work has explicit time, memory, and queue limits.
- A failed candidate never replaces the last healthy generation.
- Signals, shutdown, and Ballad watcher cleanup terminate staging work and
  drain or reject new requests predictably.
- HMR compatibility is based on explicit graph/runtime fingerprints, not file
  timestamps or a guessed list of changed modules.

## Delivery Sequence

1. Route the current Lua-only partition classifier through the Ballad watch
   effect without compiling or restarting the server.
2. Introduce one-process generation staging, atomic handler selection, and
   rollback tests.
3. Add in-flight request draining and observable generation diagnostics.
4. Add optional multi-worker acknowledgement under strict bounded limits.
5. Define and test the explicit state-provider contract for rolling restarts.
6. Only then expose a separate `HMR_partiture.lua` or `meteorite hmr` command.

Until those steps are complete, the user-facing contract remains **watch and
live reload**, not stateful HMR.
