# Composition and lifecycle implementation audit

**Date:** July 27, 2026  
**Decision source:** `docs/architecture/composition-lifecycle-decisions.md`

## Implemented in this audit

| Contract | Implementation | Regression coverage |
| --- | --- | --- |
| Local and effective mounted facts | `src/core/scope.lua`; route normalization snapshots each scope | `tests/composition_lifecycle.lua`: mounted fact snapshot |
| Inspectable emitted scope facts | `src/codegen/emitter.lua` writes `scopes.json` | graph smoke emits local/effective scope records |
| Deterministic scope identity | globally unique explicit/generated IDs on `App:mount` | duplicate scope-ID test |
| Fact merge diagnostics | scope helper rejects conflicting params, query, capabilities, and context | context collision and equal-parameter tests |
| Context contract | declarative-only validation and read-only request proxy | immutable `ctx.scope` test |
| Named plugin identity | app-wide plugin definition registry, effective ID deduplication | root/scoped plugin test |
| Raw middleware | explicit `app:use(function)` rejection | raw middleware test |
| Canonical route IDs | canonical lowering retains `id` for graph-plugin targets | graph insertion regression |
| Graph-plugin ordering | unique IDs and stable ID ordering per pass | graph-plugin ordering test |
| Post-transform structural validation | hook and pipeline validation rerun after graph passes | invalid inserted-hook test |
| Codegen unit ownership | duplicate codegen unit names fail | `src/core/plugin_contract.lua` |

## Files changed

- `src/core/scope.lua` — new scope construction, merge, identity, and snapshot
  model.
- `src/core/app.lua` — scope/plugin registration and raw middleware rejection.
- `src/core/route.lua` — scope snapshots, request-plugin graph definitions,
  canonical route IDs, and post-transform validation.
- `src/core/contract.lua` — reusable pipeline structural validation.
- `src/core/plugin_contract.lua` — deterministic graph-plugin pass order,
  duplicate-ID protection, codegen collision protection.
- `src/cli/hybrid.lua` — read-only request-facing scope context.
- `src/codegen/emitter.lua` — `scopes.json` inspection artifact.
- `src/meteorite.lua`, `src/codegen/luals_aids.lua` — updated LuaLS surface.
- `tests/composition_lifecycle.lua` — focused contract regressions.

## Final normalized shape

Each normalized route contains a serializable scope snapshot:

```lua
scope = {
  id = "devices",
  parent = "organization",
  local_prefix = "/devices",
  path_prefix = "/orgs/:org_id/devices",
  chain = { ... },
  source = { file = "src/app.lua", line = 12, column = 1 },
  declared = { params = { ... }, context = { ... }, plugins = { ... } },
  effective = { params = { ... }, context = { ... }, plugins = { ... } },
}
```

The runtime uses `scope.effective.context` as the read-only `ctx.scope` view.
The graph uses effective plugin IDs to reference release-visible plugin
definitions in `graph.plugins`.

Release graph output also includes `scopes.json`. It retains scope identity,
source, chain, declared/effective context, plugin IDs, and the declared versus
effective parameter/query/capability key sets without widening the generated
runtime ABI.

## Deliberate limitations

The following remain unsupported and are therefore not promised by the public
guide:

- arbitrary raw middleware;
- a unified request-time executor for `transform` and `hook` stages;
- scoped lifecycle-hook inheritance and post-handler unwinding;
- route/child/root error-hook precedence or decline handling;
- typed dataflow ownership and cross-Lua/Zig request-state exchange;
- guaranteed worker topology or process-global Lua module state;
- graph-plugin dependency declarations, I/O sandboxing, and profile-pass
  mutation enforcement.

Pipeline stages and graph-plugin insertions are graph metadata with structural
validation. They become runtime guarantees only after a shared executor is
used by every backend.

## Backend discrepancy

The hybrid dispatcher executes effective named request plugins in root-to-leaf
order followed by the selected primary handler. Generated release backends
receive the graph metadata, but do not yet interpret every pipeline stage as a
unified lifecycle executor. This is intentionally documented as a limitation.

## Validation run

```text
moon exec lua tests/composition_lifecycle.lua
moon exec lua tests/plugin_flow.lua
moon exec lua tests/contract.lua
```

All focused tests passed after this audit.
