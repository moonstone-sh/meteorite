#!/usr/bin/env bash
set -e

# Run moon sync to fetch dependencies
moon sync

export PORT="${PORT:-8080}"

# Turbo needs libtffi_wrap — the Makefile builds it as a .dylib (not a Lua C
# module), so Moonstone's provision discovery doesn't pick it up.  Find it in
# the store and set TURBO_LIBTFFI to the absolute path.
LIBTFFI=$(find ~/.local/share/moonstone/store -path '*turbo*' -name 'libtffi_wrap.*' -print -quit 2>/dev/null)
if [ -n "$LIBTFFI" ]; then
  export TURBO_LIBTFFI="$LIBTFFI"
fi

# Run the app. Use `moon exec` so the orbit's LuaJIT binary is on PATH.
exec moon exec -- luajit app.lua
