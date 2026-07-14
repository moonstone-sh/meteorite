# Meteorite — Agent Development Guide

Meteorite is a Moonstone-zig service compiler prototype. It takes a Lua-declared HTTP application graph, validates it against a release compiler contract, compiles it to a Zig HTTP server, and optionally materializes a target Lua runtime for cross-platform hybrid releases.

```text
Lua declares.
Ballad materializes.
Zig compiles.
Meteorite lands.
```

---

## 1. What Meteorite Is

Meteorite is **not** a web framework in the traditional sense. It is a **compiler**: Lua DSL code runs on the host to produce a normalized application graph (routes, handlers, validators, patterns, capabilities, scopes, plugins). That graph is then validated and compiled into a Zig HTTP server binary.

Two execution modes:

- **Static** — The graph contains only Zig handlers and graph-expanded facts. No Lua runtime is needed at deploy time. The output is a self-contained binary.
- **Hybrid** — The graph retains inline Lua handlers, Lua file/module handlers, and/or scoped Lua plugins. The output includes a Lua runtime and module trees so the embedded interpreter can execute those nodes at request time.

Meteorite owns its own CLI (`meteorite`), its own Ballad plugin (`meteorite.ballad`), and its own Zig build driver (`build.zig`).

---

## 2. Relationship to Moonstone and Ballad

Meteorite is a Moonstone package (`moonstone/meteorite`) and a Ballad plugin consumer.

### Moonstone

- Meteorite's `moonstone.toml` declares `kind = "bin"` with runtime `lua@5.4`.
- `moon sync` materializes `.moonstone/env/` with the Lua runtime and any dependencies.
- Meteorite's CLI and Lua modules can run via `moon exec` or via `moon run <script>`.
- Moonstone's content-addressed store provides runtime and package artifacts, including **source provenance** (`source_payload_path`, `source_kind`) that Meteorite consumes for cross-target hybrid builds.

### Ballad

- Meteorite registers as a Ballad plugin under the name `meteorite.ballad` (see `src/meteorite/ballad.lua` → `src/ballad/init.lua`).
- Ballad's `moonstone` plugin (`ballad.plugins.moonstone`) exposes project metadata, runtime facts, and package facts via `project_prepare()` / `project()`.
- Meteorite's release export runs inside a Ballad partiture (`partiture.lua` for registry export; per-app `partiture.lua` for production releases).
- Ballad's `registry.source_package` creates the publishable Moonstone source package for Meteorite itself.

### Data Flow

```
moonstone.toml ──moon sync──▶ .moonstone/env/ (Lua runtime + modules)
                                      │
src/main.lua ──load──▶ Meteorite app graph (Lua DSL)
                                      │
                         emitter.emit() ──▶ .meteorite/graph/current/
                                      │                    ├── graph.zig
                                      │                    ├── ctx.zig
                                      │                    ├── routes/*.zig
                                      │                    ├── patterns/*.zig
                                      │                    ├── listen_config.zig
                                      │                    ├── zig-files.tsv
                                      │                    ├── *.zon (manifest data)
                                      │                    └── build-report.txt
                                      │
                         zig build ──▶ dist/server (Zig HTTP binary)
                                      │
              meteorite.ballad.release() ──▶ dist/release/ (deployable directory)
```

---

## 3. Project Structure

