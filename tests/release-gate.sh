#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS="${METEORITE_GA_TARGETS:-aarch64-linux-gnu x86_64-linux-gnu}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "release gate: required command not found: $1" >&2
    exit 1
  fi
}

for command in git zig luajit python3 tar zstd file lsof; do
  require_command "$command"
done

if [[ ! -f "$ROOT/../ballad/src/main.lua" ]]; then
  echo "release gate: expected Ballad sibling checkout at $ROOT/../ballad" >&2
  exit 1
fi

cd "$ROOT"

run_gate() {
  local label="$1"
  shift
  echo "=== release gate: $label ==="
  if "$@"; then return 0; fi
  local status=$?
  echo "FAIL: release gate: $label (exit $status)" >&2
  exit "$status"
}

run_gate repository-hygiene bash tests/repository-hygiene.sh
run_gate registry-export bash tests/registry-export.sh
run_gate lua-suite bash tests/run-all.sh
run_gate web-standards bash fixtures/tests/web-standards.sh
run_gate ipc-backends bash fixtures/tests/ipc-backends.sh
run_gate basic-service bash fixtures/tests/basic-service.sh
run_gate release-smoke bash fixtures/tests/release-smoke.sh
run_gate release-reproducibility bash tests/release-reproducibility.sh
run_gate ipc-release-smoke bash fixtures/tests/ipc-release-smoke.sh
run_gate zig-build zig build -Dgraph-input=fixtures/apps/showcase-service/src/main.lua -Dgraph-output=.meteorite/graph/current

for target in $TARGETS; do
  run_gate "cross-target-$target" env METEORITE_CROSS_TARGET="$target" \
    bash fixtures/tests/cross-target.sh
done

echo "PASS: Meteorite v0.1 release gate"
