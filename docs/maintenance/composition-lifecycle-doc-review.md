# Composition and lifecycle public-doc review

This note maps the public guide claim set to implementation and tests. It is
intentionally conservative: no lifecycle guarantee is documented unless the
normalized graph represents it and the relevant execution path is verified.

| Public claim | Implementation | Test / graph field | Release modes | Limitation |
| --- | --- | --- | --- | --- |
| Builder modules contribute routes to one parent root | `src/core/app.lua:App:mount` | `tests/composition_lifecycle.lua` scope snapshot | dev, hybrid, static graph generation | Builder return values are ignored. |
| Scope facts have local and effective forms | `src/core/scope.lua:snapshot`, `src/codegen/emitter.lua` | `route.scope.declared`, `route.scope.effective`, `scopes.json` | all graph modes | Only params/query/capabilities/context/plugins are scoped today. |
| Collisions do not silently shadow | `src/core/scope.lua:merge_fact_map` | conflict regression | all graph modes | No explicit override syntax exists. |
| `ctx.scope` is read-only effective context | `src/cli/hybrid.lua:new_context` | immutable context regression | hybrid invoke | Generated backend exposure is graph data, not independently tested here. |
| Named plugins run root-to-leaf before a hybrid handler | `src/cli/hybrid.lua:execute_scope_plugins` | plugin ordering regression | hybrid invoke | Not generalized into post-handler/observe stages. |
| Raw function middleware is rejected | `src/core/app.lua:App:use` | raw middleware regression | all modes | Use named plugins instead. |
| Graph plugins have deterministic pass order | `src/core/plugin_contract.lua:run_passes` | graph plugin ordering regression | graph construction | No dependency graph or I/O sandbox. |
| Pipeline hooks are validated | `src/core/hooks.lua`, `src/core/contract.lua` | `tests/contract.lua`, insertion regression | all graph modes | Hooks are not yet a uniform runtime executor. |
| Explicit stages remain inspectable | `src/core/contract.lua:serialize`, `src/core/route.lua` | `route.pipeline` | all graph modes | Runtime execution is limited to primary handlers/plugins. |

The public guide deliberately does not claim error-hook precedence,
post-handler/observe execution, graph-plugin request-stage execution,
cross-strategy state exchange, or process-global Lua modules. Those topics are
specified as future work in
`docs/architecture/composition-lifecycle-decisions.md`.
