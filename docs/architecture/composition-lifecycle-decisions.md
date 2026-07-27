# Composition, scopes, pipelines, and lifecycle decisions

**Status:** implementation audit, July 27, 2026. This document is the
canonical decision record for the public composition guide. It separates
current behavior from the release model Meteorite still needs to implement.

## Evidence reviewed

The audit reviewed `src/core/app.lua`, `src/core/route.lua`,
`src/core/contract.lua`, `src/core/hooks.lua`, `src/core/plugin_contract.lua`,
`src/cli/hybrid.lua`, the graph/codegen modules, generated graph output, and
the `contract.lua`, `plugin_flow.lua`, `routes_graph.lua`, and scoped-plugin
fixtures.

## Current behavior, verified

### Service root and mounted builders

`m.app()` creates one declaration root. `app:mount(prefix, options, builder)`
creates a temporary child declaration scope, calls `builder(child)`, copies the
child declarations back to the parent, and returns the parent app. A builder's
return value is ignored. The child object is not retained by Meteorite after
the callback, although Lua code can technically retain the reference; doing so
does not add routes to the parent after the mount has returned and is
unsupported.

There is no supported app-to-app mount. A builder receives an app-shaped
declaration scope only so it can use the ordinary route methods. Creating
another `m.app()` inside a builder creates an unrelated root and is not merged.

### Paths and route facts

Mount prefixes are concatenated with child route paths. Paths must begin with
`/`; `parse_path` understands literals, named parameters, `*`, and final
catch-all parameters. Optional parameters are not a path feature. Final route
validation happens while normalizing declarations into a graph.

Before this audit's implementation work, mount and route fact maps used plain
overwrite semantics. A child could silently replace inherited `params`,
`query`, `capabilities`, or `context` entries. Duplicate slashes and duplicate
scope IDs were not given a complete contract.

### Request plugins

`m.plugin(spec)` creates a named Lua request-plugin definition. `app:use` and
mount `plugins = { ... }` attach it to the effective scope plugin list. The
hybrid dispatcher runs the resulting list in list order before the primary
route handler. A plugin may return a string or response table to short-circuit
the handler. Plugin exceptions are converted into the dispatcher error path.

The normalizer records each distinct plugin object in `graph.plugins`, and
code generation lifts plugin `execute` functions for hybrid releases. The
current deduplication is object-identity based in the graph, whereas runtime
execution follows the scope list. Attaching the same plugin at two levels can
therefore execute it twice.

`app:use(function)` is merely recorded in `app.middleware`; it is not part of
the hybrid dispatch path and is not a release-aware request mechanism. Public
documentation must not describe it as equivalent to `m.plugin`.

### Route pipelines and hooks

Canonical route declarations lower handlers into pipeline stage metadata.
Supported stage kinds are `transform`, `handle`, and `hook`; the current
strategy field is `strat` and supports `inline_lua`, `lua`, and `zig`. `rust`
is explicitly rejected. The builder rejects duplicate explicit IDs inside one
pipeline, requires pre-handler hook phases before the first `handle`, and
requires post-handler/observe/error hooks after it. Transform-only pipelines
are marked but not rejected.

Hook phase permission validation is implemented as graph-time metadata
validation. It rejects forbidden response writes, forbidden short-circuiting,
and route-param reads in `pre_tree`.

**Important limitation:** generated route metadata contains the full pipeline,
but the current hybrid dispatcher executes only scope plugins and the selected
primary handler. Generated Zig bindings similarly select route handlers rather
than execute an arbitrary stage sequence. Pipeline transforms, hooks, and
graph-plugin injected stages are not yet one backend-neutral runtime execution
model. They are inspectable/validated graph data, not a released lifecycle
guarantee.

### Graph plugins

Graph plugins are distinct from request plugins. `app:use(graph_plugin)`
registers a build-time graph author. The current pass order is declaration
order within four fixed passes: `validate`, `transform`, `codegen`, `profile`.
They can add diagnostics, graph hooks, codegen units, counters, and mutate a
route pipeline relative to a stage ID. Policy ownership conflicts are emitted
as diagnostics, not failures. No dependency/priority system, codegen-unit
collision check, post-transform revalidation, determinism guard, or I/O
sandbox exists today.

### State

`ctx:set` and `ctx:get` operate on a new Lua table for every call to
`hybrid.invoke`, so they are request-local in that dispatcher. They accept
arbitrary Lua values and may overwrite existing values. The state table is
returned by the test/invoke response for inspection and is naturally discarded
when the invocation ends.

`ctx:cache` is backed by `app.cache`, so it is runtime-instance state in the
hybrid runner. Lua `require` module state follows the Lua interpreter instance
that loads it. Current source does not guarantee one interpreter per process,
one per worker, or a shared topology across release backends. The safe term is
**runtime-instance module state**, not process-global state.

## Chosen semantic model

The following rules are the target contract. Items marked **implemented by this
audit** are enforced in the accompanying implementation work. Others remain
planned and must not be promised by the public guide until their graph and
runtime implementation lands.

### Scope model

1. There is exactly one service root per normalized graph.
2. Every `mount` creates a scope record with `id`, `parent`, local prefix,
   normalized full prefix, local facts, effective facts, plugin references,
   source location, and source-order information. **Implemented by this
   audit.**
3. Explicit scope IDs are recommended for any boundary referenced by tooling or
   diagnostics. Generated IDs are deterministic from the normalized full
   prefix and are only an internal convenience.
4. Scope IDs are globally unique within an app graph. Sibling or nested
   duplicates fail deterministically. **Implemented by this audit.**
5. A route carries both its deepest scope record and the complete ancestor
   chain. Handler-visible scope data is only the effective declarative context,
   not compiler-internal scope structure. **Implemented by this audit for the
   graph and hybrid context.**
