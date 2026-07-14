# Meteorite Web Standards Status + Plan

Purpose: turn Meteorite from a fast compiler prototype into a serious, standards-aligned HTTP application platform. This is a phased checklist, not a claim that every item is already complete.

Last reviewed: 2026-07-10

## Release Bar Definitions

- **P0 Serious Release:** safe HTTP/1.1 behavior, predictable request/response APIs, security defaults, benchmark honesty, and deployable static/hybrid releases.
- **P1 Competitive Web Platform:** middleware, response headers, cookies, streaming, multipart/forms, OpenAPI-ready schemas, and high-confidence interop tests.
- **P2 Differentiators:** compile-time graph guarantees, release manifest introspection, typed generated clients, edge/serverless adapters, and static/hybrid performance proofs.

## Phase 0 — Inventory And Claims Audit

- [x] Mark each benchmark scenario as one of: `static`, `hybrid(lua-runtime)`, `framework-parity`, or `proof-only`; keep detailed execution tiers separate.
- [x] Add preflight checks for every benchmark claim, not just body/status checks.
- [x] Ensure scenario names describe real behavior; rename or fix misleading routes such as `pipeline:cors` if no CORS header is emitted.
- [x] Add a generated `bench/results/*/claim-audit.md` with invalidation reasons and exact checks performed.
- [x] Confirm `release-static` and `release-hybrid` benchmark fixtures are exercising the intended runtime mode.
- [x] Document which generated artifacts must never be committed: `.meteorite/`, `.moonstone/env/`, `.zig-cache/`, runtime logs, pid files, and rebuilt `dist/server` unless intentionally versioned.

Generated-artifact policy: benchmark runs may create `.meteorite/graph/bench`, `.zig-cache/`, `zig-cache/`, `.moonstone/`, `.moonstone-home/`, `dist/server`, `bench/results/*`, competitor runtime logs, pid files, generated nginx configs, and temporary language build caches. These are local outputs and must not be committed unless a maintainer explicitly asks to version a fixture artifact.

## Phase 1 — HTTP/1.1 Correctness

- [x] Request parsing respects RFC token syntax for methods and header names.
- [x] Request header parsing rejects CRLF injection, oversized headers, malformed lines, and ambiguous folded headers.
- [x] URI length and header-size limits are documented and covered by tests.
- [x] Method handling returns correct `404`, `405`, and `Allow` headers where appropriate.
- [x] `HEAD` returns headers equivalent to `GET` without a body.
- [x] Persistent connections obey `Connection: close` and keep-alive semantics.
- [x] Request bodies honor `Content-Length`, EOF, empty body, body limit, and early close behavior.
- [x] Chunked request-body support is explicitly implemented or rejected with a clear status.
- [x] Response writer always emits valid status line, content length, connection policy, date, and content type when applicable.
- [x] Response header API prevents reserved header conflicts (`content-length`, `connection`, `transfer-encoding`, etc.).
- [x] Response header API rejects CRLF injection in names and values.
- [x] Static file serving sets stable `ETag`, `Cache-Control`, `Content-Type`, and conditional response behavior.
- [x] Static file serving protects against path traversal, symlink escapes, and ambiguous encoded path segments.

## Phase 2 — Request API Surface

- [x] Route params support typed access, missing-param diagnostics, and generated Zig context types.
- [x] Query parsing supports repeated keys, booleans, integers, optional values, malformed encoding behavior, percent-decoding, and multi-value access via `ctx:query_all()`.
- [x] Request headers are case-insensitive and exposed consistently to Lua and Zig handlers.
- [x] Cookies parser supports request cookies, quoted values, percent-encoding policy, and malformed cookie handling.
- [x] JSON body parser exists for Lua dev/invoke and runtime paths or is explicitly exposed as userland helper.
- [x] Form URL-encoded parser exists or is explicitly out of scope for P0.
- [x] Multipart form parsing has a P1 design covering limits, temp-file policy, streaming, and cleanup.
- [x] Raw body access is single-read or cached consistently across Lua/Zig paths.
- [x] Body parsing errors produce deterministic status and diagnostics.

