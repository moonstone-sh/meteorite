# Meteorite OpenAPI 3.1 Design

## Overview

Meteorite generates OpenAPI 3.1 specifications directly from the normalized route
graph at build time. No middleware, no runtime annotation scanning — the spec is a
compile-time artifact produced by the graph emitter alongside `graph.zig`,
`routes.zon`, and `schemas.zon`.

## How It Works

### Graph → OpenAPI Pipeline

```
src/main.lua (Lua DSL)
      │
      ▼
app:normalize({ mode = ... })
      │
      ▼
normalized graph (routes, params, query, validation, responses, scope)
      │
      ├──▶ openapi-plan.zon     (per-route plan, intermediate)
      ├──▶ schemas.zon          (schema IR for codegen)
      └──▶ openapi.json         (final OpenAPI 3.1 document)
```

### Source Files

| File | Role |
|------|------|
| `src/codegen/openapi.lua` | OpenAPI 3.1 document builder |
| `src/codegen/report.lua` | `openapi_plan()` — per-route intermediate plan |
| `src/codegen/emitter.lua` | Wires `openapi.json` emission into graph build |
| `.meteorite/graph/current/openapi.json` | Generated spec (dev/build output) |
| `.meteorite/graph/current/openapi-plan.zon` | Intermediate per-route plan (ZON format) |

### Using the Generated Spec

```bash
# Generate graph (includes openapi.json)
meteorite graph src/main.lua .meteorite/graph/current hybrid

# View the spec
cat .meteorite/graph/current/openapi.json | python3 -m json.tool

# Generate a transport-agnostic Lua client from the same route graph
meteorite client lua src/main.lua .meteorite/client.lua

# Serve it with Swagger UI (optional)
# Copy openapi.json to a static directory and point Swagger UI at it
```

## OpenAPI 3.1 Mapping

### Paths

Meteorite route paths are converted to OpenAPI path templates:

| Meteorite Path | OpenAPI Template |
|----------------|-----------------|
| `/users` | `/users` |
| `/users/:id` | `/users/{id}` |
| `/files/:path*` | `/files/{path}` |
| `/static/*` | `/static/{wildcard}` |

### Methods

| Meteorite Method | OpenAPI Operation Key |
|-----------------|----------------------|
| `GET` | `get` |
| `POST` | `post` |
| `PUT` | `put` |
| `PATCH` | `patch` |
| `DELETE` | `delete` |
| `HEAD` | `head` |
| `OPTIONS` | `options` |
| `ALL` (app:all) | All seven operations emitted |

### Parameters

Meteorite validators map to OpenAPI parameters:

| Validator Domain | OpenAPI `in` |
|-----------------|-------------|
| `params` | `path` (always required) |
| `query` | `query` |
| `headers` | `header` |
| `cookies` | `cookie` |

### Schema Types

| Meteorite Type | OpenAPI/JSON Schema |
|---------------|-------------------|
| `string` | `{ "type": "string" }` |
| `u64` | `{ "type": "integer", "minimum": 0 }` |
| `i32` | `{ "type": "integer" }` |
| `bool` | `{ "type": "boolean" }` |
| `uuid` | `{ "type": "string", "format": "uuid" }` |
| `email` | `{ "type": "string", "format": "email" }` |
| `hex` | `{ "type": "string", "pattern": "^[0-9A-Fa-f]+$" }` |
| `slug` | `{ "type": "string", "pattern": "^[A-Za-z0-9_-]+$" }` |
| `token` | `{ "type": "string", "pattern": "^[A-Za-z0-9._~-]+$" }` |
| `pattern` | `{ "type": "string", "x-meteorite-pattern-id": "<id>" }` |

Additional constraints (`max_len`, `exact_len`, `min`, `max`) map to
`maxLength`, `minLength`/`maxLength`, `minimum`, `maximum` respectively.

### Request Bodies

When a route declares `json` or `form` validators, the OpenAPI operation includes
a `requestBody` with the appropriate content type:

```json
{
  "requestBody": {
    "required": false,
    "content": {
      "application/json": {
        "schema": {
          "type": "object",
          "properties": { ... },
          "required": [ ... ],
          "additionalProperties": false
        }
      }
    }
  }
}
```

### Responses

Route `responses` declarations map to OpenAPI response objects:

```lua
app:post("/users", {
  responses = {
    [201] = { json = { id = m.u64(), name = m.string() } },
    [400] = { description = "validation error" },
  },
}, function(c) ... end)
```

Produces:

```json
{
  "responses": {
    "201": {
      "description": "Response for status 201",
      "content": {
        "application/json": {
          "schema": {
            "type": "object",
            "properties": {
              "id": { "type": "integer", "minimum": 0 },
              "name": { "type": "string" }
            },
            "required": ["id", "name"],
            "additionalProperties": false
          }
        }
      }
    },
    "400": {
      "description": "validation error"
    }
  }
}
```