```
meteorite/
├── AGENTS.md              ← This file
├── README.md              ← User-facing overview
├── docs/
│   ├── examples.md        ← Copyable app shapes (CRUD, etc.)
│   ├── release-compiler-contract.md ← Release compiler contract and implementation status
│   └── benchmarks.md      ← Benchmark methodology and results
├── moonstone.toml         ← Package declaration + scripts
├── moonstone.lock         ← Pinned dependency versions
├── build.zig              ← Zig build driver (graph generation + server compilation)
├── partiture.lua          ← Ballad partiture for Meteorite registry export
├── bin/meteorite          ← CLI launcher shell script
│
├── src/
│   ├── meteorite.lua          ← Public require("meteorite") facade (DSL: app, routes, mount, site, plugin, schema types)
│   ├── meteorite/
│   │   └── ballad.lua         ← Ballad plugin loader (redirects to src/ballad/init.lua)
│   ├── core/
│   │   ├── route.lua          ← Route declaration, path parsing, scope chains
│   │   ├── schema.lua         ← Type validators (u64, uuid, slug, hex, email, token, pattern, etc.)
│   │   ├── patterns.lua       ← Regex → DFA compiler for pattern validators
│   │   ├── profile.lua        ← Memory/resource profile presets
│   │   ├── handler_factories.lua  ← m.file(), m.dir() handler factories
│   │   └── site.lua           ← m.site() static site macro
│   ├── codegen/
│   │   ├── emitter.lua        ← Graph emitter: writes graph.zig, ctx.zig, routes/, patterns/, zon files, build report
│   │   ├── lifter.lua         ← Lifts inline Lua handler chunks to .meteorite/lua/inline/
│   │   ├── static.lua         ← Static asset scanner/manifest builder
│   │   ├── partitions.lua     ← Partition hash/diff for incremental dev rebuilds
│   │   └── zon.lua            ← ZON (Zig Object Notation) encoder
│   ├── ballad/
│   │   ├── init.lua           ← Ballad plugin entry: graph(), zig(), release() methods
│   │   ├── release_contract.lua  ← Release mode validation (static/hybrid), target Lua checks
│   │   ├── release_tasks.lua    ← Native task construction (build-target-lua.sh, build-lua-cmodule.sh, zig build args)
│   │   ├── release_assets.lua   ← Asset collection (graph files, static assets, hybrid Lua, packages, runtime source)
│   │   └── release_manifest.lua ← meteorite-release.json builder
│   ├── cli/
│   │   ├── main.lua           ← CLI: init, build, dev, graph, doctor, invoke, help
│   │   ├── dev.lua            ← Live reload supervisor (partition-aware rebuild/reload)
│   │   ├── hybrid.lua         ← In-process hybrid Lua route invoker (for dev/invoke)
│   │   └── http_client.lua    ← HTTP client helper for capability stubs
│   └── utils/
│       └── json.lua           ← Minimal JSON encoder
│
├── zig/
│   ├── main.zig               ← Server entry point
│   ├── meteorite.zig          ← Server core: dispatch, static serving, validation, diagnostics
│   ├── bridge.zig             ← Lua VM bridge: state lifecycle, handler refs, context API, capability calls
│   ├── pattern.zig            ← DFA pattern matching at runtime
│   ├── handlers.zig           ← Empty handlers (overridden by project zig/handlers.zig)
│   ├── validators.zig         ← Empty validators (overridden by project zig/validators.zig)
│   ├── empty_handlers.zig     ← Fallback when project has no zig/handlers.zig
│   ├── empty_validators.zig   ← Fallback when project has no zig/validators.zig
│   ├── helpers/
│   │   └── data_cruncher.zig  ← Demo Zig helper
│   └── backends/
│       ├── std_http.zig       ← std.http-based backend
│       └── fast_http.zig      ← High-performance threaded/pool backend
│
├── scripts/
│   ├── build-target-lua.sh    ← Cross-compile PUC Lua from source with zig cc
│   ├── build-lua-cmodule.sh   ← Cross-compile Lua C modules with zig cc + luarocks
│   └── guard.sh               ← Dev supervisor port/process cleanup
│
├── templates/
│   ├── project/               ← Default minimal hybrid app template
│   ├── static/                ← Pure Zig static app template
│   └── hybrid/                ← Mixed Lua + Zig hybrid app template
│
├── fixtures/
│   ├── README.md              ← Fixture standards and roles
│   ├── apps/
│   │   ├── showcase-service/  ← Default app for moon run graph/dev/build
│   │   ├── basic-service/     ← Black-box acceptance fixture (routing, validators, body limits, Zig handlers)
│   │   ├── hybrid-demo/       ← Inline Lua handlers, capabilities, hybrid invoke
│   │   ├── scoped-plugins/    ← Scoped mounts, plugins, request-local state
│   │   ├── static-site/       ← m.file, m.dir, m.site, static release packaging
│   │   └── bench-service/     ← Benchmark-only endpoints
│   └── tests/
│       ├── basic-service.sh   ← Full acceptance test suite
│       └── release-smoke.sh   ← Release export smoke test
│
├── tests/
│   ├── patterns.lua           ← DFA pattern compiler unit tests
│   └── scope_plugins.lua      ← Scoped plugin/mount integration tests
│
└── bench/
    ├── run.sh                 ← Main benchmark runner
    ├── run-fast-http-matrix.sh
    ├── run-hybrid-ladder.sh
    ├── run-lua-stability.sh
    ├── summarize.py
    ├── compare.py
    ├── hybrid_ladder.py
    ├── collect_memory.sh
    ├── collect_env.sh
    ├── check-lua-state-correctness.sh
    └── wrk/echo.lua           ← wrk Lua script
```

