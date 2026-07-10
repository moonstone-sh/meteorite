# Meteorite ↔ Hono Sensible Feature Parity Plan

Purpose: identify which Hono features matter for a serious Meteorite release, decide what must be first-class vs. intentionally out of scope, and track parity with checkboxes.

Sources reviewed on 2026-07-07:

- Hono docs home: https://www.honojs.com/docs/
- Hono routing docs: https://hono.dev/docs/api/routing
- Hono middleware docs: https://hono.dev/docs/guides/middleware
- Hono validation docs: https://hono.dev/docs/guides/validation
- Hono RPC docs: https://hono.dev/docs/guides/rpc
- Hono WebSocket helper docs: https://hono.dev/docs/helpers/websocket
- Hono JSX docs: https://hono.dev/docs/guides/jsx
- Hono OpenAPI example: https://hono.dev/examples/hono-openapi

Hono positioning to respect: it is a small, ultrafast framework built on Web Standards and runs across runtimes including Cloudflare Workers, Fastly Compute, Deno, Bun, Vercel, Netlify, AWS Lambda/Lambda@Edge, and Node.js. Its serious-release feature surface is not only speed; it also includes routing, middleware, helpers, validation, RPC, JSX/html, WebSockets, and ecosystem integrations.

## Parity Strategy

- **Do not clone Hono.** Meteorite is a compiler: Lua declares, Zig compiles, releases are static or hybrid.
- **Match the serious expectations.** Users will expect routing, middleware, validation, CORS, cookies, auth helpers, OpenAPI, and excellent DX.
- **Lean into Meteorite strengths.** Compile-time graph validation, generated Zig contexts, static/hybrid release gates, target Lua packaging, and runtime counters should exceed Hono where possible.
- **Treat parity as product requirements.** A missing feature needs either an implementation plan or a clear non-goal.

## Status Legend

- [ ] Missing or not validated
- [ ] Partial / needs design
- [ ] Implemented but needs tests/docs
- [ ] Release-ready

## Phase H0 — Core Hono-Like Routing Expectations

Hono docs emphasize flexible routing, method-specific handlers, wildcard routes, host/header-derived routing customization, and registration-order priority.

- [ ] `GET`, `POST`, `PUT`, `PATCH`, `DELETE` route declarations are documented and tested.
- [ ] `HEAD` and `OPTIONS` behavior is defined and tested.
- [ ] `app:all()` or equivalent any-method route support exists or is explicitly out of scope.
- [ ] Wildcard route matching exists or has a design.
- [ ] Param route matching supports typed extraction and source diagnostics.
- [ ] Route priority/order semantics are explicit; static vs param vs wildcard behavior is deterministic.
- [ ] Mounted apps/scopes behave like route groups.
- [ ] Host/header-aware routing is evaluated as P1: useful, but not P0 unless multi-tenant routing is a target.
- [ ] 404/405 behavior is aligned with web expectations and includes `Allow` for 405.

## Phase H1 — Context And Request/Response API

Hono’s DX is centered around an easy context object and Web-standard Request/Response style behavior.

- [ ] Lua `ctx` exposes params, query, state, scope, request headers, body, and response helpers.
- [ ] Zig generated contexts expose typed params/query and response helpers.
- [ ] Response helpers support text, JSON, bytes, redirects, custom status, custom headers, and empty bodies.
- [ ] Response headers work in returned Lua response tables and direct helpers like `ctx:text(..., { headers = ... })`.
- [ ] `meteorite invoke` prints or returns response headers for local testing.
- [ ] Request parsing supports JSON, form, query, header, param, and cookie validation targets comparable to Hono validation docs.
- [ ] Context-local storage/state semantics are documented and tested for scoped plugins and nested mounts.

## Phase H2 — Middleware System

Hono middleware can run before/after handlers, call `next()`, short-circuit, and compose in registration order. Hono catches thrown errors and routes them through error handling.

- [ ] Meteorite pipeline has middleware-like before/after semantics that users can understand without compiler internals.
- [ ] Middleware can short-circuit with a response.
- [ ] Middleware can mutate response headers after handler execution.
- [ ] Middleware ordering is registration-order or documented equivalent.
- [ ] Scoped middleware works for route groups/mounts.
- [ ] Error propagation from middleware and handlers uses a single `on_error`/error hook contract.
- [ ] Middleware source locations appear in diagnostics.
- [ ] Middleware effects are captured in graph metadata for release inspection.

