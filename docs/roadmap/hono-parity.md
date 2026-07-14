# Meteorite ↔ Hono Sensible Feature Parity Plan

Purpose: identify which Hono features matter for a serious Meteorite release, decide what must be first-class vs. intentionally out of scope, and track parity with checkboxes.

Sources reviewed on 2026-07-07; local Meteorite status reconciled on 2026-07-10:

- Hono docs home: <https://www.honojs.com/docs/>
- Hono routing docs: <https://hono.dev/docs/api/routing>
- Hono middleware docs: <https://hono.dev/docs/guides/middleware>
- Hono validation docs: <https://hono.dev/docs/guides/validation>
- Hono RPC docs: <https://hono.dev/docs/guides/rpc>
- Hono WebSocket helper docs: <https://hono.dev/docs/helpers/websocket>
- Hono JSX docs: <https://hono.dev/docs/guides/jsx>
- Hono OpenAPI example: <https://hono.dev/examples/hono-openapi>

Hono positioning to respect: it is a small, ultrafast framework built on Web Standards and runs across runtimes including Cloudflare Workers, Fastly Compute, Deno, Bun, Vercel, Netlify, AWS Lambda/Lambda@Edge, and Node.js. Its serious-release feature surface is not only speed; it also includes routing, middleware, helpers, validation, RPC, JSX/html, WebSockets, and ecosystem integrations.

## Parity Strategy

- **Do not clone Hono.** Meteorite is a compiler: Lua declares, Zig compiles, releases are static or hybrid.
- **Match the serious expectations.** Users will expect routing, middleware, validation, CORS, cookies, auth helpers, OpenAPI, and excellent DX.
- **Lean into Meteorite strengths.** Compile-time graph validation, generated Zig contexts, static/hybrid release gates, target Lua packaging, and runtime counters should exceed Hono where possible.
- **Treat parity as product requirements.** A missing feature needs either an implementation plan or a clear non-goal.

## Status Legend

- Missing or not validated
- Partial / needs design
- Implemented but needs tests/docs
- Release-ready

## Phase H0 — Core Hono-Like Routing Expectations

Hono docs emphasize flexible routing, method-specific handlers, wildcard routes, host/header-derived routing customization, and registration-order priority.

- [x] `GET`, `POST`, `PUT`, `PATCH`, `DELETE` route declarations are documented and tested.
- [x] `HEAD` and `OPTIONS` behavior is defined and tested.
- [x] `app:all()` or equivalent any-method route support exists or is explicitly out of scope.
- [x] Wildcard route matching exists or has a design.
- [x] Param route matching supports typed extraction and source diagnostics.
- [x] Route priority/order semantics are explicit; static vs param vs wildcard behavior is deterministic.
- [x] Mounted apps/scopes behave like route groups.
- [x] Host/header-aware routing is evaluated as P1: useful, but not P0 unless multi-tenant routing is a target.
  - **Decision:** P1 non-goal for the current release. Multi-tenant routing is not a target for Meteorite v0.1.
- [x] 404/405 behavior is aligned with web expectations and includes `Allow` for 405.

### H0 Reconciliation Notes

Release-ready coverage now includes method declarations (`GET`/`POST`/`PUT`/`PATCH`/`DELETE`), explicit `HEAD`/`OPTIONS`, typed params, mounted scopes, `405 Allow` behavior via `fixtures/tests/basic-service.sh` and `fixtures/tests/web-standards.sh`, `app:all()` any-method routes (method `ALL` dispatched after method-specific routes), bare `*` wildcard routes (final-segment catch-all), and explicit route priority documentation in `docs/examples.md`. Host/header-aware routing remains a P1 non-goal for the current release.

## Phase H1 — Context And Request/Response API

Hono’s DX is centered around an easy context object and Web-standard Request/Response style behavior.

- [x] Lua `ctx` exposes params, query, state, scope, request headers, body, and response helpers.
- [x] Zig generated contexts expose typed params/query and response helpers.
- [x] Response helpers support text, JSON, bytes, redirects, custom status, custom headers, and empty bodies.
- [x] Response headers work in returned Lua response tables and direct helpers like `ctx:text(..., { headers = ... })`.
- [x] `meteorite invoke` prints or returns response headers for local testing.
- [x] Request parsing supports JSON, form, query, header, param, and cookie validation targets comparable to Hono validation docs.
- [x] Context-local storage/state semantics are documented and tested for scoped plugins and nested mounts.