---

## 4. Build System

### Zig Build

Meteorite's `build.zig` is the core build driver. It:

1. Runs the Lua graph generator (`moonstone/env/bin/lua src/cli/main.lua graph <input> <output> <mode>`)
2. Reads generated graph modules (`graph.zig`, `ctx.zig`, `listen_config.zig`, `routes/*.zig`, `patterns/*.zig`)
3. Reads `zig-files.tsv` for additional generated Zig file imports
4. Compiles the server executable against `zig/meteorite.zig`, `zig/bridge.zig`, `zig/pattern.zig`
5. Links against Lua when mode is hybrid (`-Dlua-root` → `liblua`, headers)
6. Installs to `dist/server`

**Key build options (`-D` flags):**

| Flag | Default | Description |
|------|---------|-------------|
| `-Dmode` | `release-static` | `release-static`, `release-hybrid`, `hybrid`, `hybrid_dev`, `dev` |
| `-Dgraph-input` | `fixtures/apps/showcase-service/src/main.lua` | App entry Lua file |
| `-Dgraph-output` | `.meteorite/graph/current` | Generated graph directory |
| `-Dproject-root` | `.` | Project root (for Ballad release builds) |
| `-Dmeteorite-cli` | auto-detected | Meteorite CLI Lua entrypoint |
| `-Dlua-root` | `.moonstone/env/libexec/lua/files` | Lua runtime root with `include/` and `lib/` |
| `-Dbackend` | `fast_http` | `fast_http` or `std_http` |
| `-Dhybrid-profile` | `default` | `default` or `optimized` (affects Lua state strategy) |
| `-Drouter-dispatch` | `method_buckets` | `method_buckets`, `static_fast_path`, `param_matchers`, `legacy_scan` |
| `-Dtarget` | native | Zig cross-compilation target |
| `-Doptimize` | auto (ReleaseFast for release-* modes) | Optimization level |

### Build Commands

```bash
# Local dev build (uses showcase-service fixture by default)
zig build install-server
# Output: dist/server

# Via meteorite CLI
meteorite build --mode hybrid
meteorite build --mode release-static

# Via moon run
moon run build
```

### Zig Version

- **Zig version:** 0.16.0 (same as Moonstone)
- **Zig std library path:** `/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std/`

---

## 5. CLI Commands