Multipart P1 design: multipart parsing is intentionally not a P0 runtime helper. The P1 parser must be opt-in per route, require explicit `max_parts`, `max_field_bytes`, `max_file_bytes`, and total body limits, stream file parts to caller-owned temp storage or a configured sink, reject nested multipart by default, sanitize filenames as metadata only, clean partial temp files on disconnect/error, and expose deterministic `400`/`413` diagnostics. Until implemented, apps should use raw `ctx:body()` with route body limits or an external upload service for multipart traffic.

Query decoding policy: query parameter values are percent-decoded before validation and handler access in both the compiled Zig runtime and the local hybrid invoke path. This closes a previous inconsistency where form body and cookie values were decoded but query values were returned raw. The Zig `queryValue` function decodes into arena-allocated memory (zero-copy when no percent signs are present), and the Lua `parse_query` function applies the same `percent_decode` helper. Malformed percent-encoding (`%zz`, `%0a`) is still rejected at the server level by `queryEncodingValid` before values reach handlers.

Query multi-value policy: `ctx:query(name)` returns the first value for a repeated key (first-wins), matching previous behavior. `ctx:query_all(name)` returns all values as a Lua array (`string[]`), enabling handlers to access `?tag=pepe&tag=pope` as `{ "pepe", "pope" }`. The API is available in both the compiled runtime (Zig `Context.queryAll`, `l_query_all` binding, vtable entry) and the hybrid invoke path (`Context:query_all` method). The web standards fixture exercises both `query_all` and percent-decoded query values on the compiled server and through hybrid invoke.

## Phase 3 — Response API Surface

- [x] Lua response tables support `status`, `content_type`, `body`, and `headers`.
- [x] Bare string returns from Lua handlers produce `200 text/plain; charset=utf-8` consistently across compiled runtime and hybrid invoke.
- [x] `ctx:text`, `ctx:json`, and `ctx:bytes` support optional response headers.
- [x] Zig context has response helpers for text, JSON, bytes, redirects, empty status responses, and custom headers.
- [x] Header behavior is identical for `fast_http` and `std_http` backends.
- [x] JSON response encoding has a documented serializer and escaping policy.
- [x] Redirect helper validates status codes and `Location` values.
- [x] Cookie-setting helper supports `Set-Cookie` with secure defaults.
- [x] Streaming responses are designed before implementation: chunked transfer, flush semantics, backpressure, and Lua runtime constraints.
- [x] Response compression is opt-in and does not corrupt `Content-Length` or `ETag` semantics.

JSON response policy: Lua runtime `ctx:json()` uses Meteorite's built-in Lua-value encoder, not a host-dependent JSON library. It emits Lua arrays with contiguous integer keys as JSON arrays, other tables as JSON objects, `nil` as `null`, booleans and numbers as JSON primitives, unsupported Lua values as `null`, and escapes `\\`, `"`, and ASCII control bytes as JSON string escapes. Zig `ctx.json()` and `ctx.jsonWithHeaders()` intentionally accept already-encoded JSON bytes; typed Zig serialization is a separate P1 feature.

String-return policy: a bare string return from an inline Lua handler or scoped plugin `execute` function is sugar for `200 text/plain; charset=utf-8` with the string as the body. In the compiled runtime, `finishLuaResponse` detects `lua_isstring` and calls `vtable.text(ctx, 200, string)`. In the hybrid invoke path, string returns are normalized to `{ status = 200, content_type = "text/plain; charset=utf-8", body = result }` before response fields are attached. This fixes a previous inconsistency where hybrid invoke used `text/plain` without charset for string returns, plugin returns, 404/405, and 501 responses. Use string returns for simple status/echo endpoints; for custom status codes, content types, or headers, return a response table or use `ctx:text()`, `ctx:json()`, or `ctx:bytes()`.

Redirect policy: Zig `ctx.redirect(status, location)` accepts only `301`, `302`, `303`, `307`, or `308`, rejects empty or CRLF-containing `Location` values, and emits an empty response with a validated `Location` header. Lua can currently emit redirects with response tables; a Lua redirect helper remains part of cookie/response-builder follow-up work.

Streaming P1 design: streaming responses must be opt-in per route and backend, use HTTP/1.1 chunked transfer only when `Content-Length` is intentionally absent, expose explicit `write`/`flush`/`finish` semantics, propagate socket backpressure as write errors, abort cleanly on disconnect, and forbid yielding across unsafe embedded-Lua boundaries unless the route is marked as streaming-compatible. Static/hybrid non-streaming responses remain fixed-length by default.

