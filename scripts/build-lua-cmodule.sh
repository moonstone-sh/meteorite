#!/bin/sh
set -eu

usage() {
  echo "usage: build-lua-cmodule.sh <source-payload> <rockspec-payload> <lua-root> <out-dir> <target> <package-name>" >&2
  exit 2
}

src=${1:-}
rockspec=${2:-}
lua_root=${3:-}
out=${4:-}
target=${5:-}
pkg=${6:-package}
[ -n "$src" ] && [ -n "$rockspec" ] && [ -n "$lua_root" ] && [ -n "$out" ] && [ -n "$target" ] || usage
[ -f "$src" ] || { echo "Lua C-module source payload not found for $pkg: $src" >&2; exit 1; }
[ -f "$rockspec" ] || { echo "Lua C-module rockspec payload not found for $pkg: $rockspec" >&2; exit 1; }

case "$lua_root" in
  /*) ;;
  *) lua_root="$(pwd)/$lua_root" ;;
esac
case "$out" in
  /*) ;;
  *) out="$(pwd)/$out" ;;
esac

[ -d "$lua_root/include" ] || { echo "target Lua include dir missing for $pkg: $lua_root/include" >&2; exit 1; }
command -v luarocks >/dev/null 2>&1 || { echo "luarocks is required to rebuild Lua C module $pkg for $target" >&2; exit 1; }

work="$out/.build-$pkg"
rm -rf "$work"
mkdir -p "$work" "$out"

case "$src" in
  *.src.rock|*.zip) unzip -q "$src" -d "$work" ;;
  *.tar.gz|*.tgz) tar -xzf "$src" -C "$work" ;;
  *.tar.zst|*.tzst) tar --zstd -xf "$src" -C "$work" ;;
  *.tar.xz) tar -xJf "$src" -C "$work" ;;
  *.tar.bz2) tar -xjf "$src" -C "$work" ;;
  *) echo "unsupported Lua C-module source payload archive for $pkg: $src" >&2; exit 1 ;;
esac

cp "$rockspec" "$work/package.rockspec"
(
  cd "$work"
  CC="zig cc -target $target -fPIC" \
  LD="zig cc -target $target" \
  AR="zig ar" \
  RANLIB="zig ranlib" \
  CFLAGS="-I$lua_root/include -fPIC" \
  LIBFLAG="-shared" \
  luarocks make package.rockspec --tree "$out" --lua-dir "$lua_root" --no-manifest
)

rm -rf "$work"
cat > "$out/$pkg.cmodule.json" <<JSON
{"format":"meteorite.lua_cmodule.v0","package":"$pkg","target":"$target","lua_root":"$lua_root"}
JSON
