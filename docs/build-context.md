# Build context

Meteorite gives each application a snapshot of the facts used while declaring
its graph. Framework integrations read `app.build_context`, rather than process
globals or environment variables.

```lua
local m = require('meteorite')
local app = m.app({ name = 'site' })
-- During a release-hybrid graph load:
assert(app.build_context.mode == 'release-hybrid')
assert(app.build_context.release)
return app
```

CLI graph loading and Ballad graph/release loading establish the context before
evaluating the entrypoint. They also pass it as the entry chunk's first argument
(`local context = ...`). `m.app()` captures a fresh snapshot, so an app keeps its
mode after the loader finishes. Imports performed during declaration share the
same scoped context. A nested or failed load restores the previous scope.
Declaration is synchronous; yielding across `with` is outside this contract.

For programmatic construction, pass the context explicitly:

```lua
local app = m.app({
  name = 'site',
  build_context = m.build_context.create('release-static'),
})
```

Tooling can run a declaration under a context with
`m.build_context.with(context, function(context) ... end)`. `current()` returns a
fresh snapshot and defaults to `dev` outside a loader. Mutating a returned
snapshot does not change the loader's context or another app.

Supported mode names are `dev`, `hybrid_dev`, `hybrid`, `static`,
`release-hybrid`, and `release-static`. The `release` flag is true only for the
last two explicit release modes. Unknown modes fail with an actionable error.
This API describes graph declaration; it does not change graph normalization,
provide a request context, or infer a Moonstone target flavor.

`METEORITE_BUILD_MODE` is no longer read or written. Code that used it should
read its app's `build_context.mode`. Hydronium mounts use that snapshot to decide
HMR defaults; an explicit `hmr` option still takes precedence. Update Meteorite
and Hydronium together when adopting this integration contract.