Compression policy: response compression is currently an opt-in static-asset feature via prebuilt compressed variants. When `Accept-Encoding` selects a compressed artifact, Meteorite serves the compressed byte length, compressed artifact ETag, `Content-Encoding`, and `Vary: Accept-Encoding`; dynamic response compression is not enabled until it can preserve `Content-Length`, `ETag`, and streaming semantics.

Cookie-setting policy: `ctx:set_cookie()` in Lua and `ctx.setCookie()` in Zig build a validated `Set-Cookie` value with secure defaults: `Path=/`, `Secure`, `HttpOnly`, and `SameSite=Lax`. Cookie names must use HTTP token syntax, values must use RFC 6265 cookie-octets, attribute values reject control characters, CRLF, and semicolons, and `SameSite=None` is rejected unless `Secure` remains enabled. Response helpers still validate the final `Set-Cookie` header before writing it.

## Phase 4 — Middleware, Hooks, And Pipeline Semantics

- [x] Middleware has before/after semantics with deterministic ordering.
- [x] Middleware can short-circuit with a response.
- [x] Middleware can mutate response headers after handler execution.
- [x] Errors thrown in middleware/handlers route through a single error boundary.
- [x] Scoped plugins and mounted routes share the same middleware contract.
- [x] Pipeline stages document what they can read/write: request, params, query, state, response headers, body.
- [x] Hooks have test coverage for `pre_tree`, `post_match`, `pre_handler`, `post_handler`, `observe`, and `error` phases.
- [x] Compile-time graph validation rejects ambiguous or impossible middleware contracts.

Pipeline access contract: stages declare `reads` and `writes` as resource names. Stable P0 namespaces are `request.method`, `request.path`, `request.query`, `request.headers`, `route.params`, `route.policy`, `route.scope`, `state.*`, `response.status`, `response.headers`, `response.body`, `body`, and `error`. The graph builder validates hook declarations before codegen so impossible contracts fail at compile time instead of becoming runtime surprises.

Hook phase contract: `pre_tree` runs before route params exist and must not read params or mutate responses; `post_match` and `pre_handler` can inspect matched route facts but cannot mutate responses; `post_handler` may inspect and mutate responses; `observe` is read-only and cannot short-circuit; `error` can inspect structured errors and produce a response. Runtime execution for the full hook matrix remains separate from this compile-time contract slice.

Ordering contract: route pipelines are validated around the first `handle` stage. `pre_tree`, `post_match`, and `pre_handler` hooks must appear before `handle`; `post_handler`, `observe`, and `error` hooks must appear after `handle`. Transform stages remain order-preserving middleware and may appear before or after `handle` so plugins such as cache lookup/store can model before/after behavior without a separate stage kind.

Scoped middleware runtime: scoped Lua plugins execute before matched route handlers, can short-circuit by returning a response or calling a response helper, and share request-local string state with the eventual handler through `ctx:set()`/`ctx:get()`. Mounted child routes inherit the same plugin chain and scope context used by the route graph, so compiled fast_http/std_http behavior matches the local hybrid invoke contract for scoped plugins. Plugin `execute` string returns are now normalized to `text/plain; charset=utf-8` in hybrid invoke, matching the compiled runtime.

Error boundary runtime: scoped middleware/plugin failures, Lua handler failures, and Zig handler errors now route through the same route-level boundary. If no response has been committed, Meteorite returns `500 text/plain` with `internal server error` and `X-Meteorite-Error-Boundary: route`; if a response was already committed, the boundary logs and closes the connection rather than attempting a second response.

Post-handler mutation runtime: dynamic route responses are staged in request-local context and committed after route pipeline execution. Zig `post_handler` hooks can mutate validated response headers with `ctx.responseHeader()` before commit; fast_http and std_http both emit the final staged response with the post-handler headers. Direct scoped-plugin responses still short-circuit and commit immediately after the plugin chain returns.

## Phase 5 — Web Security Defaults

