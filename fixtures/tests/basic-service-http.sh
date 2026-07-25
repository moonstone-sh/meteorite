#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
meteorite_test_setup
meteorite_test_trap "basic-service-http"

if [[ "${METEORITE_BASIC_SERVICE_BUILT:-0}" != "1" ]]; then
  bash fixtures/tests/basic-service-build.sh
fi

while read -r pid; do
  [[ -z "${pid:-}" ]] || kill "$pid" 2>/dev/null || true
done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)

fixtures/apps/basic-service/dist/server >/tmp/meteorite-basic-service.log 2>&1 &
server_pid=$!
source "fixtures/tests/cleanup.sh"
register_pid "$server_pid"
sleep 0.5

expect_body() {
  local actual
  actual="$(curl -sS "$2")"
  [[ "$actual" == "$1" ]]
}

expect_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl -sS -o /tmp/meteorite-status.out -w '%{http_code}' "$@")"
  [[ "$actual" == "$expected" ]]
}

expect_body ok http://127.0.0.1:8080/health
expect_body 123 http://127.0.0.1:8080/users/123
[[ "$(curl -sS -X PUT --data 'replace user' http://127.0.0.1:8080/users/123)" == "123" ]]
[[ "$(curl -sS -X PATCH --data 'patch user' http://127.0.0.1:8080/users/123)" == "123" ]]
[[ "$(curl -sS -X DELETE http://127.0.0.1:8080/users/123)" == "123" ]]
expect_body router_01 http://127.0.0.1:8080/devices/router_01
expect_body report-01.txt http://127.0.0.1:8080/files/report-01.txt
expect_body release_64 http://127.0.0.1:8080/slugs/release_64
expect_body 550e8400-e29b-41d4-a716-446655440000 http://127.0.0.1:8080/uuids/550e8400-e29b-41d4-a716-446655440000
expect_body 0123456789abcdef0123456789abcdef http://127.0.0.1:8080/hex/0123456789abcdef0123456789abcdef
expect_body lua 'http://127.0.0.1:8080/search?q=lua&page=2&exact=true'
[[ "$(curl -sS -X POST --data 'hello body' http://127.0.0.1:8080/echo)" == "hello body" ]]
expect_status 404 http://127.0.0.1:8080/missing
expect_status 405 -X POST http://127.0.0.1:8080/health
expect_status 405 -X PUT http://127.0.0.1:8080/health
expect_status 404 http://127.0.0.1:8080/users/not-a-number
expect_status 404 http://127.0.0.1:8080/devices/INVALID
expect_status 404 http://127.0.0.1:8080/files/../../secret
expect_status 404 http://127.0.0.1:8080/slugs/bad.slug
expect_status 404 http://127.0.0.1:8080/uuids/not-a-uuid
expect_status 404 http://127.0.0.1:8080/hex/abc
expect_status 400 http://127.0.0.1:8080/search
expect_status 400 'http://127.0.0.1:8080/search?q=lua&page=abc'
too_many_pairs="$(python3 - <<'PY'
print('&'.join('q%d=x' % i for i in range(70)), end='')
PY
)"
expect_status 414 "http://127.0.0.1:8080/health?${too_many_pairs}"
python3 - <<'PY' >/tmp/meteorite-big-body.txt
print('x' * 9000, end='')
PY
expect_status 413 -X POST --data-binary @/tmp/meteorite-big-body.txt http://127.0.0.1:8080/echo
expect_status 413 -X DELETE --data 'unexpected' http://127.0.0.1:8080/users/123

echo "PASS: basic-service HTTP smoke"
