#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LUA_BIN="${LUA_BIN:-lua}"
if [ -x ".moonstone/env/bin/lua" ]; then
  LUA_BIN=".moonstone/env/bin/lua"
fi

export LUA_PATH="src/?.lua;src/?/init.lua;tests/?.lua;;"

PASS=0
FAIL=0

for test_file in tests/*.lua; do
  case "$(basename "$test_file")" in
    test.lua|run-all.sh) continue ;;
  esac

  echo "=== $(basename "$test_file") ==="
  if "$LUA_BIN" "$test_file" 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  echo ""
done

echo "=== Summary ==="
echo "Test files: $((PASS + FAIL)) passed=$PASS failed=$FAIL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