- [x] CORS helper covers origin matching, methods, headers, credentials, max-age, `Vary: Origin`, and preflight `OPTIONS`.
- [x] Secure headers helper covers common baseline headers with configurable policy.
- [x] Body limit helper applies globally and per-route.
- [x] CSRF story is documented for cookie-based apps.
- [x] Basic auth and bearer/JWT examples exist with constant-time secret comparison where relevant.
- [x] IP restriction / trusted proxy story is documented before adding proxy-sensitive features.
- [x] Request ID middleware/helper exists and flows through logs and response headers.
- [x] Logging avoids leaking secrets by default.

Secure headers policy: `ctx:secure_headers(opts)` returns a response-header table with conservative defaults: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and `Cross-Origin-Opener-Policy: same-origin`. Apps can opt into `Content-Security-Policy`, `Permissions-Policy`, and HSTS (`Strict-Transport-Security`) per route or helper wrapper; HSTS is intentionally opt-in so local HTTP/dev deployments are not accidentally pinned. Individual defaults can be disabled or overridden through options, and all output still passes Meteorite response-header validation.

CORS policy: `ctx:cors_headers(opts)` returns a validated response-header table for explicit route use rather than enabling global CORS by default. It supports exact origin allowlists, wildcard origin, reflected safe origins when credentials are enabled, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, `Access-Control-Allow-Credentials`, `Access-Control-Max-Age`, `Access-Control-Expose-Headers`, and `Vary: Origin`. Disallowed origins produce no CORS headers. Apps can attach the helper to normal responses and explicit `OPTIONS` routes; automatic framework preflight remains a conservative generic fallback only when no explicit `OPTIONS` route matches.

Request ID policy: `ctx:request_id()` returns a safe incoming `X-Request-ID` value when present, otherwise generates a 128-bit lowercase hex identifier and caches it for the request. Lua and Zig handlers can attach it to response headers with `X-Request-ID` and include it in application logs; invalid incoming IDs containing unsafe characters or excessive length are ignored rather than reflected.

Auth helper policy: `ctx:basic_auth()` parses `Authorization: Basic ...` into username/password, `ctx:bearer_token()` parses a single Bearer token, and `ctx:constant_time_equal(a, b)` provides a reusable comparison helper for secrets. The web standards fixture demonstrates both Basic and Bearer protected routes returning `WWW-Authenticate` challenges on failure. JWT validation remains an application/library concern until Meteorite has a first-class crypto/key-management contract; examples should still use constant-time comparison for shared secrets and avoid logging credentials or tokens.

CSRF policy: Meteorite does not enable ambient cookie-based mutation safety automatically. Cookie-authenticated apps should pair `SameSite=Lax` or `SameSite=Strict` cookies with per-request CSRF tokens for unsafe methods (`POST`, `PUT`, `PATCH`, `DELETE`), validate both the token and expected `Origin`/`Referer` when available, and keep CORS credentialed origins explicit. APIs authenticated only with non-cookie `Authorization` headers are not protected by CSRF tokens by default, but still need normal authorization checks.

Trusted proxy/IP policy: Meteorite treats proxy-derived headers such as `Forwarded`, `X-Forwarded-For`, `X-Real-IP`, and `CF-Connecting-IP` as untrusted application input until a first-class trusted-proxy configuration exists. Apps should not implement IP allow/deny decisions from those headers directly. Future proxy support must declare trusted proxy CIDRs/hops at compile time or startup, canonicalize a single client IP, and expose both raw and trusted values distinctly.

Logging policy: framework diagnostics avoid request header dumps, and application code should use `ctx:safe_header(name)` or `ctx:safe_headers(names)` for structured request logs. These helpers redact `Authorization`, `Cookie`, `Set-Cookie`, `Proxy-Authorization`, API-key/auth-token headers, and CSRF tokens while preserving non-sensitive selected headers such as request IDs and trace IDs.

## Phase 6 — Validation, Schemas, And Contracts

- [x] Route params, query, headers, cookies, JSON body, and form body share a common validator interface.
- [x] Validators produce stable runtime errors and compile-time graph metadata.
- [x] Schema metadata can emit JSON Schema or an intermediate representation suitable for OpenAPI.
- [x] OpenAPI export plan maps Meteorite route graph to paths, methods, params, query, request body, responses, and security schemes.
- [x] Generated route reports include validator coverage and missing response schema warnings.
- [x] Hybrid Lua validators and Zig validators have consistent semantics.

