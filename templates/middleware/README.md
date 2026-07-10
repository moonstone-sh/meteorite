# {{name}}

A Meteorite middleware starter using scoped plugins, request headers, short-circuit responses, and request-local state.

## Try it

```bash
moon sync
meteorite doctor
meteorite invoke src/main.lua GET /health
meteorite invoke --json src/main.lua GET /api/me
meteorite invoke --json -H "Authorization: Bearer dev" src/main.lua GET /api/me
moon run dev
```

Use this template when you want route groups with shared auth, tenant context, or observability hooks before the handler runs.