```bash
meteorite init [path] [flags]     # Create a new Meteorite app
meteorite init my-app             # Minimal Lua-first hybrid app
meteorite init my-app --static    # Pure Zig handlers; release-static mode
meteorite init my-app --hybrid    # Mixed Lua + Zig handlers
meteorite init . --with-zig       # Add zig/handlers.zig + zig/validators.zig scaffolding

meteorite graph [input] [output] [mode]  # Generate graph only (no Zig build)
meteorite build [--mode <mode>]          # Generate graph + compile server
meteorite dev                            # Live reload supervisor
meteorite doctor                         # Check project/tool readiness
meteorite invoke [input] [method] [path] [body]  # In-process route invocation
meteorite help [command]                 # Show help
```

### moon run Scripts (from moonstone.toml)

```bash
moon run graph              # Generate graph for showcase-service
moon run dev                # Live reload dev server
moon run build              # Build server to dist/server
moon run run                # Build and run server
moon run test-fixture       # Run basic-service Ballad partiture test
moon run test-acceptance    # Full acceptance test suite (basic-service.sh)
moon run test-release-smoke # Release export smoke test (release-smoke.sh)
moon run bench              # Benchmark suite
moon run bench:matrix       # Fast HTTP matrix benchmark
moon run bench:hybrid       # Hybrid ladder benchmark
moon run bench:lua-stability # Lua state stability benchmark
```

---

## 6. Route Declaration Contract

Meteorite routes can be declared in two forms:

### Legacy form (sugar)

```lua
app:get("/health", function(ctx) return "ok" end)
app:get("/users/:id", { params = { id = m.u64() } }, "handlers.get_user")
```

Internally, every handler lowers to a single-stage pipeline:
```
pipeline: [ { kind = "handle", strat = "inline_lua" | "zig" | "lua" } ]
```

### Canonical form

```lua
app:get({
  route = "/orders/:id",
  params = { id = m.u64() },
  pipeline = function(ctx)
    ctx:transform({ id = "auth", strat = "lua", path = "transforms/auth.lua" })
    ctx:transform("zig", "transforms/load_order.zig")
    ctx:transform(function(ctx) ctx.state.foo = "bar" end)
    ctx:handle({ id = "show", strat = "lua", path = "handlers/show.lua" })
    ctx:hook("post_handler", { strat = "lua", path = "hooks/log.lua" })
  end,
})
```

The pipeline function runs at **graph build time**, not request time. It records
stages in order. Each stage has a `kind` (transform|handle|hook), a `strat`
(inline_lua|lua|zig), and optional path/symbol/fn_ref.

### Graph inspection

```bash
meteorite routes src/main.lua          # human-readable
meteorite routes --graph src/main.lua  # JSON
```

### Contract module

`src/core/contract.lua` defines:
- `RouteContract` — the canonical internal representation
- `PipelineBuilder` — the `ctx` object passed to `pipeline = function(ctx) ... end`
- `StageContract` — kind, phase, strat, path, symbol, fn_ref, reads, writes
- `HookContract` — phase (pre_tree|post_match|pre_handler|post_handler|observe|error)
- `contract.build(method, decl, scope)` — single entry point that lowers all forms
- `contract.serialize(route_contract)` — produces inspectable table

## 7. Development Workflow

### Quick Start (from meteorite repo root)

```bash
moon sync                    # Materialize .moonstone/env/
moon run dev                 # Start dev server with live reload
```

### Dev Server (`meteorite dev` / `moon run dev`)

The dev supervisor (`src/cli/dev.lua`) is partition-aware:

- **Lua-only edits** (inline handler chunk changes) → reload in-process without rebuild
- **Route shape / Zig / build-affecting changes** → rebuild graph + server, restart
- **Graph/build failure** → keep previous server alive

`scripts/guard.sh` manages port cleanup and stale process termination:

```bash
scripts/guard.sh status      # Show tracked and port-listening processes
scripts/guard.sh handoff     # Cleanup old supervisors, assert port is free
scripts/guard.sh cleanup     # Terminate stale dev servers
```

### Smoke Test

```bash
curl http://127.0.0.1:8080/health   # → ok
curl http://127.0.0.1:8080/hello/max
```