Routes without declared responses get a `default` response with a
"schema not declared" description.

### Security Schemes

Meteorite infers security schemes from validation headers and cookies:

| Detection | OpenAPI Scheme |
|-----------|---------------|
| `Authorization` header validator | `bearerAuth`: `{ "type": "http", "scheme": "bearer" }` |
| Cookie validator (e.g. `session`) | `cookie_<name>`: `{ "type": "apiKey", "in": "cookie", "name": "<name>" }` |

Operations that require auth get a `security` array referencing the scheme.

### Tags

Route scope IDs (from `app:mount("/prefix", { id = "billing" }, ...)`) become
OpenAPI tags. Routes at the root scope have no tag.

## Validation

The generated `openapi.json` is valid OpenAPI 3.1.0 JSON that can be consumed by:

- Swagger UI / Redoc for documentation
- `openapi-generator` for client SDK generation
- API gateways for request validation
- Development tools for type inference

## Design Decisions

### Why Compile-Time?

Meteorite is a compiler. The graph is fully known at build time — there is no
runtime route registration or dynamic middleware that changes the API surface.
Generating the spec at build time means:

- The spec is always in sync with the binary
- No runtime overhead for spec generation
- The spec can be diffed between releases
- Schema validation is already done by the Meteorite graph validator

### Why Not Middleware?

Hono's OpenAPI ecosystem uses runtime middleware (`hono-openapi`) that intercepts
routes and builds the spec on demand. Meteorite's equivalent is the graph emitter:
the spec is a build artifact, not a runtime concern. This is stronger for release
correctness — the spec cannot drift from the deployed binary.

### Intermediate Plan vs. Final Spec

The `openapi-plan.zon` file is an intermediate representation that preserves
Meteorite-specific metadata (route IDs, canonical IDs, message projections). The
`openapi.json` file is the final, standards-compliant spec for external consumers.

## Implemented And Future Work

- [x] Optional `/__meteorite/openapi.json` route for dev/hybrid mode
- [x] Route-description DSL (`summary`, `description`, `tags`, `operationId`, `responses`)
- [x] TypeScript client generation path via standard OpenAPI tools
- [x] Detect undocumented routes and warn in release modes
- [x] Generated Lua client for service-to-service calls (`meteorite client lua`)
- [x] Compatibility tests for generated Lua client request construction
- [ ] Swagger UI static template as optional release asset
- [ ] Promote undocumented-route diagnostics from warning to fail-by-mode if v0.1 requires strict docs

## Client Generation Strategy

### Decision: OpenAPI-First, TypeScript and Lua as Targets

Meteorite's compile-time graph produces a complete `openapi.json` at build time.
This is the primary client-generation artifact. The strategy is:

1. **OpenAPI 3.1 JSON** is the canonical spec — generated by `src/codegen/openapi.lua`
   during every `meteorite graph` or `meteorite build` run.

2. **TypeScript client** — generated from `openapi.json` using standard tools
   like `openapi-generator` or `hey-api/openapi-ts`. No custom Meteorite tooling
   needed; the spec is standards-compliant.

3. **Lua client** — for Moonstone/Meteorite service-to-service calls. Can be
   generated from `openapi.json` or directly from the route graph metadata
   (`routes.zon`, `schemas.zon`) for tighter integration with Meteorite's
   typed param/query validators.

4. **No runtime inference** — unlike Hono RPC which relies on TypeScript
   type-level inference at build time, Meteorite's spec is a serialized artifact
   that can be consumed by any language or tool.

### Compile-Time Graph Guarantees vs Hono RPC

| Guarantee | Hono RPC | Meteorite Graph |
|-----------|----------|-----------------|
| Route shape known at build time | TypeScript types | Lua graph + Zig comptime |
| Param/query/body types validated | TypeScript inference | Schema validators → DFA + Zig comptime |
| Response schema enforced | TypeScript return type | `responses` declaration → OpenAPI + Zig |
| Spec drift from binary | Possible (runtime middleware) | Impossible (compile-time artifact) |
| Cross-language client | TypeScript only | Any language via OpenAPI 3.1 JSON |
| Static mode guarantees | N/A | No Lua runtime, no spec drift |
| Undocumented route detection | Manual | Build-time warning in release modes |

Meteorite's compile-time graph offers stronger guarantees than Hono RPC because:

- The OpenAPI spec is emitted from the same graph that compiles the Zig binary.
  They cannot drift.
- Static mode guarantees no Lua runtime nodes remain — the spec and binary
  are purely Zig.
- Schema validators compile to DFA pattern matchers and Zig comptime checks,
  not runtime validation.
- Undocumented route detection runs at build time in release modes.
- The spec is a serialized JSON artifact, not a type-level construct tied to
  one language's compiler.