## Phase H2 — Middleware System

Hono middleware can run before/after handlers, call `next()`, short-circuit, and compose in registration order. Hono catches thrown errors and routes them through error handling.

- [x] Meteorite pipeline has middleware-like before/after semantics that users can understand without compiler internals.
- [x] Middleware can short-circuit with a response.
- [x] Middleware can mutate response headers after handler execution.
- [x] Middleware ordering is registration-order or documented equivalent.
- [x] Scoped middleware works for route groups/mounts.
- [x] Error propagation from middleware and handlers uses a single `on_error`/error hook contract.
- [x] Middleware source locations appear in diagnostics.
- [x] Middleware effects are captured in graph metadata for release inspection.

## Phase H3 — Built-In Middleware And Helpers That Matter

Hono docs list built-ins/helpers including Basic Auth, Bearer Auth, Body Limit, Cache, Compress, Context Storage, Cookie, CORS, ETag, html, JSX, JWT, Logger, Pretty JSON, Secure Headers, SSG, Streaming, GraphQL, Firebase Auth, Sentry, and more. Meteorite should prioritize the ones that are core to API/server releases.

### P0 Helpers

- [x] CORS helper: origin rules, methods, allowed headers, exposed headers, credentials, max-age, `Vary`, and preflight `OPTIONS`.
- [x] Body limit helper: global and route-level limits with deterministic errors.
- [x] Logger helper: basic structured request logging with redaction.
- [x] Secure headers helper: sane defaults with opt-out.
- [x] Cookie helper: parse request cookies and set response cookies.
- [x] ETag/static cache helper: static files covered; optional dynamic response helpers remain.
- [x] Request ID helper: generate/propagate request IDs.

### P1 Helpers

- [x] Basic Auth helper.
- [x] Bearer/JWT auth helper or documented integration path.
- [x] Pretty JSON helper for dev/debug only.
- [x] Compression helper with correct `Vary`, `Content-Length`, and ETag behavior.
- [x] Timeout helper with cancellation semantics.
- [x] Timing helper / `Server-Timing` support.
- [x] Trailing slash middleware policy.
- [x] Method override policy if HTML forms are a target.
  - **Decision:** Non-goal for API-service release. HTML form method override is not a target.
- [x] IP restriction / trusted proxy story.
  - **Decision:** Non-goal for v0.1. Reverse proxy handles IP filtering (see `docs/deployment.md` Nginx config).
- [x] CSRF helper if cookie-auth apps are a target.
  - **Decision:** Non-goal for API-service release. CSRF protection belongs in the reverse proxy or client for cookie-auth apps.

### P2 / Ecosystem Integrations

- [x] GraphQL integration example or non-goal.
  - **Decision:** Non-goal. GraphQL is a separate runtime concern; Meteorite focuses on REST/HTTP compilation.
- [x] Sentry/observability integration hook example.
  - **Decision:** Non-goal for v0.1. Structured logging (`ctx:log`) and `Server-Timing` provide observability; external APM integration is adapter work.
- [x] Firebase/Auth.js/Better Auth style examples if user demand appears.
  - **Decision:** Non-goal. Auth capabilities (`ctx:auth`) provide the integration point; specific providers are user-side.
- [x] SSG/static generation story for `m.site()` or release export.
  - **Decision:** `m.site()` handles static asset packaging. Full SSG with pre-render belongs in Ballad release tasks, not Meteorite core.

## Phase H4 — Validation And Type/Schema Story

Hono provides a thin validator and supports validation targets: `json`, `query`, `header`, `param`, `cookie`, and `form`; Hono RPC uses validator output for client inference.

- [x] Meteorite schema validators cover params, query, headers, cookies, JSON body, form body, and raw body constraints.
- [x] Validation errors return configurable but stable status/body format.
- [x] Validators generate graph metadata usable for docs and clients.
- [x] Runtime validation behavior matches dev/invoke validation behavior.
- [x] Third-party Lua validators have an extension point without undermining release graph determinism.
  - **Decision:** Non-goal for v0.1. Built-in validators (u64, uuid, slug, hex, email, token, bool, pattern) cover API-service needs. Extension points would undermine compile-time graph determinism.
- [x] Header validators are case-insensitive where appropriate.
- [x] Cookie validators handle absent, malformed, and repeated cookies.
- [x] Form validators document content-type requirements.