6. Mounts may not contain route parameters that collide with an ancestor or
   child path parameter name. **Implemented by this audit.**
7. Mount `/` is valid. Trailing slashes are normalized at declaration time;
   duplicate internal slashes are rejected instead of silently changing route
   identity. **Implemented by this audit.**

### Fact merge table

| Fact family | Rule |
| --- | --- |
| Path `params` | Inherited; equal duplicates are accepted; different declarations fail. |
| `query` | Inherited; equal duplicates are accepted; different declarations fail. |
| Capabilities | Inherited by capability key; equal duplicates are accepted; different ownership/specifications fail. |
| Context | Inherited declarative data; duplicate keys fail, even when values are equal, unless a future explicit override syntax is introduced. |
| Named request plugins | Inherited by plugin ID; a repeated reference to the same definition runs once; a different definition with the same ID fails. |
| Hooks / route pipeline | Route-local in the current release. Scoped lifecycle inheritance is planned. |
| Metadata / responses / policy | Route-local in the current release. Scoped merging is not implemented. |

Context values are restricted to declarative scalars, arrays, and records:
strings, numbers, booleans, and nested tables of those values. Functions,
threads, userdata, and cyclic tables are rejected. This keeps graph inspection
and release serialization possible. **Implemented by this audit.**

No silent shadowing is allowed. A future override must use explicit syntax and
must leave an override record in the graph.

### `ctx.scope`

`ctx.scope` is a read-only handler view of the precomputed effective context.
It does not expose `id`, parent, prefixes, or compiler scope chains. Those are
available only through graph inspection. Context is copied into the request context so a handler cannot mutate
the scope declaration. **Implemented by this audit for the hybrid dispatcher.**

### Identity policy

| Construct | Identity policy |
| --- | --- |
| Service root | `root` |
| Mounted scope | explicit recommended; deterministic generated fallback; global uniqueness |
| Named request plugin | explicit globally unique `id` |
| Graph plugin | explicit globally unique `id` |
| Explicit pipeline stage | explicit ID required when another stage/plugin targets it |
| Shorthand handler | deterministic internal route-local ID; not a graph-plugin target |
| Hook / transform | explicit route-local ID when referenced |
| Codegen unit | plugin-qualified name; collision is an error (planned) |

Generated IDs are never a stable integration target. Graph transformations must
target an explicit stage ID.

### Request plugin contract

A named request plugin is a release-visible graph definition that contributes
one identified pre-handler execution boundary to every route in its scope. In
the current runtime it is invoked root-to-leaf before the primary handler.
Duplicate effective attachment is deduplicated by plugin ID and definition;
conflicting IDs fail. **Implemented by this audit.**

Plugins are not yet general stage factories: they cannot currently declare
post-handler or observe behavior, dependencies, reads/writes, or multiple
runtime stages. Those are planned capabilities of the unified pipeline model.

Raw middleware is not supported as a request contract. It must fail with a
diagnostic directing authors to `m.plugin` or an explicit route pipeline.
**Implemented by this audit.**

### Pipeline and lifecycle contract

The normalized graph remains backend-neutral data, but it is not yet a
backend-neutral executor. The future executor will use one materialized order:

1. root request plugins, declaration order;
2. ancestor scope request plugins, outer-to-inner;
3. route pre-handler pipeline stages;
4. exactly one primary response-producing handle stage;
5. route post-handler stages, then scope/root post-handler hooks,
   inner-to-outer;
6. observe hooks after response finalization; and
7. error hooks, nearest scope to root, when an earlier phase fails.

This is a **product decision, not current runtime behavior** for transforms,
hooks, graph insertions, post-handler mutation, and error unwinding. Until the
executor exists, only the following lifecycle claims are verified:

| Phase | Graph validation today | Runtime guarantee today |
| --- | --- | --- |
| `pre_tree` | no route-param reads, may short-circuit | none |
| `post_match` | no response writes, may short-circuit | none |
| `pre_handler` | no response writes, may short-circuit | named plugins only |
| `post_handler` | response writes allowed | none |
| `observe` | response writes/short-circuit forbidden | none |
| `error` | response production metadata allowed | dispatcher fallback only |

The dispatcher returns a fallback error response for plugin/handler failures;
it does not currently implement route/scope/root error hooks or post-handler
unwinding. A failing observe hook is therefore not a supported runtime case.

### Graph pass contract

Graph plugins are build-time graph authors. The fixed pass order is validate,
transform, revalidate, codegen, profile. Within a pass, plugins are ordered by
explicit `id`, with declaration order only as a tie-breaking diagnostic error:
duplicate graph plugin IDs are prohibited. Transform changes are attributed to
their owner plugin and must undergo structural pipeline/hook validation before
codegen. Profile passes must not alter executable graph data. Graph plugin I/O
is outside the reproducible contract and must be prohibited by a future
sandbox. Only the existing fixed pass names are implemented today; revalidation
and deterministic plugin ordering are implementation work in this audit.

## Required implementation work before public guarantees

The public guide may claim only the scope merge, scope identity, named plugin,
request-state, and raw-middleware behavior once the accompanying tests pass.
It must label full pipeline execution, scoped lifecycle hooks, graph-plugin
stage execution, error-hook precedence, cross-Lua/Zig state exchange, worker
topology, and plugin dependency ordering as unavailable or planned.

The next release-level implementation should add a single backend-neutral
pipeline executor and lower both named plugins and explicit stages into it. At
that point it can implement deterministic post-handler unwinding, error-hook
precedence, cross-backend equivalence tests, typed dataflow ownership, and
release-visible source strategy contracts without inventing separate runtime
rules per backend.
