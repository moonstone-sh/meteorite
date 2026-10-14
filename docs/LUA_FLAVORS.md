# Lua flavors in Meteorite

Moonstone describes where Lua code runs as a *flavor*: language (`lua51`
to `lua55`, `luajit`, `luau`) plus host os and arch, written
`lua54-aarch64-macos` or `luajit-x86_64-linux`. A module can ship one file
per flavor (`util@lua54.lua`, `util@luajit.lua`, `fs@lua51@windows.lua`).
`moon sync` projects the winning file of each **dependency** as `util.lua`.
A project's **own** sources are not projected. They need the runtime
searcher from the generated `moonstone.variants` module. The spec is in
Moonstone's `docs/PROJECT_ENVIRONMENT.md`, section "Flavors: one package
for several Luas".

This page covers what Meteorite does with flavors. All of it is optional.
With a `moon` that predates flavors, or outside Moonstone, every lookup falls
back to the untagged file, which is what Meteorite did before.

## Meteorite's own Lua

| file | role |
|---|---|
| `src/meteorite/compat.lua` | untagged fallback; detects the runtime (`unpack`, `pack`, `load` with env, `lua_version`, `is_luajit`) |
| `src/meteorite/compat@lua54.lua` | PUC 5.4, no branches |
| `src/meteorite/compat@luajit.lua` | LuaJIT (beats `@lua51` on LuaJIT) |
| `src/meteorite/compat@lua51.lua` | PUC 5.1 (`loadstring`, `setfenv`) |
| `src/meteorite/flavor.lua` | flavor detection, variant resolution, release projection |

The audit found only a few version-dependent spots in `src/`:
`(table.unpack or unpack)` in `cli/check.lua`, `cli/build.lua`,
`cli/dev_command.lua` and `cli/package_context.lua`, and `load(string)` in
`codegen/lifter.lua`. The last one broke on PUC 5.1, whose `load` takes no
strings. All of them now go through `meteorite.compat`. `cli/main.lua` keeps
its inline `_VERSION` match because it runs before `package.path` can find
`meteorite.compat`. `lifter.lua`'s `_ENV` upvalue check already worked on
every Lua.

Honestly, the variant files do not buy Meteorite much speed. The fallback
picks its implementation once, at load time. The variants mainly
demonstrate the model and prove it works on a real package. `tests/compat.lua`
keeps them in step. It checks that every variant parses, that all of them
export the same fields, and that the variant for the running interpreter
behaves the same as the fallback.

How a variant gets selected:

- **Installed package** (`share/lua/<v>/meteorite/...`): `moon sync`
  projects `meteorite/compat.lua`.
- **Checkout or libexec mount** (unprojected): `cli/main.lua` calls
  `require("meteorite.flavor").install_searcher()`. That call runs
  `moonstone.variants.install(<host flavor>)` behind `pcall`, and does
  nothing when the module is missing. The searcher probes the tagged names on
  every `require`. On the CLI's `graph` command this cost between 0 and
  about 10% of wall time in the measurements, which were noisy.
- The Ballad plugin and the tests never install the searcher, so they load
  the fallback.

## Two flavors: host and target

`meteorite.flavor` separates two flavors:

- `flavor.host()` is the interpreter running Meteorite. The language comes
  from `jit`/`_VERSION`. The os and arch come from `moonstone.target` when
  it describes this same interpreter, otherwise from `jit.os`/`jit.arch` or
  `uname`.
- `flavor.target()` is the Lua embedded in the server being built. Its
  sources are checked in this order:
  1. `METEORITE_LUA_FLAVOR`
  2. `MOONSTONE_TARGET`
  3. `moonstone.target`
  4. the host

  The Zig build (`zig/build_api.zig`, `luaFlavorId`) sets
  `METEORITE_LUA_FLAVOR` on the graph step whenever the server embeds Lua.
  The language comes from the archive it links: LuaJIT is recognized by the
  root name, and the PUC level is read from `LUA_VERSION_NUM` in `lua.h`. The
  os and arch come from `-Dtarget`. Because the build is the only place that
  knows both, its value wins over a `MOONSTONE_TARGET` that a caller set
  for something else.

## Hybrid servers: how variants are chosen

The embedded Lua `loadfile`s handler paths. That bypasses both `moon sync`'s
projection and any `require` searcher. Meteorite therefore makes the choice
itself, at three points.

1. **Handlers (`m.lua`)**, all modes. `codegen/graph_prepare.lua`
   resolves `route.handler.path` with `flavor.resolve_file`, which uses
   `moonstone.variants.suffixes` and `select`. So `src/app/x.lua` becomes
   `src/app/x@lua54.lua` when that variant wins. The original path is kept
   as `handler.declared_path`, and `handler.flavor` records the flavor id.
   If two variants are equally specific, the graph fails and names the
   route. A handler written with an explicit tag (`m.lua("x", { path =
   "x@luajit.lua" })`) is used as written.
