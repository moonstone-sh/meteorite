#!/usr/bin/env bash

meteorite_test_setup() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)"
  LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"
  cd "$ROOT"
  export MOONSTONE_HOME="$ROOT/.moonstone-home"
}

meteorite_test_trap() {
  local name="$1"
  trap 'status=$?; printf "FAIL: %s line %s: %s (exit %s)\\n" "$METEORITE_TEST_NAME" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR
  METEORITE_TEST_NAME="$name"
}

meteorite_graph() {
  local input="$1"
  local output="$2"
  local mode="$3"
  local backend="$4"
  luajit src/cli/main.lua graph "$input" "$output" "$mode" "$backend"
}

meteorite_export_basic_service() {
  LUA_PATH="$LUA_PROJECT_PATH" luajit ../ballad/src/main.lua play fixtures/apps/basic-service/partiture.lua >/tmp/meteorite-partiture-test.log
}
