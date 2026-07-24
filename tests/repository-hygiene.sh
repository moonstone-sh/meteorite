#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

forbidden_paths="$(git ls-files \
  '.ballad/**' \
  '.moonstone/**' \
  '.meteorite/**' \
  '.zig-cache/**' \
  'zig-cache/**' \
  'zig-out/**' \
  'dist/**' \
  'bench/competitors/**/node_modules/**' \
  'bench/competitors/**/target/**' \
  'bench/competitors/**/logs/**' \
  'bench/results/**')"

if [[ -n "$forbidden_paths" ]]; then
  echo "repository hygiene: generated benchmark artifacts are tracked:" >&2
  echo "$forbidden_paths" >&2
  exit 1
fi

for required_pattern in \
  '.ballad/' \
  '.moonstone/' \
  '.meteorite/' \
  '.zig-cache/' \
  'zig-cache/' \
  'zig-out/' \
  'dist/' \
  'bench/competitors/**/node_modules/' \
  'bench/competitors/**/target/' \
  'bench/competitors/**/logs/'; do
  if ! grep -Fqx "$required_pattern" .gitignore; then
    echo "repository hygiene: missing .gitignore rule: $required_pattern" >&2
    exit 1
  fi
done

if grep -En '"(hono|@hono/node-server)"[[:space:]]*:[[:space:]]*"(latest|\^|~|\*)' \
  bench/competitors/hono/package.json >/dev/null; then
  echo "repository hygiene: Hono benchmark dependencies must use exact versions" >&2
  exit 1
fi

echo "PASS: repository hygiene"