### In-Process Invoke (no server needed)

```bash
luajit src/cli/main.lua invoke fixtures/apps/hybrid-demo/src/main.lua GET /devices/router_01
# Output: 200\tapplication/json\t{"device":"device:router_01"}
```

---

## 7. Testing

### Test Commands

```bash
# Full acceptance suite (routing, validators, body limits, capabilities, Zig handlers, error cases)
moon run test-acceptance
# or: bash fixtures/tests/basic-service.sh

# Release export smoke test (static site packaging, deploy-local copy, no source leaks)
moon run test-release-smoke
# or: bash fixtures/tests/release-smoke.sh

# Ballad partiture test (graph generation + server build for basic-service fixture)
moon run test-fixture

# Unit tests (no moon needed)
luajit tests/patterns.lua         # DFA pattern compiler tests
luajit tests/scope_plugins.lua    # Scoped plugin/mount tests
```

### Test Infrastructure

The acceptance test (`fixtures/tests/basic-service.sh`) is comprehensive. It:

1. Runs the Ballad partiture for `basic-service` to generate the graph and build the server
2. Verifies graph output files exist and contain expected content
3. Starts the server and tests all routes with `curl`
4. Tests error cases: 404, 405, 413 (body too large), 414 (URI too long)
5. Tests pattern validation failures (non-matching params)
6. Tests missing handler build errors (Zig compile-time diagnostics)
7. Tests pattern DFA byte budget exceeded errors
8. Tests custom memory profiles
9. Tests hybrid-demo fixture: inline Lua handlers, capabilities, hybrid invoke
10. Tests static mode rejection of inline Lua handlers
11. Tests undeclared capability detection
12. Tests outer-local upvalue capture detection
13. Tests generated handler stub sync
14. Tests typed Zig handler context parameters

The release smoke test (`fixtures/tests/release-smoke.sh`) verifies:

1. Static site Ballad partiture produces deployable `dist/release/`
2. No `.moonstone/env` leaks or host absolute paths in release
3. Server runs from a copied release directory with source removed
4. Static assets serve correctly with path traversal protection
5. Lua C-module package asset collection (deploy-local `lua/` and `lib/` trees)

### Running Tests Without Moon (Direct Lua)

```bash
# Set LUA_PATH to include meteorite src/ and ballad
LUA_PATH='src/?.lua;src/?/init.lua;../ballad/.moonstone/env/share/lua/5.1/?.lua;../ballad/.moonstone/env/share/lua/5.1/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;;' \
  luajit ../ballad/src/main.lua play fixtures/apps/basic-service/partiture.lua
```

### Fixture Conventions

- App fixtures live under `fixtures/apps/<name>/` with `src/main.lua`, `src/app.lua`, and optional `zig/`
- Each fixture has a `README.md` documenting its goal
- Fixtures with release testing have a `partiture.lua`
- **Do not commit** generated `.meteorite/`, `.zig-cache/`, `.moonstone/`, `dist/` in fixtures (they are gitignored)
- The acceptance test regenerates everything from source

---

## 8. Release Compiler Contract

See `docs/release-compiler-contract.md` for the full contract specification.

### Static Mode (`mode = "static"`)

Validates the graph as a Zig-only artifact. Fails before Zig build if any Lua runtime execution nodes are retained:

- Inline Lua route handlers
- Lua file/module route handlers
- Scoped plugin runtime `execute` functions
- Plugin handlers that lower to Lua

Failure messages list each retained node with source location and suggest `mode = "hybrid"`.

### Hybrid Mode (`mode = "hybrid"`)

Allows retained Lua runtime nodes. When Lua nodes exist:

- **Same-host** (no target or `target = "native"`): packages the host `.moonstone/env` Lua module/C-module trees
- **Cross-target** (e.g. `target = "aarch64-linux-gnu"`): requires Moonstone store facts for target runtime source and module source; builds target Lua with `zig cc` via `scripts/build-target-lua.sh`; rebuilds Lua C modules via `scripts/build-lua-cmodule.sh`