## Phase H3 — Built-In Middleware And Helpers That Matter

Hono docs list built-ins/helpers including Basic Auth, Bearer Auth, Body Limit, Cache, Compress, Context Storage, Cookie, CORS, ETag, html, JSX, JWT, Logger, Pretty JSON, Secure Headers, SSG, Streaming, GraphQL, Firebase Auth, Sentry, and more. Meteorite should prioritize the ones that are core to API/server releases.

### P0 Helpers

- [ ] CORS helper: origin rules, methods, allowed headers, exposed headers, credentials, max-age, `Vary`, and preflight `OPTIONS`.
- [x] Body limit helper: global and route-level limits with deterministic errors.
- [ ] Logger helper: basic structured request logging with redaction.
- [ ] Secure headers helper: sane defaults with opt-out.
- [x] Cookie helper: parse request cookies and set response cookies.
- [ ] ETag/static cache helper: static files covered; optional dynamic response helpers remain.
- [ ] Request ID helper: generate/propagate request IDs.

### P1 Helpers

- [ ] Basic Auth helper.
- [ ] Bearer/JWT auth helper or documented integration path.
- [ ] Pretty JSON helper for dev/debug only.
- [ ] Compression helper with correct `Vary`, `Content-Length`, and ETag behavior.
- [ ] Timeout helper with cancellation semantics.
- [ ] Timing helper / `Server-Timing` support.
- [ ] Trailing slash middleware policy.
- [ ] Method override policy if HTML forms are a target.
- [ ] IP restriction / trusted proxy story.
- [ ] CSRF helper if cookie-auth apps are a target.

### P2 / Ecosystem Integrations

- [ ] GraphQL integration example or non-goal.
- [ ] Sentry/observability integration hook example.
- [ ] Firebase/Auth.js/Better Auth style examples if user demand appears.
- [ ] SSG/static generation story for `m.site()` or release export.

## Phase H4 — Validation And Type/Schema Story

Hono provides a thin validator and supports validation targets: `json`, `query`, `header`, `param`, `cookie`, and `form`; Hono RPC uses validator output for client inference.

- [ ] Meteorite schema validators cover params, query, headers, cookies, JSON body, form body, and raw body constraints.
- [ ] Validation errors return configurable but stable status/body format.
- [ ] Validators generate graph metadata usable for docs and clients.
- [ ] Runtime validation behavior matches dev/invoke validation behavior.
- [ ] Third-party Lua validators have an extension point without undermining release graph determinism.
- [ ] Header validators are case-insensitive where appropriate.
- [ ] Cookie validators handle absent, malformed, and repeated cookies.
- [ ] Form validators document content-type requirements.

## Phase H5 — RPC / Generated Client Parity

Hono RPC shares server API specs with clients through TypeScript types and its client helper. Meteorite cannot mirror this exactly in Lua/Zig, but it can compete with graph-derived clients.

- [ ] Decide target client outputs: TypeScript, Lua, OpenAPI-only, or all three.
- [ ] Export route graph metadata with methods, paths, params, query, body, responses, and errors.
- [ ] Generate TypeScript client from graph/OpenAPI for serious web-app adoption.
- [ ] Generate Lua client for Moonstone/Meteorite service-to-service calls.
- [ ] Include response status/content-type/header schemas in generated metadata.
- [ ] Provide compatibility tests for generated clients against `meteorite invoke` and live server.
- [ ] Document where Meteorite’s compile-time graph offers stronger guarantees than Hono RPC.

## Phase H6 — OpenAPI And Documentation

Hono’s OpenAPI ecosystem uses middleware such as `hono-openapi`, schema validators, route descriptions, response schemas, and an `/openapi` endpoint.

- [ ] Define Meteorite route-description DSL for summary, description, tags, operation id, and response schemas.
- [ ] Map Meteorite validators to JSON Schema/OpenAPI components.
- [ ] Emit OpenAPI 3.1 from the normalized graph.
- [ ] Add optional `/openapi.json` route for dev/hybrid mode or generated static asset for releases.
- [ ] Add Swagger UI or Redoc static template as optional release asset.
- [ ] Validate generated OpenAPI in tests.
- [ ] Detect undocumented routes before serious release and warn/fail by mode.