Validation metadata contract: route declarations now normalize params, query, headers, cookies, JSON body fields, and form body fields through the same schema map shape. The generated graph carries `route.validation.headers`, `route.validation.cookies`, `route.validation.json_body`, and `route.validation.form_body` alongside existing `params` and `query`; `routes.zon` exposes the same contract for tooling. Runtime validation remains implemented for params/query today, while the new metadata gives Phase 6 a stable source for header/cookie/body runtime validation, OpenAPI export, and consistent Lua/Zig typed contexts.

Validator coverage reporting: `build-report.txt` includes aggregate validator counts by domain (`params`, `query`, `headers`, `cookies`, `json`, `form`) so fixtures can assert coverage and release reports can flag missing schema areas. It also reports response schema coverage as declared vs missing counts, while `schemas.zon` and `openapi-plan.zon` preserve declared response schemas and mark undeclared responses with `missing_schema = true` placeholders.

Schema IR artifact: graph generation emits `schemas.zon` with format `meteorite.schema-ir.v0`. Each route entry maps params, query, headers, cookies, JSON body fields, and form body fields into an OpenAPI-ready object schema shape with `properties`, `required`, `additionalProperties = false`, scalar JSON Schema types, string formats (`uuid`, `email`), length constraints, numeric bounds, and Meteorite pattern IDs for DFA-backed validators.

OpenAPI plan artifact: graph generation emits `openapi-plan.zon` with format `meteorite.openapi-plan.v0` and target `openapi = "3.1.0"`. Each route entry includes the raw path, OpenAPI path template, method, operation id, parameters split by path/query/header/cookie location, request body media types for JSON and URL-encoded forms, placeholder response entries marked `missing_schema = true`, and security hints derived from auth capabilities plus header/cookie validators. This is an export plan, not a final OpenAPI JSON emitter yet.

Runtime validation diagnostics: query, header, cookie, JSON body, and URL-encoded form validators now fail with stable `400 validation error` responses when a matched route has missing or invalid fields. Responses include `X-Meteorite-Validation-Domain`, `X-Meteorite-Validation-Field`, and `X-Meteorite-Validation-Reason` (`missing` or `invalid`) across both HTTP backends. Path params remain route-matching constraints and continue to produce `404` when no route matches.

Local hybrid invoke consistency: `cli.hybrid.invoke()` now mirrors compiled runtime validator semantics for matched-route query, header, cookie, JSON body, and URL-encoded form validators, including the same `400 validation error` body and `X-Meteorite-Validation-*` headers. The hybrid invoke context also provides method-based access parity with the compiled runtime: `Context:query(name)`, `Context:param(name)`, and `Context:query_all(name)` are now available as methods rather than only table fields, matching the `.lazy_context` arg_mode contract used by inline Lua handlers that name their first parameter `ctx` or `c`. Bare string returns from handlers are normalized to `{ status = 200, content_type = "text/plain; charset=utf-8", body = result }` in hybrid invoke, matching the compiled runtime's `finishLuaResponse` string path. The web standards fixture runs direct local invoke checks for each validator domain, context method access, query decoding, query_all, and string-return content-type before exercising the compiled server.

Routes graph inspection: `meteorite routes --graph` now emits stable `meteorite.routes.v0` JSON for developer tooling. Each route entry includes method/path/handler facts, params and query schema summaries, header/cookie/JSON/form validation domains, declared response status schemas, runtime requirements, normalized scope plugin ids, and pipeline stages. The web standards fixture parses this JSON and asserts the validation contract route contains the expected params, validators, response schema, runtime flag, and root scope.

Local invoke inspection: `meteorite invoke` preserves the legacy tab-separated output by default and adds opt-in `--json` output with format `meteorite.invoke.v0`. JSON invoke responses include request method/path/headers plus response status, content type, headers, and body, while `-H/--header` lets local checks exercise header-driven behavior such as CORS. The web standards fixture asserts a CORS route through JSON invoke, including response headers.