### Release Export (Ballad Partiture)

```lua
local ballad = require("ballad")
local moonstone = require("ballad.plugins.moonstone")

return ballad.partiture(function(p)
  local meteorite = p:use("meteorite.ballad")
  local project = moonstone.project_prepare({ root = ".", roles = { "runtime" } })
  local release = meteorite.release({
    project = project,
    input = "src/main.lua",
    graph_output = ".meteorite/graph/release",
    mode = "hybrid",           -- or "static"
    target = "aarch64-linux-gnu",  -- optional cross target
    bin = "bin/server",
    backend = "std_http",
    router_dispatch = "param_matchers",
  })
  p.sink.directory(release, { out = "dist/release", file_graph = true })
end)
```

Run with:

```bash
moon exec ballad -- play partiture.lua
# or from meteorite repo:
moon run release   # (if a release script is defined)
```

Output: `dist/release/` containing `bin/server`, `meteorite-release.json`, static assets (if any), and hybrid Lua trees (if hybrid mode).

### Release Manifest (`meteorite-release.json`)

Emitted by `src/ballad/release_manifest.lua`. Contains:

- `format`: `"meteorite.release.v0"`
- `mode`: `"static"` or `"hybrid"`
- `graph_hash`: content hash of the normalized graph
- `contract`: validation contract format and retained Lua nodes
- `runtime_source`: target Lua source artifact path (cross-target hybrid)
- `static`: static asset entries with content type, ETag, cache policy, compressed variants

---

## 9. Cross-Compilation

### How It Works

Meteorite cross-compiles via the Zig build system's `-Dtarget` flag, combined with `zig cc` for building the target Lua runtime from source.

**Flow (cross-target hybrid):**

1. Host Lua evaluates the Meteorite app and produces the normalized graph
2. Meteorite validates the graph using the selected release mode
3. If hybrid retains Lua nodes, Meteorite asks Ballad/Moonstone for target runtime source facts
4. `scripts/build-target-lua.sh` builds PUC Lua from `source_payload_path` with `zig cc -target <target>`
5. The Zig build links against the target-built Lua headers/library (`-Dlua-root`)
6. `scripts/build-lua-cmodule.sh` rebuilds Lua C modules for the target ABI
7. Meteorite collects: `bin/server`, target `liblua`, lifted inline chunks, Lua handler files, pure Lua modules, target-built C modules
8. `meteorite-release.json` records the runtime source artifact and retained-node contract

### Source Provenance Dependency

Cross-target hybrid requires Moonstone to expose **upstream source provenance** for runtime artifacts:

- `source_payload_path` — path to the upstream Lua source archive (e.g. `lua-5.4.7.tar.gz`)
- `source_kind` — must be `"puc_lua_source"`, `"luarocks_src_rock"`, `"upstream_archive"`, `"lua_source"`, or `"source"` (NOT `"runtime"`, which is a prebuilt blob)

The `release_contract.lua` function `runtime_source_is_rebuildable()` gates on this:

```lua
return kind == "source" or kind == "upstream_archive" or kind == "lua_source" or kind == "puc_lua_source"
```

If `source_kind = "runtime"` (prebuilt blob), cross-target hybrid fails with a diagnostic asking for upstream source provenance.

### Cross-Compile Scripts

**`scripts/build-target-lua.sh`** — Builds PUC Lua from source for a target:

```bash
sh scripts/build-target-lua.sh <source-payload> <out-dir> <target> [optimize]
# Example:
sh scripts/build-target-lua.sh /store/.../lua-5.4.7.tar.gz .meteorite/release/aarch64-linux-gnu/lua aarch64-linux-gnu ReleaseFast
```

Extracts the source archive, finds the Lua source root (`src/lua.c`), runs `make generic CC="zig cc -target <target>"`, and installs `bin/lua`, `lib/liblua.a`, and headers.

