#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"
TARGET="${METEORITE_CROSS_TARGET:-aarch64-linux-gnu}"
ZIG_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-/tmp/zig-cache-meteorite-cross}"

cd "$ROOT"
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
export MOONSTONE_HOME="$ROOT/.moonstone-home"

echo "cross-target: target: $TARGET"

CMODULE_FIXTURE_DIR="$(mktemp -d /tmp/meteorite-cross-cmodule.XXXXXX)"
mkdir -p "$CMODULE_FIXTURE_DIR/src/mockcmodule" "$CMODULE_FIXTURE_DIR/bin"
cat > "$CMODULE_FIXTURE_DIR/src/mockcmodule/mock.c" <<'C'
int luaopen_mockcmodule(void) { return 0; }
C
tar -czf "$CMODULE_FIXTURE_DIR/mockcmodule.tar.gz" -C "$CMODULE_FIXTURE_DIR/src" mockcmodule
cat > "$CMODULE_FIXTURE_DIR/mockcmodule-0.1-1.rockspec" <<'ROCKSPEC'
package = "mockcmodule"
version = "0.1-1"
source = { url = "file://mockcmodule.tar.gz" }
build = { type = "builtin", modules = { mockcmodule = "mock.c" } }
ROCKSPEC
cat > "$CMODULE_FIXTURE_DIR/bin/luarocks" <<'SH'
#!/usr/bin/env sh
set -eu
tree=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tree)
      tree="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$tree" ] || { echo "fake luarocks missing --tree" >&2; exit 1; }
mkdir -p "$tree/lib/lua/5.4"
printf 'synthetic target cmodule\n' > "$tree/lib/lua/5.4/mockcmodule.so"
SH
chmod +x "$CMODULE_FIXTURE_DIR/bin/luarocks"
cleanup_cross_target() {
  rm -rf "$CMODULE_FIXTURE_DIR"
  cleanup_all
}
trap cleanup_cross_target EXIT INT TERM HUP

# Ensure the fixture has a .moonstone/env/bin/lua for build.zig's graph step.
# The release flow generates the graph via emitter.emit() in Lua, but build.zig
# also runs a graph step that needs a Lua binary at {project_root}/.moonstone/env/bin/lua.
FIXTURE_ROOT="$ROOT/fixtures/apps/hybrid-demo"
if [ ! -x "$FIXTURE_ROOT/.moonstone/env/bin/lua" ]; then
  mkdir -p "$FIXTURE_ROOT/.moonstone/env/bin"
  if [ -x "$ROOT/.moonstone/env/bin/lua" ]; then
    ln -sf "$ROOT/.moonstone/env/bin/lua" "$FIXTURE_ROOT/.moonstone/env/bin/lua"
  elif command -v lua >/dev/null 2>&1; then
    ln -sf "$(command -v lua)" "$FIXTURE_ROOT/.moonstone/env/bin/lua"
  elif command -v luajit >/dev/null 2>&1; then
    ln -sf "$(command -v luajit)" "$FIXTURE_ROOT/.moonstone/env/bin/lua"
  else
    echo "cross-target: no lua binary found for fixture env" >&2
    exit 1
  fi
fi

cleanup_port() {
  while read -r pid; do
    if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi
  done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
}
cleanup_port

rm -rf fixtures/apps/hybrid-demo/dist/release fixtures/apps/hybrid-demo/.meteorite/graph/release

LUA_PATH="$LUA_PROJECT_PATH" \
PATH="$CMODULE_FIXTURE_DIR/bin:$PATH" \
METEORITE_CROSS_TARGET="$TARGET" \
METEORITE_CMODULE_SOURCE="$CMODULE_FIXTURE_DIR/mockcmodule.tar.gz" \
METEORITE_CMODULE_ROCKSPEC="$CMODULE_FIXTURE_DIR/mockcmodule-0.1-1.rockspec" \
ZIG_GLOBAL_CACHE_DIR="$ZIG_CACHE_DIR" \
  luajit ../ballad/src/main.lua play fixtures/apps/hybrid-demo/partiture-cross-target.lua \
  >/tmp/meteorite-cross-target-ballad.log 2>&1

# Verify the release binary exists and is the correct architecture
test -x fixtures/apps/hybrid-demo/dist/release/bin/server
test -f fixtures/apps/hybrid-demo/dist/release/meteorite-release.json

BINARY_ARCH=$(file -b fixtures/apps/hybrid-demo/dist/release/bin/server)
case "$TARGET" in
  aarch64-*)
    expected_arch="ARM aarch64"
    ;;
  x86_64-*)
    expected_arch="x86-64"
    ;;
  *)
    expected_arch="$TARGET"
    ;;
esac

case "$BINARY_ARCH" in
  *"ELF"*"$expected_arch"*)
    echo "cross-target: binary architecture OK ($TARGET)"
    ;;
  *)
    echo "cross-target: unexpected binary architecture: $BINARY_ARCH" >&2
    exit 1
    ;;
esac

# Verify the release manifest records the hybrid mode and runtime source
grep -q '"mode":"hybrid"' fixtures/apps/hybrid-demo/dist/release/meteorite-release.json
grep -q '"format":"meteorite.release.v0"' fixtures/apps/hybrid-demo/dist/release/meteorite-release.json

# Verify no host absolute paths leaked into text files (excluding binaries and metadata)
# runtime.json and file-graph.json legitimately contain source paths; binaries may
# have embedded build paths from debug info. Focus on source/config files only.
host_path_leaks=$(find fixtures/apps/hybrid-demo/dist/release -type f \
  \( -name '*.lua' -o -name '*.zig' -o -name '*.zon' -o -name '*.toml' -o -name '*.txt' -o -name '*.json' \) \
  ! -name 'runtime.json' ! -name 'file-graph.json' ! -name 'meteorite-release.json' \
  -exec grep -l "$ROOT" {} \; 2>/dev/null || true)
if [ -n "$host_path_leaks" ]; then
  echo "cross-target: host absolute paths found in release text files:" >&2
  echo "$host_path_leaks" >&2
  exit 1
fi

# Verify target Lua was built (runtime source asset in release)
if [ -d fixtures/apps/hybrid-demo/dist/release/runtime ]; then
  echo "cross-target: runtime source asset present"
fi

test -f fixtures/apps/hybrid-demo/dist/release/lib/5.4/mockcmodule.so
grep -q 'synthetic target cmodule' fixtures/apps/hybrid-demo/dist/release/lib/5.4/mockcmodule.so
echo "cross-target: target Lua C module rebuilt"

# Verify lifted inline Lua chunks are in the release
if ls fixtures/apps/hybrid-demo/dist/release/.meteorite/lua/inline/*.lua 2>/dev/null | head -1 | grep -q .; then
  echo "cross-target: inline Lua chunks present"
else
  echo "cross-target: WARNING - no inline Lua chunks found in release"
fi

echo "PASS: Meteorite cross-target hybrid release ($TARGET)"
