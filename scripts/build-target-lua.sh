#!/bin/sh
set -eu

usage() {
  echo "usage: build-target-lua.sh <source-payload> <out-dir> <target> [optimize]" >&2
  exit 2
}

src=${1:-}
out=${2:-}
target=${3:-}
optimize=${4:-ReleaseFast}
[ -n "$src" ] && [ -n "$out" ] && [ -n "$target" ] || usage
[ -f "$src" ] || { echo "Lua source payload not found: $src" >&2; exit 1; }

case "$optimize" in
  Debug) copt="-O0" ;;
  ReleaseSmall) copt="-Os" ;;
  ReleaseSafe|ReleaseFast|*) copt="-O2" ;;
esac

work="$out/.build"
rm -rf "$out"
mkdir -p "$work" "$out/bin" "$out/lib" "$out/include"

case "$src" in
  *.tar.gz|*.tgz) tar -xzf "$src" -C "$work" ;;
  *.tar.xz) tar -xJf "$src" -C "$work" ;;
  *.tar.bz2) tar -xjf "$src" -C "$work" ;;
  *.zip) unzip -q "$src" -d "$work" ;;
  *) echo "unsupported Lua source payload archive: $src" >&2; exit 1 ;;
esac

root=$(find "$work" -maxdepth 2 -type f -name lua.c -path '*/src/lua.c' -print | head -n 1 | sed 's#/src/lua.c$##')
[ -n "$root" ] || { echo "could not find PUC Lua source root in $src" >&2; exit 1; }

cc="zig cc -target $target $copt -fPIC"
ar="zig ar"
ranlib="zig ranlib"

(
  cd "$root/src"
  make clean >/dev/null 2>&1 || true
  make generic CC="$cc" AR="$ar rcu" RANLIB="$ranlib" MYCFLAGS="-DLUA_USE_POSIX" MYLDFLAGS="" >/dev/null
)

cp "$root/src/lua" "$out/bin/lua"
[ -f "$root/src/luac" ] && cp "$root/src/luac" "$out/bin/luac"
cp "$root/src/liblua.a" "$out/lib/liblua.a"
cp "$root/src/lua.h" "$root/src/luaconf.h" "$root/src/lualib.h" "$root/src/lauxlib.h" "$out/include/"
[ -f "$root/src/lua.hpp" ] && cp "$root/src/lua.hpp" "$out/include/"
cat > "$out/runtime.json" <<JSON
{"format":"meteorite.target_lua.v0","target":"$target","source_payload":"$src","lib":"lib/liblua.a","include":"include","bin":"bin/lua"}
JSON
rm -rf "$work"