**`scripts/build-lua-cmodule.sh`** — Rebuilds a Lua C module for a target:

```bash
sh scripts/build-lua-cmodule.sh <source-payload> <rockspec-payload> <lua-root> <out-dir> <target> <package-name>
```

Uses `luarocks make` with `CC="zig cc -target <target>"` against the target-built Lua headers.

### Cross-Target Limitations

- **LuaJIT** requires a separate target matrix and host `buildvm` stage (not yet supported)
- Lua C-module rebuilds require `luarocks` on the host and package rockspecs
- Packages without source/rockspec payloads fail with package-specific diagnostics

---

## 10. Benchmarks

```bash
moon run bench               # Default: 10s duration, concurrency 1/16/64
moon run bench:matrix        # Fast HTTP backend matrix
moon run bench:hybrid        # Hybrid ladder (incremental Lua handler load)
moon run bench:lua-stability # Lua state stability under load
```

Benchmark scripts live in `bench/` and use `fixtures/apps/bench-service/` for endpoints. Results are written to `bench/results/` (gitignored except `.gitkeep`).

Tools used: `oha`, `wrk`, and custom Lua probes. See `docs/benchmarks.md` for methodology and historical results.

---

## 11. Key Invariants

1. **Never manually edit `.meteorite/graph/`** — it is generated by `emitter.emit()`. Regenerate with `meteorite graph` or `moon run graph`.
2. **Never manually edit `.moonstone/env/`** — use `moon sync`.
3. **Generated Zig files are write-on-change** — the emitter only rewrites files whose content changed, so incremental edits touch only affected modules.
4. **The graph is mode-agnostic** — Lua may build the graph in any mode; the mode only changes which runtime nodes the final graph may retain.
5. **Static mode is a validation gate** — it fails before Zig build if Lua runtime nodes remain, not after.
6. **Cross-target hybrid requires upstream source** — prebuilt runtime blobs cannot be cross-compiled; only source archives can.
7. **`dist/server` is dev-only** — use `dist/release/` for deployment.
8. **Symlinks in static roots are rejected** during graph generation; path traversal returns 404 at runtime.

---

## 12. Common Tasks

### Add a New Route

Edit `src/app.lua` (or fixture `src/app.lua`):

```lua
app:get("/my-route/:id", {
  params = { id = m.u64() },
  query = { verbose = m.bool({ optional = true }) },
}, function(c)
  return c:json({ id = c.params.id, verbose = c.query.verbose })
end)
```

For static mode, use a Zig handler string instead:

```lua
app:get("/my-route/:id", { params = { id = m.u64() } }, "handlers.my_route")
```

Then define `pub fn my_route(c: mt.ctx.my_route) !void` in `zig/handlers.zig`.

### Regenerate After Edits

```bash
moon run graph    # regenerate graph
moon run build    # rebuild server
# or just:
moon run dev      # live reload handles it
```

### Add a New Fixture

1. Create `fixtures/apps/<name>/` with `src/main.lua`, `src/app.lua`, `README.md`
2. Add `zig/` only if exercising Zig handlers
3. Add `partiture.lua` if testing release export
4. Do not commit generated artifacts (they are gitignored)
5. Document the fixture's distinct goal in `fixtures/README.md`

### Debug Graph Output

```bash
# View generated graph
cat .meteorite/graph/current/graph.zig
cat .meteorite/graph/current/routes.zon
cat .meteorite/graph/current/build-report.txt
cat .meteorite/graph/current/capabilities.zon

# Check partition hashes (for incremental rebuild awareness)
cat .meteorite/graph/current/partition-hashes.tsv
```

### Debug Build Configuration

The server reports its build configuration at runtime:

```bash
curl http://127.0.0.1:8080/meteorite/info  # if enabled
# or check build_info.zig generated during build
```