2. **Project modules `require`d at run time, development servers.** A
   non-release graph whose project has variant files under `src/` emits
   `pub const lua_variant_flavor = .{ ... }` into `graph.zig`.
   `zig/bridge/lua_bindings.zig` then appends a guarded
   `moonstone.variants.install(<that flavor>)` to each Lua state's package
   setup. Projects with no variants get the same `graph.zig` and the same
   setup string as before.
3. **Hybrid releases.** `src/ballad/init.lua` builds for the environment's
   language with the `-Dtarget` os/arch (`flavor.for_zig_target`), and
   `release_assets.lua` projects what it ships:
   - Project modules found through `require` scanning ship under their
     plain name (`src/app/util.lua`) with the content of the winning
     variant. The asset metadata gets `flavor_variant` and `flavor`.
   - Dependency trees (`files/share/lua`) are collapsed the same way
     `moon sync` collapses them. The losing variants are not shipped.

   A release therefore needs no searcher and no `.moonstone/env` on the
   target machine.

Verified on 2026-10-14 with the flavor-aware `moon` (scratch build of
Moonstone `feat/lua-flavors` ab59713), using a `-Dmode=hybrid` fixture
whose `hello` has a `hello@lua54.lua` variant and whose `app.util` has
`@lua54`/`@luajit` variants:

- `/hello` returned "lua54 handler" and `/util` returned "util says lua54".
- `MOONSTONE_TARGET=luajit-x86_64-linux zig build ...` still chose
  `hello@lua54.lua`, because `METEORITE_LUA_FLAVOR` wins.
- With the installed pre-flavor moon, the same fixture served
  "fallback handler" and "util says fallback".
- `otool -L` on each server listed only `libSystem`.

## `m.dir`, `m.site`, static content

Static routes serve bytes. A file named `x@lua54.lua` inside an `m.dir` or
`m.site` root is content: it is served under that name and never treated as
a module. Meteorite has no file-based Lua routing, so a tagged file cannot
become a route by accident. Only `m.lua` handler paths and `require`d
modules are resolved as variants.

## Editor support (`meteorite init`, `meteorite sync`)

Tagged files are ordinary Lua files, so LuaLS indexes them as workspace
files. `require("app.util")` resolves to the untagged `util.lua` through
`runtime.path`, which is one reason to always keep an untagged fallback.
LuaLS takes one `runtime.version` per workspace. As a result, an
`@luajit` file checked as "Lua 5.4" may report `jit` and `setfenv` as
undefined. Put `---@diagnostic disable: undefined-global` at the top of
such files.

`meteorite sync` now writes `"runtime.version": "LuaJIT"` and the `5.1`
share paths for LuaJIT environments. Before, it wrote "Lua 5.4" because the
`luajit` abi did not parse. The `meteorite init` templates do not scaffold
variants. A new project has no flavor-specific code, and an example variant
would only add a file to keep in step.

## Not done yet

- **Optimized hybrid profile with `m.lua` handlers.** The fixture fails to
  compile there (`cached_runtime.zig: unknown inline Lua route`). The same
  failure happens on the baseline commit (0016957), so it is not caused by
  flavors. Because of it, the run-time searcher was verified only under the
  default (per-request) profile.
- **Release manifest.** `meteorite-release.json` does not record the
  flavor. Adding it changes manifest bytes for every hybrid release, so it
  was left for a deliberate format bump.
- **No end-to-end Ballad hybrid release with variants.** The release
  projection is covered by unit tests (`tests/flavor.lua`), not by
  `fixtures/tests/release-smoke.sh`.
- **Cost of the per-request searcher.** In development servers that use the
  per-request Lua state profile, the searcher is installed once per state,
  which means once per request. It only does so for projects that have their
  own variant files.
- **Missing variants give the old error.** A module that exists only as
  variants for other flavors is reported as a missing file, the same as
  before flavors. Without directory listing there is no "no variant matches"
  diagnostic, because the searcher only probes matching suffixes.
- **Runtime `MOONSTONE_TARGET` mismatch.** If `MOONSTONE_TARGET` names a
  language other than the Lua being linked, the build's
  `METEORITE_LUA_FLAVOR` wins silently. The bare `meteorite graph` CLI,
  which has no Zig build, follows `MOONSTONE_TARGET`.
- **Test fixture copy of the rule.** `tests/support/moonstone_variants.lua`
  is a test-only copy of Moonstone's rule. The tests prefer the
  environment's real module when it exists. Re-copy the file if the rule
  changes.