Doctor readiness checks: `meteorite doctor` now reports project shape, `src/main.lua`, Moonstone env and Lua runtime, Meteorite CLI visibility, Zig version, Ballad plugin source, Ballad core availability, generated graph and LuaLS aids, static release readiness, hybrid release readiness, release partiture presence, and dev port state. The web standards fixture asserts the complete label set from an app-root run, including expected warnings for fixture-local release packaging gaps.

Init template coverage: `meteorite init --template` now accepts `minimal`, `static`, `hybrid`, `middleware`, `cors`, `json-api`, and `static-site`. The new focused starters cover scoped plugin middleware, explicit CORS and preflight responses, JSON body/query/param validation with response schemas, and `m.site()` static asset serving with immutable assets. Init also restores manifest and release partiture rendering for generated apps, and the web standards fixture generates and graphs every advertised template.

Compiler diagnostic shape: static-mode Lua retention and hybrid inline-Lua lifting failures now include `mode`, `route id`, method/path, source location, and a `remediation` section. Static failures point to `meteorite build --mode hybrid` or a static-safe Zig/file replacement, while lifting failures explain how to avoid upvalue capture or move the handler to `m.lua(...)`. The web standards fixture asserts both diagnostic paths.

Dev reload classification: the dev supervisor now distinguishes Lua-only handler chunk edits (`reload`), static asset/file handler edits (`rebuild` with asset reason), route graph-shape edits (`rebuild` with graph-shape reason), and Zig/build input edits (`rebuild` with Zig/build reason). Static assets are tracked as first-class `static_asset` partitions and common asset roots (`public`, `static`, `site`, `assets`) participate in the dev fingerprint. The web standards fixture exercises every classification path through generated partition changes.

## Phase 7 — Developer Experience

- [x] `meteorite routes --graph` emits stable JSON for route/middleware/validator inspection.
- [x] `meteorite doctor` checks Lua runtime, Zig version, Moonstone env, Ballad, ports, generated graph, and static/hybrid release readiness.
- [x] `meteorite invoke` returns status, content-type, headers, and body for local route checks.
- [x] Generated docs/stubs show complete context API, including response headers, cookies, `query_all`, and `param` methods. The `meteorite.lua` facade now defines `MeteoriteContext` with all 30+ method/field annotations, plus `MeteoriteHttpClient`, `MeteoriteAuthClient`, `MeteoriteZigClient`, `MeteoritePlugin`, and `MeteoriteHttpResponse` classes for LuaLS/EmmyLua IDE support without requiring a build.
- [x] `meteorite init` templates include static, hybrid, middleware, CORS, JSON API, and static-site examples.
- [x] Error messages identify source location, route id, mode, and remediation.
- [x] Dev reload differentiates Lua-only, graph-shape, Zig, and asset changes.

LuaLS annotation coverage: the `meteorite.lua` facade now carries inline `---@class MeteoriteContext` annotations with all context methods (`query`, `query_all`, `param`, `header`, `body`, `json_body`, `form_body`, `text`, `json`, `bytes`, `cookie`, `set_cookie`, `request_id`, `secure_headers`, `cors_headers`, `constant_time_equal`, `basic_auth`, `bearer_token`, `safe_header`, `safe_headers`, `log`, `timing_stage`, `server_timing`, `http`, `auth`, `zig`, `get`, `set`, `scope`) so language servers provide autocomplete and type checking before a build generates the full per-route meta files. The `MeteoriteHandler` alias documents that string returns produce `200 text/plain; charset=utf-8`, table returns provide `{status?, content_type?, body?, headers?}`, and `nil` means no response. The generated `report.lua` LuaLS output also includes `query_all` and `param` method annotations. `docs/examples.md` documents the `arg_mode` contract: `ctx`/`c` → `lazy_context` (method-based access), `req` → `request_table` (pre-populated table access), no params → `no_args`, other names → `direct_params`.

## Phase 8 — Release And Deployment

Release manifest metadata: `meteorite-release.json` now exposes `graph_hash`, `route_count` (while preserving legacy `routes`), target ABI, retained Lua node count and details, static asset count/list, runtime source packaging status, packaged runtime source artifact path, and source kind. Static release manifests also record the no-Lua-runtime guarantee with `static.lua_runtime_execution_nodes = 0` when the contract passes. The web standards fixture unit-builds representative static and hybrid manifests and asserts all of these fields.

