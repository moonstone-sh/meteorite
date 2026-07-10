# Web Standards Fixture

Focused HTTP standards fixture for Meteorite runtime behavior that should be stable across backends and release modes.

Initial coverage:

- Lua response tables with custom headers
- `ctx:text`, `ctx:json`, and `ctx:bytes` response helper header options
- CORS response headers on simple GET routes
- Redirect-style responses with `Location`

Covered by `fixtures/tests/web-standards.sh`.