### H1–H4 Reconciliation Notes

The Web Standards fixture now validates Lua and Zig response helpers, returned Lua response tables, custom headers, redirects, empty responses, cookies, JSON/form/body parsing, case-insensitive request headers, scoped state, request IDs, auth helpers, secure headers, CORS, logging, `Server-Timing`, response-header injection rejection, graph schema metadata, OpenAPI planning metadata, and dev/invoke parity for validation. `meteorite invoke --headers` is now implemented: the `--headers` flag prints sorted response headers after the status/content-type/body line in text mode.

## Phase H5 — RPC / Generated Client Parity

Hono RPC shares server API specs with clients through TypeScript types and its client helper. Meteorite cannot mirror this exactly in Lua/Zig, but it can compete with graph-derived clients.

- [x] Decide target client outputs: TypeScript, Lua, OpenAPI-only, or all three.
  - **Decision:** OpenAPI 3.1 JSON is the canonical spec. TypeScript and Lua clients generated from it. See `docs/design/openapi.md`.
- [x] Export route graph metadata with methods, paths, params, query, body, responses, and errors.
- [x] Support TypeScript client generation through standards-compliant OpenAPI.
  - **Decision:** Use standard `openapi-generator` or `hey-api/openapi-ts` against the generated `openapi.json`. No custom Meteorite tooling is required for v0.1.
- [ ] Generate Lua client for Moonstone/Meteorite service-to-service calls.
  - **Decision:** Deferred tooling. The spec is ready; a first-party Lua client generator can consume `openapi.json` or direct graph metadata later.
- [x] Include response status/content-type/header schemas in generated metadata.
- [ ] Provide compatibility tests for generated Lua clients against `meteorite invoke` and live server.
  - **Decision:** Deferred with the Lua client generator. `openapi.json` itself is validated in `tests/openapi.lua`.
- [x] Document where Meteorite's compile-time graph offers stronger guarantees than Hono RPC.
  - **Documented in `docs/design/openapi.md` under "Compile-Time Graph Guarantees vs Hono RPC".

## Phase H6 — OpenAPI And Documentation

Hono’s OpenAPI ecosystem uses middleware such as `hono-openapi`, schema validators, route descriptions, response schemas, and an `/openapi` endpoint.

- [x] Define Meteorite route-description DSL for summary, description, tags, operation id, and response schemas.
- [x] Map Meteorite validators to JSON Schema/OpenAPI components.
- [x] Emit OpenAPI 3.1 from the normalized graph.
- [x] Add optional `/openapi.json` route for dev/hybrid mode or generated static asset for releases.
- [x] Add Swagger UI or Redoc static template as optional release asset.
  - **Decision:** Non-goal for Meteorite core. Users can point Swagger UI/Redoc at the generated `openapi.json` or the `/__meteorite/openapi.json` dev endpoint.
- [x] Validate generated OpenAPI in tests.
- [x] Detect undocumented routes before serious release and warn/fail by mode.

## Phase H7 — HTML, Templates, JSX Equivalent

Hono supports html helpers, JSX, JSX renderer middleware, streaming JSX, and SSG. Meteorite does not need JSX specifically, but serious contenders need an HTML/rendering story.

- [x] Document HTML response helper for Lua and Zig.
- [x] Provide safe HTML escaping helper.
- [x] Decide supported template story: `etlua`, custom compiler, static pre-render, or all.
  - **Decision:** Non-goal for v0.1. `ctx:html()` and `ctx:escape_html()` provide basic HTML output. Template engines are user-side in hybrid mode.
- [x] Ensure templates work in static and hybrid release modes where applicable.
  - **Decision:** Non-goal. Template engines run in hybrid mode (Lua runtime). Static mode uses Zig handlers for HTML.
- [x] Add examples for template layout, partials, and static asset integration.
  - **Decision:** Non-goal for v0.1. `ctx:html()` is the HTML output mechanism.
- [x] Evaluate streaming HTML as P2 unless needed for competitive demos.
  - **Decision:** P2 non-goal. Streaming HTML is not needed for API-service releases.
- [x] Decide whether SSG belongs in Meteorite or Ballad release tasks.
  - **Decision:** SSG belongs in Ballad release tasks, not Meteorite core. `m.site()` handles static assets.

## Phase H8 — WebSockets And Streaming

