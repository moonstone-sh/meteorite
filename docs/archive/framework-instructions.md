# Implement Framework Benchmarks

You are responsible for implementing a benchmark server for a specific Lua web framework.
We are comparing them against Meteorite.

Implement these 11 endpoints exactly. They MUST return a 200 OK with the exact body string shown below, and a `text/plain` content type.

1. `GET /__app/json/encode-small` -> `json:encode-small:<name>:<n>:<ok>`
   Logic: Encode `{ok=true, name="meteorite", n=123}`, then decode it, and return the formatted string.
2. `POST /__app/json/decode-1kb` -> `json:decode-1kb:<name>:<n>:<payload_start>`
   Logic: Read JSON body. Decode it. Extract `name`, `n`, and first 8 chars of `payload`.
3. `POST /__app/json/roundtrip-1kb` -> `json:roundtrip-1kb:<name>:<n>:<len>`
   Logic: Decode JSON body, add/modify `modified=true`, re-encode it, return the formatted string with the length of the re-encoded string.
4. `GET /__app/template/hello` -> `template:hello:Hello Meteorite!`
   Logic: Render a string template "Hello <%= name %>!" with `{name="Meteorite"}` using `etlua`.
5. `GET /__app/template/list-100` -> `template:list-100:<len>:<first_id>:<first_name>`
   Logic: Render an etlua template that iterates over 100 items (id, name).
6. `GET /__app/sqlite/select-one` -> `sqlite:select-one:item-042:420`
   Logic: Use luasql.sqlite3. Connect to `:memory:`, fetch a row from a pre-populated table.
7. `GET /__app/sqlite/select-100` -> `sqlite:select-100:100`
   Logic: Fetch 100 rows.
8. `POST /__app/sqlite/insert-small` -> `sqlite:insert-small:1`
   Logic: Insert 1 row.
9. `GET /__app/pipeline/cors` -> `pipeline:cors:ok`
   Logic: Set `Access-Control-Allow-Origin: *` header.
10. `GET /__app/pipeline/cors-json-template` -> `pipeline:cors-json-template:cors-json-template`
    Logic: Add CORS header, decode small JSON, render template.
11. `GET /__app/full/sqlite-json-template` -> `full:sqlite-json-template:item-007:70`
    Logic: Fetch from DB, encode to JSON, embed in template.

For `luasql` and `etlua`, you can configure your framework's `moonstone.toml` to install them:
```toml
[[dependencies]]
name = "luasql-sqlite3"
constraint = "^2.8.0-1"
registry = "rocks"
role = "runtime"

[[dependencies]]
name = "etlua"
constraint = "rocks:etlua@*"
role = "runtime"

[[dependencies]]
name = "lua-cjson"
constraint = "rocks:lua-cjson@*"
role = "runtime"
```
Make sure to initialize your in-memory database ONCE on startup.
Also create a `run.sh` script inside your directory that starts the server on `$PORT` (default 8080) and exits when it receives a SIGTERM.