Static release guarantee: static release export now performs a second post-emission graph assertion and a final asset-set assertion before returning deployable assets. The graph assertion rejects any retained inline/file Lua handlers or Lua plugin execution nodes after codegen; the asset assertion rejects Lua runtime trees, runtime source archives, Lua module/C-module trees, lifted inline chunks, Lua handler/plugin files, and copied Lua source paths in static releases. The web standards fixture exercises both guard paths plus an allowed static server/static-asset set.

Hybrid Lua asset minimization: hybrid release packaging now starts from retained runtime nodes instead of copying the whole application `src/` tree. It packages lifted inline chunks, explicit Lua route/plugin handler files, and project-local `require(...)` dependencies discovered from those files, tagging transitive dependencies as `meteorite_lua_module`. Unreferenced app source files are omitted; package module trees and native C modules remain collected through Moonstone package facts, with native C modules skipped for cross-target unless rebuilt through the target C-module task path. The web standards fixture verifies inline chunk, Lua handler, transitive module, and unused-source behavior.

Cross-target provenance gate: cross-target hybrid release fails before native build tasks if retained Lua runtime nodes require target Lua but no Lua runtime source provenance is available, if the provided runtime payload is a prebuilt `runtime` artifact instead of rebuildable source, or if Lua C modules lack source/rockspec provenance. Diagnostics include target ABI, missing provenance field names, retained Lua node references when relevant, and remediation text. The web standards fixture asserts missing runtime source, rejected prebuilt runtime kind, and missing C-module source provenance.

Copied release smoke: the static release smoke now parses the actual `meteorite-release.json`, asserts static no-Lua guarantees, copies `dist/release` to a fresh deploy directory, verifies no source/runtime trees are present, temporarily moves the source `site/dist` tree away, starts the server from the copied deploy root, waits for readiness, and serves static routes from the copied release only. The smoke uses Ballad's non-symlinked dist Lua path for `dkjson` so it does not depend on external Moonstone store symlink readability.

Safe runtime build info: servers now expose `GET /__meteorite/info` with stable `meteorite.info.v0` JSON containing build mode, optimization, target triple, backend, connection/worker strategy, queue settings, router dispatch, Lua runtime flag, hybrid profile, Lua state/ref/cache strategies, and capability store strategy. The endpoint intentionally reports only enum/string/count build facts and no project roots, graph paths, source paths, or absolute host paths. Release smoke asserts the copied `std_http` release reports safe static config; the web standards fixture asserts the same no-path contract for `fast_http` hybrid builds.

Container deployment recipe: `deploy/Dockerfile.release` packages an already-built `dist/release` directory into `/app`, runs as an unprivileged `meteorite` user, exposes port 8080, and starts `/app/bin/server`. `deploy/README.md` documents the required `dist/release` build context, safe info endpoint check, and Linux-compatible binary requirement. Release smoke asserts the recipe files and key Dockerfile contract so the documented path remains present.

Signal and cleanup coverage: release smoke now terminates the copied release server through `scripts/guard.sh cleanup`, verifies the server logs `Shutting down...`, runs `scripts/guard.sh assert-free`, and checks port 8080 has no remaining listeners. The guard sends a wake-up request to `GET /__meteorite/info` after TERM so blocking accept loops observe the shutdown flag before escalation, and cleanup is best-effort while `assert-free` remains the strict port-occupancy gate.

- [x] Release manifests include graph hash, route count, retained Lua nodes, static assets, runtime source, and target ABI.
- [x] Static releases guarantee no Lua runtime execution nodes.
- [x] Hybrid releases package only necessary Lua files/modules and native modules.
- [x] Cross-target hybrid fails early if source provenance is missing.
- [x] Release smoke tests run from a copied directory with source removed.
- [x] Server reports build configuration at runtime without exposing host paths.
- [x] Docker/container recipe exists for representative deployment.
- [x] Signal handling, graceful shutdown, and port cleanup are tested.

## Phase 9 — Performance And Observability