Hono has a WebSocket helper with `onOpen`, `onMessage`, `onClose`, and `onError`, and Hono documents middleware/header caveats around upgrades. Hono also has streaming helpers.

- [x] Decide if WebSocket is in scope for the next serious release; if not, mark as explicit P2.
- [x] If in scope, design upgrade handling in `fast_http` and `std_http` separately.
  - **Decision:** Non-goal for v0.1. WebSocket is P2.
- [x] Define Lua handler lifecycle for WebSocket callbacks and state.
  - **Decision:** Non-goal for v0.1. WebSocket is P2.
- [x] Define backpressure, message size, close codes, ping/pong, and error behavior.
  - **Decision:** Non-goal for v0.1. WebSocket is P2.
- [x] Ensure middleware/header mutation does not conflict with upgrade responses.
  - **Decision:** Non-goal for v0.1. WebSocket is P2.
- [x] Design streaming responses separately from WebSockets: chunked transfer, flush, cancellation, and Lua bridge lifetime.
  - **Decision:** Non-goal for v0.1. Streaming responses are P2.

## Phase H9 — Runtime/Adapter Story

Hono wins mindshare partly by running across many JS runtimes. Meteorite’s equivalent is deployment clarity across native targets.

- [x] Static binary story is documented as the default production advantage.
- [x] Hybrid release story documents Lua runtime packaging and target ABI.
- [x] Cross-target release diagnostics are friendly and early.
- [x] Container deployment template exists.
- [x] Systemd/launchd/supervisor examples exist.
- [x] Serverless/edge story is explicitly out of scope or planned as adapter work.
- [x] Graceful shutdown and health/readiness endpoints are documented.

## Phase H10 — Serious Release Must-Haves

These are the minimum must-haves to be taken seriously against Hono for API services, even if Meteorite is not trying to be a TypeScript framework.

- [x] Routing: methods, params, query, scoped mounts, deterministic priority.
- [x] Middleware: before/after, short-circuit, response mutation, error boundary.
- [x] Request API: headers, body, params, query, cookies.
- [x] Response API: status, body, content type, custom headers, cookies, redirects, JSON.
- [x] CORS: real helper plus benchmark/header tests.
- [x] Validation: params/query/body/header/cookie with graph metadata.
- [x] OpenAPI: generated spec from graph.
- [x] Dev UX: `init`, `doctor`, `routes`, `invoke`, hot reload, clear diagnostics.
- [x] Release UX: static/hybrid gates, manifest, smoke tests, no source leaks.
- [x] Performance UX: honest benchmark proof with counters and invalidation reasons.
- [x] Docs: copyable examples for JSON API, CORS, auth, cookies, static site, OpenAPI, and hybrid Lua.

### H5–H10 Reconciliation Notes

Meteorite now exports route/schema/OpenAPI-planning metadata and release manifests with enough graph facts to feed docs and clients. A full OpenAPI 3.1 JSON emitter (`src/codegen/openapi.lua`) now generates `openapi.json` alongside `openapi-plan.zon` during graph builds, with complete path templates, parameter/schema mapping, request bodies, response schemas, and inferred security schemes. Generated TypeScript/Lua clients remain open. Deployment parity is substantially stronger: static/hybrid release gates, copied-directory release smoke, no-source-leak checks, safe build-info endpoint, container recipe, graceful shutdown, and benchmark claim audits are in place. WebSockets, full JSX, TypeScript RPC inference, P0 serverless/edge adapter parity, GraphQL built-ins, and cloning every Hono middleware helper are explicitly non-goals for the serious API-service release.

## Non-Goals To Decide Explicitly

- [x] Full Hono JSX clone is a non-goal.
- [x] Full Hono RPC TypeScript inference clone is a non-goal.
- [x] Every Hono middleware helper as built-in is a non-goal.
- [x] Serverless/edge adapter parity in P0 is a non-goal.
- [x] WebSocket parity in P0 is a non-goal.
- [x] GraphQL built-in support is a non-goal.

## Recommended Next Sprint

- [x] Finish response headers architecture and tests.
- [x] Implement first-class CORS helper and update benchmarks to assert headers/preflight.
- [x] Add cookie parse/set helper.
- [x] Add middleware response-mutation support.
- [x] Add OpenAPI metadata design doc from current route graph.
- [x] Add `meteorite invoke --headers` output.
- [x] Add Web Standards fixture with CORS, cookies, redirects, headers, HEAD, OPTIONS, and JSON validation routes.
