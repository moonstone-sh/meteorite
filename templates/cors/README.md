# {{name}}

A Meteorite CORS starter with explicit `OPTIONS` handling and reusable `ctx:cors_headers()` policy.

## Try it

```bash
moon sync
meteorite invoke --json -H "Origin: https://app.example" src/main.lua GET /health
meteorite invoke --json -H "Origin: https://app.example" src/main.lua OPTIONS /api/messages
moon run dev
```

Keep allowed origins explicit for credentialed requests. Use `origin = "*"` only for public, non-credentialed APIs.
