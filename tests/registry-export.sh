#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_ROOT="$ROOT/dist/registry/meteorite"
LUA_PROJECT_PATH="${ROOT}/src/?.lua;${ROOT}/src/?/init.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?.lua;${ROOT}/../ballad/dist/ballad/libexec/ballad/lua/?/init.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

cd "$ROOT"
if ! LUA_PATH="$LUA_PROJECT_PATH" luajit ../ballad/src/main.lua play partiture.lua \
  >/tmp/meteorite-registry-export.log 2>&1; then
  tail -n 160 /tmp/meteorite-registry-export.log >&2 || true
  exit 1
fi

test -f "$REGISTRY_ROOT/package.toml"
archive="$(find "$REGISTRY_ROOT" -maxdepth 1 -type f -name '*.tar.zst' -print -quit)"
if [[ -z "$archive" ]]; then
  echo "registry export: source archive not found" >&2
  exit 1
fi

contents="$(zstd -dc "$archive" | tar -tf -)"
for required_path in README.md docs/roadmap/v0.1-ga.md; do
  if ! grep -Fqx "./$required_path" <<<"$contents" && ! grep -Fqx "$required_path" <<<"$contents"; then
    echo "registry export: source archive missing $required_path" >&2
    exit 1
  fi
done

for forbidden_path in moonstone.toml moonstone.lock; do
  if grep -Fqx "./$forbidden_path" <<<"$contents" || grep -Fqx "$forbidden_path" <<<"$contents"; then
    echo "registry export: source archive contains development manifest $forbidden_path" >&2
    exit 1
  fi
done

while IFS= read -r archive_path; do
  case "$archive_path" in
    ./.moonstone/* | .moonstone/* | \
    ./.meteorite/* | .meteorite/* | \
    ./.ballad/* | .ballad/* | \
    ./.zig-cache/* | .zig-cache/* | \
    ./zig-cache/* | zig-cache/* | \
    ./zig-out/* | zig-out/* | \
    ./dist/* | dist/* | \
    ./fixtures/* | fixtures/* | \
    ./.git/* | .git/*)
      echo "registry export: source archive contains excluded root path $archive_path" >&2
      exit 1
      ;;
  esac
done <<<"$contents"

echo "PASS: Meteorite registry source export"