Benchmark observability baseline: `bench/lib/verify.sh` preflights each scenario for status, body, content-type, required headers, fixture identity, worker/runtime config, and server liveness before any row can run. Meteorite rows reset and sample `GET /__bench/stats` plus `GET /__bench/meta` around each loadgen run, so Lua-dependent tiers can be invalidated by pcall undercounts and runtime pressure fields are captured alongside load generator output.

Per-row loadgen telemetry: `bench/lib/matrix.sh` records configured concurrency/threads, target QPS, warmup/loadgen exit codes, loadgen CPU, non-2xx counts, split socket connect/read/write/timeout errors, aggregate socket errors, server/loadgen FD counts and maxima, queue depth, inflight, budget rejections, and backpressure. `bench/report/summary.py` carries those fields into `summary.json` and claim-grade notes so performance claims are quarantined when transport, FD, runtime-counter, or parser evidence is missing.

Safe server counter endpoint: Meteorite benchmark builds expose `GET /__bench/meta` and `GET /__bench/stats` with non-secret runtime counters only: accepted/completed request totals, open/inflight current and max values, queue depth and max queue depth, worker queue max, budget rejections, backpressure, dropped/connection errors, bytes read/written, worker/thread count, and Lua runtime stats. The endpoint is fixture-scoped to bench builds and avoids host paths or source-bearing fields.

Logging middleware/helper support: Lua contexts now expose `ctx:log(level, message, fields, opts)` in both embedded runtime and dev/invoke. It emits structured JSON by default or key/value plain text with `{ format = "plain" }`, includes `request_id`, strips CR/LF/NUL from log fields, caps string fields, and composes with `ctx:safe_header()` / `ctx:safe_headers()` so sensitive request headers are redacted before application logs. The web standards fixture asserts both JSON and plain log lines.

Timing middleware/helper support: Lua contexts now expose `ctx:timing_stage(metrics, name, fn, opts)` and `ctx:server_timing(metrics)` in both embedded runtime and dev/invoke. The helper records stage durations in milliseconds, sanitizes metric tokens/descriptions for the HTTP `Server-Timing` grammar, supports explicit metrics such as response-write timing, and returns a normal response-header table so routes or post-handler middleware can attach timing data without backend-specific code. The web standards fixture asserts `Server-Timing` contains handler and response metrics.

Profiling cost breakdown: `bench/profile-costs.py` consumes `summary.json` and emits `profile-costs.md` plus `profile-costs.json` beside benchmark summaries. It uses differential scenario pairs to estimate router/typed-param, parser/body-parse, Lua bridge, handler compute, body IO, and response writer costs, while marking missing or non-claim-grade source rows as notes instead of silently inventing numbers. `bench/run.sh` now generates this report automatically after `summary.json` exists.

- [x] Every benchmark preflights body, status, content-type, required headers, runtime counters, and server liveness.
- [x] Lua runtime benchmark rows require pcall/counter proof where claims depend on Lua execution.
- [x] Load generator CPU, socket errors, non-2xx, FD pressure, queue depth, and backpressure are recorded per row.
- [x] Server exposes safe counters for accepted/completed requests, inflight, queue depth, errors, bytes, and worker count.
- [x] Logging middleware supports structured JSON and plain text.
- [x] Timing middleware can add `Server-Timing` and record per-stage durations.
- [x] Profiling scripts distinguish router, parser, Lua bridge, handler, body IO, and response writer cost.

## Immediate Must-Do Before Claiming Serious Release

- [x] Finish response-header support across Lua runtime, dev/invoke, `fast_http`, and `std_http`.
- [x] Make CORS benchmark emit and assert `Access-Control-Allow-Origin: *`.
- [x] Add first-class CORS helper design beyond basic `OPTIONS` preflight support.
- [x] Add `HEAD` correctness tests.
- [x] Add response-header injection tests.
- [x] Add method `Allow` header behavior or document current behavior.
- [x] Expand Web Standards smoke fixture to cover static files and conditional requests.

Response-header injection coverage: the web standards fixture now exercises invalid response headers from Lua response tables, Lua helper options, Zig response helpers, and Zig post-handler mutation. It asserts each rejected path returns the route error boundary and that CRLF-injected `Injected:` headers or rejected header values are never emitted. The route error boundary now distinguishes staged responses from committed responses so post-handler header validation failures can safely replace the staged body with the standard 500 boundary response instead of closing the socket.