## Phase H7 — HTML, Templates, JSX Equivalent

Hono supports html helpers, JSX, JSX renderer middleware, streaming JSX, and SSG. Meteorite does not need JSX specifically, but serious contenders need an HTML/rendering story.

- [ ] Document HTML response helper for Lua and Zig.
- [ ] Provide safe HTML escaping helper.
- [ ] Decide supported template story: `etlua`, custom compiler, static pre-render, or all.
- [ ] Ensure templates work in static and hybrid release modes where applicable.
- [ ] Add examples for template layout, partials, and static asset integration.
- [ ] Evaluate streaming HTML as P2 unless needed for competitive demos.
- [ ] Decide whether SSG belongs in Meteorite or Ballad release tasks.

## Phase H8 — WebSockets And Streaming

Hono has a WebSocket helper with `onOpen`, `onMessage`, `onClose`, and `onError`, and Hono documents middleware/header caveats around upgrades. Hono also has streaming helpers.

- [ ] Decide if WebSocket is in scope for the next serious release; if not, mark as explicit P2.
- [ ] If in scope, design upgrade handling in `fast_http` and `std_http` separately.
- [ ] Define Lua handler lifecycle for WebSocket callbacks and state.
- [ ] Define backpressure, message size, close codes, ping/pong, and error behavior.
- [ ] Ensure middleware/header mutation does not conflict with upgrade responses.
- [ ] Design streaming responses separately from WebSockets: chunked transfer, flush, cancellation, and Lua bridge lifetime.

## Phase H9 — Runtime/Adapter Story

Hono wins mindshare partly by running across many JS runtimes. Meteorite’s equivalent is deployment clarity across native targets.

- [ ] Static binary story is documented as the default production advantage.
- [ ] Hybrid release story documents Lua runtime packaging and target ABI.
- [ ] Cross-target release diagnostics are friendly and early.
- [ ] Container deployment template exists.
- [ ] Systemd/launchd/supervisor examples exist.
- [ ] Serverless/edge story is explicitly out of scope or planned as adapter work.
- [ ] Graceful shutdown and health/readiness endpoints are documented.

## Phase H10 — Serious Release Must-Haves

These are the minimum must-haves to be taken seriously against Hono for API services, even if Meteorite is not trying to be a TypeScript framework.

- [ ] Routing: methods, params, query, scoped mounts, deterministic priority.
- [ ] Middleware: before/after, short-circuit, response mutation, error boundary.
- [x] Request API: headers, body, params, query, cookies.
- [x] Response API: status, body, content type, custom headers, cookies, redirects, JSON.
- [ ] CORS: real helper plus benchmark/header tests.
- [ ] Validation: params/query/body/header/cookie with graph metadata.
- [ ] OpenAPI: generated spec from graph.
- [ ] Dev UX: `init`, `doctor`, `routes`, `invoke`, hot reload, clear diagnostics.
- [ ] Release UX: static/hybrid gates, manifest, smoke tests, no source leaks.
- [ ] Performance UX: honest benchmark proof with counters and invalidation reasons.
- [ ] Docs: copyable examples for JSON API, CORS, auth, cookies, static site, OpenAPI, and hybrid Lua.

## Non-Goals To Decide Explicitly

- [ ] Full Hono JSX clone.
- [ ] Full Hono RPC TypeScript inference clone.
- [ ] Every Hono middleware helper as built-in.
- [ ] Serverless/edge adapter parity in P0.
- [ ] WebSocket parity in P0.
- [ ] GraphQL built-in support.

## Recommended Next Sprint

- [ ] Finish response headers architecture and tests.
- [ ] Implement first-class CORS helper and update benchmarks to assert headers/preflight.
- [x] Add cookie parse/set helper.
- [ ] Add middleware response-mutation support.
- [ ] Add OpenAPI metadata design doc from current route graph.
- [ ] Add `meteorite invoke --headers` output.
- [ ] Add `WEB_STANDARDS.md` fixture with CORS, cookies, redirects, headers, HEAD, OPTIONS, and JSON validation routes.
