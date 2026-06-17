#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BALLAD_PATH="${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?.lua;${ROOT}/../ballad/.moonstone/env/share/lua/5.1/?/init.lua;${ROOT}/../ballad/src/?.lua;${ROOT}/../ballad/src/?/init.lua;;"

cd "$ROOT"
export MOONSTONE_HOME="$ROOT/.moonstone-home"
while read -r pid; do
  if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi
done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
sleep 0.2
LUA_PATH="$BALLAD_PATH" luajit ../ballad/src/main.lua play partiture-test.lua >/tmp/meteorite-partiture-test.log

test -f fixtures/basic-service/.meteorite/graph/current/graph.zig
test -f fixtures/basic-service/.meteorite/graph/current/patterns.graph.json
test -x fixtures/basic-service/dist/server

grep -q '"strategy": "class_dfa"' fixtures/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"alphabet_classes": 5' fixtures/basic-service/.meteorite/graph/current/patterns.graph.json
grep -q '"backtracking": false' fixtures/basic-service/.meteorite/graph/current/patterns.graph.json

fixtures/basic-service/dist/server >/tmp/meteorite-basic-service.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
sleep 0.5

expect_body() {
  local expected="$1"
  local url="$2"
  local actual
  actual="$(curl -sS "$url")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $url -> $expected, got $actual" >&2
    exit 1
  fi
}

expect_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl -sS -o /tmp/meteorite-status.out -w '%{http_code}' "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected status $expected for curl $*, got $actual" >&2
    cat /tmp/meteorite-status.out >&2 || true
    exit 1
  fi
}

expect_body ok http://127.0.0.1:8080/health
expect_body 123 http://127.0.0.1:8080/users/123
expect_body router_01 http://127.0.0.1:8080/devices/router_01
expect_body report-01.txt http://127.0.0.1:8080/files/report-01.txt
expect_body release_64 http://127.0.0.1:8080/slugs/release_64
expect_body 550e8400-e29b-41d4-a716-446655440000 http://127.0.0.1:8080/uuids/550e8400-e29b-41d4-a716-446655440000
expect_body 0123456789abcdef0123456789abcdef http://127.0.0.1:8080/hex/0123456789abcdef0123456789abcdef
[[ "$(curl -sS -X POST --data 'hello body' http://127.0.0.1:8080/echo)" == "hello body" ]]
expect_status 404 http://127.0.0.1:8080/missing
expect_status 405 -X POST http://127.0.0.1:8080/health
expect_status 404 http://127.0.0.1:8080/users/not-a-number
expect_status 404 http://127.0.0.1:8080/devices/INVALID
expect_status 404 http://127.0.0.1:8080/files/../../secret
expect_status 404 http://127.0.0.1:8080/slugs/bad.slug
expect_status 404 http://127.0.0.1:8080/uuids/not-a-uuid
expect_status 404 http://127.0.0.1:8080/hex/abc
python3 - <<'PY' >/tmp/meteorite-big-body.txt
print('x' * 9000, end='')
PY
expect_status 413 -X POST --data-binary @/tmp/meteorite-big-body.txt http://127.0.0.1:8080/echo

tmp_missing="$(mktemp -d /tmp/meteorite-missing-handler.XXXXXX)"
cp -R fixtures/basic-service/. "$tmp_missing/"
python3 - <<'PY' "$tmp_missing/src/app.lua"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('"handlers.health"', '"handlers.missing"')
p.write_text(s)
PY
python3 - <<'PY' "$tmp_missing/build.zig" "$ROOT"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
root = sys.argv[2]
s = p.read_text()
s = s.replace('"../../src/meteorite/cli.lua"', f'"{root}/src/meteorite/cli.lua"')
s = s.replace('b.path("../../native/src/meteorite.zig")', f'.{{ .cwd_relative = "{root}/native/src/meteorite.zig" }}')
p.write_text(s)
PY
(cd "$tmp_missing" && ! zig build install-server >/tmp/meteorite-missing-build.log 2>&1)
grep -q 'route GET /health references missing handler `handlers.missing`' /tmp/meteorite-missing-build.log
grep -q 'declared at:' /tmp/meteorite-missing-build.log
grep -q 'define `pub fn missing(ctx: anytype) !void`' /tmp/meteorite-missing-build.log

tmp_budget="$(mktemp -d /tmp/meteorite-pattern-budget.XXXXXX)"
cp -R fixtures/basic-service/. "$tmp_budget/"
python3 - <<'PY' "$tmp_budget/src/app.lua"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('max_dfa_bytes = "8kb"', 'max_dfa_bytes = "128"')
p.write_text(s)
PY
(cd "$tmp_budget" && ! luajit "$ROOT/src/meteorite/cli.lua" graph src/main.lua .meteorite/graph/current release-static >/tmp/meteorite-budget.log 2>&1)
grep -q 'pattern exceeded DFA budget' /tmp/meteorite-budget.log
grep -q 'generated_states' /tmp/meteorite-budget.log
grep -q 'estimated_size' /tmp/meteorite-budget.log

echo "PASS: Meteorite basic-service fixture acceptance"
