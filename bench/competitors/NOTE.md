# Lua-Based Competitors

All five Lua-based competitors are implemented and wired into the main benchmark
orchestrator (`bench/run.sh`) via `moon orbit exec <name>`.

## Competitor Summary

| Competitor       | Runtime    | Backend         | Status     |
|-----------------|------------|-----------------|------------|
| openresty       | LuaJIT 2.1 | nginx + ngx_lua | ✅ Wired   |
| lapis-openresty | LuaJIT 2.1 | nginx + Lapis   | ✅ Wired   |
| lapis-cqueues   | LuaJIT 2.1 | cqueues + Lapis | ✅ Wired   |
| turbo           | LuaJIT 2.1 | Turbo.lua       | ✅ Wired   |
| pegasus         | Lua 5.4    | Pegasus         | ✅ Wired   |

## Endpoint Coverage

All competitors implement the full endpoint surface:

### Synthetic `/__bench/*` endpoints
- `/health` → `"ok"`
- `/__bench/plain`, `plain-static`, `zig-static`, `hybrid-zig`, `raw` → `"ok"`
- `/__bench/meta` → JSON metadata (framework, runtime, backend)
- `/__bench/counters` → JSON request counter
- `/__bench/stats` → JSON stats (requests, errors)
- `POST /__bench/stats/reset` → reset stats
- `/__bench/fixture-info` → JSON with fixture=bench-service, routes map

### Work endpoints (CPU busy-spin + sleep)
- `/__bench/work/cpu/{50us,100us,250us,500us,1ms,2ms,5ms}` → `"work:cpu:<label>:<checksum>"`
  - CPU spin via `os.clock()` tight-loop (LuaJIT/Lua 5.4 portable)
  - OpenResty/lapis-openresty additionally benefit from `ngx.sleep` for sleep
- `/__bench/work/sleep/{1ms,5ms,10ms}` → `"sleep:<label>"`
  - OpenResty/lapis-openresty: `ngx.sleep()` (non-blocking, cooperative)
  - turbo/pegasus/lapis-cqueues: `os.execute("sleep <secs>")` (blocking)

### Public routes
- `GET /users/:id` → u64 validated id (text/plain or application/json)
- `POST /echo` → echo request body
- `GET /health` → `"ok"`

### App work-suite (`/__app/*`)
- `/__app/json/encode-small`, `decode-1kb`, `roundtrip-1kb`
- `/__app/template/hello`, `list-100`
- `/__app/sqlite/select-one`, `select-100`, `insert-small`
- `/__app/pipeline/cors`, `cors-json-template`
- `/__app/full/sqlite-json-template`

## Runtime Isolation

All Lua competitors run inside Moonstone orbit environments (`moon orbit exec <name>`),
providing isolated LuaJIT runtime and Lua dependencies without polluting the parent
project's Lua 5.4 environment. The orbit members are declared in the root
`moonstone.toml` under `[[orbits.member]]`.

## Note on LuaJIT vs Lua 5.4

All Lua competitors except Pegasus use LuaJIT (Lua 5.1 ABI) because their
frameworks (OpenResty, Lapis, Turbo) fundamentally require LuaJIT. Pegasus
runs on stock Lua 5.4 since it has no hard LuaJIT dependency. Moonstone orbit
environments handle the runtime difference transparently.

## Known Issues (2026-07-06)

### lapis-cqueues — Blocked (library compatibility)

**Status:** Dependencies install correctly (21 packages via Moonstone transitive
resolution fix), but the server fails at runtime with:

```
onstream on http.h1_stream{...;state="closed"} failed:
  http/h1_connection.lua:154: attempt to call method 'xread' (a nil value)
```

**Root cause:** Version incompatibility between cqueues `20200726` and lua-http
`0.4` on macOS.  The `http.server.listen` path goes through `is_tls_client_hello`
→ `h2_connection.socket_has_preface` → `h1_connection.new`, and somewhere in
that chain the socket loses the `xread` method.  Verified that `xread` works
correctly on cqueues socket instances in isolation.

**Interpreter:** Switched from `lua@5.1` to `luajit@2.1` — the error persists
with both runtimes, confirming it is a library-level issue, not an interpreter
issue.

**Fix needed:** Pin compatible versions of cqueues + lua-http that work together
on macOS, or patch lua-http's `socket_has_preface` to handle the negative-length
`xread` call (`xread(#bytes - #preface)` starts at -24).

### turbo — Blocked (native library + macOS compatibility)

**Status:** Dependencies install (6 packages including luasocket), but the server
fails at runtime with two issues:

1. **libtffi_wrap not provisioned:** Turbo's Makefile builds `libtffi_wrap.dylib`
   as a native shared library (not a Lua C module). Moonstone's `make`-build
   provision discovery only finds `.lua` and `.so` files, not `.dylib`. The
   `run.sh` works around this by setting `TURBO_LIBTFFI` to the store path.

2. **tablemerge nil error:** After loading libtffi_wrap, Turbo fails at
   `util.lua:98` with `bad argument #1 to 'pairs' (table expected, got nil)`.
   This appears to be a macOS compatibility issue in Turbo.lua's initialization
   code.

**Fix needed:** Debug Turbo's macOS initialization path, or use a Linux host
for Turbo benchmarks.

### pegasus — Working (switched to LuaJIT)

**Status:** Switched from `lua@5.4` to `luajit@2.1` for benchmark fairness with
other Lua competitors. All endpoints respond correctly. Meta endpoint updated
to report `luajit2.1`.

### openresty — Tuned

**Status:** nginx.conf updated: `worker_processes auto`, `error_log stderr error`,
keepalive enabled, LuaJIT warm-up in `init_worker_by_lua_block`.
