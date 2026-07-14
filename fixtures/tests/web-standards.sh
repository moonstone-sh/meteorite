#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="/tmp/meteorite-web-standards-server"
GRAPH=".meteorite/graph/web-standards"
LOG="/tmp/meteorite-web-standards.log"

cd "$ROOT"
export MOONSTONE_HOME="$ROOT/.moonstone-home"
while read -r pid; do
  if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi
done < <(lsof -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true)
sleep 0.2

zig build \
  -Dgraph-input=fixtures/apps/web-standards/src/main.lua \
  -Dgraph-output="$GRAPH" \
  -Dmode=release-hybrid \
  -Dhybrid-profile=optimized \
  -Dfast-http-strategy=pool \
  -Dfast-http-workers=1 \
  -- "$BIN" >/tmp/meteorite-web-standards-build.log

test -x "$BIN"
"$BIN" >"$LOG" 2>&1 &
server_pid=$!
source "$(dirname "${BASH_SOURCE[0]}")/cleanup.sh"
register_pid "$server_pid"

for _ in $(seq 1 100); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsS http://127.0.0.1:8080/health >/dev/null

expect_body() {
  local expected="$1" path="$2"
  shift 2
  local actual
  actual="$(curl -fsS "$@" "http://127.0.0.1:8080$path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $path -> $expected, got $actual" >&2
    exit 1
  fi
}

expect_status() {
  local expected="$1" path="$2"
  shift 2
  local actual
  actual="$(curl -sS -o /tmp/meteorite-web-standards-body -w '%{http_code}' "$@" "http://127.0.0.1:8080$path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected status $expected for $path, got $actual" >&2
    cat /tmp/meteorite-web-standards-body >&2 || true
    exit 1
  fi
}

expect_method_status() {
  local expected="$1" method="$2" path="$3"
  shift 3
  local actual
  if [[ "$method" == "HEAD" ]]; then
    actual="$(curl -sS --head -o /tmp/meteorite-web-standards-body -w '%{http_code}' "http://127.0.0.1:8080$path")"
  else
    actual="$(curl -sS -o /tmp/meteorite-web-standards-body -w '%{http_code}' -X "$method" "$@" "http://127.0.0.1:8080$path")"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "expected status $expected for $method $path, got $actual" >&2
    cat /tmp/meteorite-web-standards-body >&2 || true
    exit 1
  fi
}

expect_method_body() {
  local expected="$1" method="$2" path="$3"
  shift 3
  local actual
  actual="$(curl -fsS -X "$method" "$@" "http://127.0.0.1:8080$path")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $method $path -> $expected, got $actual" >&2
    exit 1
  fi
}

expect_method_status_body() {
  local expected_status="$1" expected_body="$2" method="$3" path="$4"
  shift 4
  local actual_status actual_body
  actual_body="/tmp/meteorite-web-standards-status-body"
  actual_status="$(curl -sS -o "$actual_body" -w '%{http_code}' -X "$method" "$@" "http://127.0.0.1:8080$path")"
  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "expected status $expected_status for $method $path, got $actual_status" >&2
    cat "$actual_body" >&2 || true
    exit 1
  fi
  if [[ "$(cat "$actual_body")" != "$expected_body" ]]; then
    echo "expected body for $method $path: $expected_body" >&2
    echo "got: $(cat "$actual_body")" >&2
    exit 1
  fi
}

expect_header() {
  local path="$1" header="$2" expected="$3"
  shift 3
  local actual
  actual="$(curl -fsS -D - -o /tmp/meteorite-web-standards-body "$@" "http://127.0.0.1:8080$path" |
    awk -v wanted="$(printf '%s' "$header" | tr '[:upper:]' '[:lower:]')" '
      /^[^:]+:/ {
        name = substr($0, 1, index($0, ":") - 1)
        value = substr($0, index($0, ":") + 1)
        gsub(/^[ \t]+|[ \t\r]+$/, "", value)
        if (tolower(name) == wanted) found = value
      }
      END { print found }
    ')"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $path header $header: $expected, got: $actual" >&2
    exit 1
  fi
}

header_value() {
  local path="$1" header="$2"
  shift 2
  curl -fsS -D - -o /tmp/meteorite-web-standards-body "$@" "http://127.0.0.1:8080$path" |
    awk -v wanted="$(printf '%s' "$header" | tr '[:upper:]' '[:lower:]')" '
      /^[^:]+:/ {
        name = substr($0, 1, index($0, ":") - 1)
        value = substr($0, index($0, ":") + 1)
        gsub(/^[ \t]+|[ \t\r]+$/, "", value)
        if (tolower(name) == wanted) found = value
      }
      END { print found }
    '
}

expect_method_header() {
  local method="$1" path="$2" header="$3" expected="$4"
  shift 4
  local actual
  local curl_args=(-sS -D - -o /tmp/meteorite-web-standards-body)
  if [[ "$method" == "HEAD" ]]; then
    curl_args+=(--head)
  else
    curl_args+=(-X "$method")
  fi
  actual="$(curl "${curl_args[@]}" "$@" "http://127.0.0.1:8080$path" |
    awk -v wanted="$(printf '%s' "$header" | tr '[:upper:]' '[:lower:]')" '
      /^[^:]+:/ {
        name = substr($0, 1, index($0, ":") - 1)
        value = substr($0, index($0, ":") + 1)
        gsub(/^[ \t]+|[ \t\r]+$/, "", value)
        if (tolower(name) == wanted) found = value
      }
      END { print found }
    ')"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $method $path header $header: $expected, got: $actual" >&2
    exit 1
  fi
}

expect_head_no_body() {
  local path="$1"
  local size
  size="$(curl -fsS --head -o /tmp/meteorite-web-standards-body -w '%{size_download}' "http://127.0.0.1:8080$path")"
  if [[ "$size" != "0" ]]; then
    echo "expected HEAD $path to download 0 bytes, got $size" >&2
    exit 1
  fi
}

raw_http_probe() {
  python3 - "$@" <<'PY'
import socket
import sys

mode = sys.argv[1]

def recv_until(sock, marker):
    data = b""
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    return data

def content_length(head):
    for line in head.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            return int(line.split(b":", 1)[1].strip())
    return 0

def header_value(head, wanted):
    wanted = wanted.lower() + b":"
    for line in head.split(b"\r\n"):
        if line.lower().startswith(wanted):
            return line.split(b":", 1)[1].strip()
    return b""

def assert_response_invariants(response, status_prefix=b"HTTP/1.1 ", require_content_type=True):
    if b"\r\n\r\n" not in response:
        raise SystemExit(f"response missing header terminator: {response!r}")
    head, body = response.split(b"\r\n\r\n", 1)
    status_line = head.split(b"\r\n", 1)[0]
    if not status_line.startswith(status_prefix):
        raise SystemExit(f"bad status line: {status_line!r}")
    if not header_value(head, b"connection"):
        raise SystemExit(f"missing connection header: {response!r}")
    if not header_value(head, b"date"):
        raise SystemExit(f"missing date header: {response!r}")
    length = header_value(head, b"content-length")
    if length and int(length) != len(body):
        raise SystemExit(f"content-length mismatch expected {length!r} got {len(body)}: {response!r}")
    if require_content_type and not header_value(head, b"content-type"):
        raise SystemExit(f"missing content-type header: {response!r}")

def read_response(sock):
    data = recv_until(sock, b"\r\n\r\n")
    if b"\r\n\r\n" not in data:
        return data
    head, body = data.split(b"\r\n\r\n", 1)
    length = content_length(head)
    while len(body) < length:
        chunk = sock.recv(4096)
        if not chunk:
            break
        body += chunk
    return head + b"\r\n\r\n" + body[:length]

if mode == "keepalive":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n")
        first = read_response(sock)
        sock.sendall(b"GET /headers/table HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        second = read_response(sock)
    if b"HTTP/1.1 200" not in first or not first.endswith(b"ok"):
        raise SystemExit(f"bad first keepalive response: {first!r}")
    if b"HTTP/1.1 200" not in second or not second.endswith(b"table-headers"):
        raise SystemExit(f"bad second keepalive response: {second!r}")
    assert_response_invariants(first)
    assert_response_invariants(second)
elif mode == "close-header":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"\r\nconnection: close\r\n" not in response.lower():
        raise SystemExit(f"missing connection close header: {response!r}")
    assert_response_invariants(response)
elif mode == "chunked":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(
            b"POST /body/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            b"4\r\nokay\r\n0\r\n\r\n"
        )
        response = read_response(sock)
    if b"HTTP/1.1 501" not in response or b"chunked request bodies unsupported" not in response:
        raise SystemExit(f"bad chunked rejection response: {response!r}")
    assert_response_invariants(response)
elif mode == "static-gzip":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /static/assets/app.js HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept-Encoding: gzip\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"\r\ncontent-encoding: gzip\r\n" not in response.lower():
        raise SystemExit(f"missing gzip content encoding: {response!r}")
    assert_response_invariants(response)
elif mode == "not-modified":
    etag = sys.argv[2].encode()
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /static/hello.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nIf-None-Match: " + etag + b"\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 304" not in response:
        raise SystemExit(f"bad 304 response: {response!r}")
    assert_response_invariants(response, status_prefix=b"HTTP/1.1 304", require_content_type=False)
elif mode == "bad-method-token":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"G@T /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 400" not in response:
        raise SystemExit(f"bad method token was not rejected: {response!r}")
elif mode == "bad-header-name":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nBad Header: nope\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 400" not in response:
        raise SystemExit(f"bad header name was not rejected: {response!r}")
elif mode == "folded-header":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n folded: nope\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 400" not in response:
        raise SystemExit(f"folded header was not rejected: {response!r}")
elif mode == "missing-header-colon":
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost 127.0.0.1\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 400" not in response:
        raise SystemExit(f"missing header colon was not rejected: {response!r}")
elif mode == "oversized-uri":
    path = b"/" + b"a" * 9000
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET " + path + b" HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 414" not in response:
        raise SystemExit(f"oversized URI was not rejected as 414: {response!r}")
elif mode == "oversized-header":
    value = b"a" * 17000
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nX-Large: " + value + b"\r\nConnection: close\r\n\r\n")
        response = read_response(sock)
    if b"HTTP/1.1 400" not in response:
        raise SystemExit(f"oversized header was not rejected: {response!r}")
else:
    raise SystemExit(f"unknown probe mode: {mode}")
PY
}

expect_body ok /health
raw_http_probe keepalive
raw_http_probe close-header
raw_http_probe chunked
raw_http_probe static-gzip
raw_http_probe bad-method-token
raw_http_probe bad-header-name
raw_http_probe folded-header
raw_http_probe missing-header-colon
raw_http_probe oversized-uri
raw_http_probe oversized-header

if ! grep -q 'validators: params=' .meteorite/graph/web-standards/build-report.txt; then
  echo "expected build report to include validator coverage" >&2
  exit 1
fi
if ! grep -q 'response schemas: declared=1 missing=' .meteorite/graph/web-standards/build-report.txt; then
  echo "expected build report to include response schema coverage" >&2
  exit 1
fi
for needle in 'validation' 'headers' 'cookies' 'json_body' 'form_body' 'x-meteorite-token' 'session' 'email' 'csrf'; do
  if ! grep -q "$needle" .meteorite/graph/web-standards/routes.zon; then
    echo "expected routes.zon validation metadata to include $needle" >&2
    exit 1
  fi
done
for needle in 'meteorite.schema-ir.v0' 'x-meteorite-token' 'session' 'email' 'csrf' 'responses' '200' 'ok' 'additionalProperties = false' 'format = "email"'; do
  if ! grep -q "$needle" .meteorite/graph/web-standards/schemas.zon; then
    echo "expected schemas.zon schema IR to include $needle" >&2
    exit 1
  fi
done
for needle in 'meteorite.openapi-plan.v0' 'openapi = "3.1.0"' 'template = "/validation/contracts/{id}"' 'operationId = "route_' 'in_ = "path"' 'in_ = "query"' 'in_ = "header"' 'in_ = "cookie"' 'application/json' 'application/x-www-form-urlencoded' 'missing_schema = true' 'x-meteorite-token' 'cookie:session' 'ok'; do
  if ! grep -q "$needle" .meteorite/graph/web-standards/openapi-plan.zon; then
    echo "expected openapi-plan.zon to include $needle" >&2
    exit 1
  fi
done

routes_graph_json="/tmp/meteorite-web-standards-routes.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua routes --graph fixtures/apps/web-standards/src/main.lua > "$routes_graph_json"
python3 - "$routes_graph_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    graph = json.load(handle)

assert graph["format"] == "meteorite.routes.v0", graph.get("format")
route = next((item for item in graph["routes"] if item["path"] == "/validation/contracts/:id"), None)
assert route is not None, "missing validation contract route"
assert route["method"] == "POST", route["method"]
assert route["scope"] == {"id": "root", "plugins": []}, route["scope"]
assert any(item["name"] == "id" and item["type"] == "u64" for item in route["params"]), route["params"]
assert any(item["name"] == "verbose" and item["type"] == "bool" for item in route["query"]), route["query"]
assert any(item["name"] == "x-meteorite-token" and item["type"] == "token" for item in route["validation"]["headers"]), route["validation"]
assert any(item["name"] == "session" and item["type"] == "token" for item in route["validation"]["cookies"]), route["validation"]
assert any(item["name"] == "email" and item["type"] == "email" for item in route["validation"]["json_body"]), route["validation"]
assert any(item["name"] == "csrf" and item["type"] == "token" for item in route["validation"]["form_body"]), route["validation"]
assert "200" in route["responses"], route["responses"]
assert route["runtime"]["requires_lua"] is True, route["runtime"]
PY

invoke_json="/tmp/meteorite-web-standards-invoke.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json -H 'Origin: https://app.example' fixtures/apps/web-standards/src/main.lua GET /security/cors > "$invoke_json"
python3 - "$invoke_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    result = json.load(handle)

assert result["format"] == "meteorite.invoke.v0", result.get("format")
assert result["request"]["method"] == "GET", result["request"]
assert result["request"]["path"] == "/security/cors", result["request"]
response = result["response"]
assert response["status"] == 200, response
assert response["content_type"] == "text/plain; charset=utf-8", response
assert response["body"] == "security:cors", response
assert response["headers"]["Access-Control-Allow-Origin"] == "https://app.example", response["headers"]
assert response["headers"]["Access-Control-Allow-Methods"] == "GET, POST, OPTIONS", response["headers"]
assert response["headers"]["Access-Control-Allow-Headers"] == "Content-Type, Authorization", response["headers"]
assert response["headers"]["Access-Control-Expose-Headers"] == "X-Request-ID", response["headers"]
PY

doctor_output="/tmp/meteorite-web-standards-doctor.txt"
set +e
(
  cd fixtures/apps/web-standards
  LUA_PATH='../../../src/?.lua;../../../src/?/init.lua;src/?.lua;src/?/init.lua;;' ../../../.moonstone/env/bin/lua ../../../src/cli/main.lua doctor > "$doctor_output"
)
doctor_status=$?
set -e
if [ "$doctor_status" -eq 0 ]; then
  echo "expected fixture-local doctor to report missing moonstone.toml" >&2
  exit 1
fi
for needle in 'Meteorite doctor' 'moonstone.toml' 'src/main.lua' 'Moonstone env' 'Lua runtime' 'Meteorite CLI' 'Zig' 'Ballad plugin' 'Ballad core' 'generated graph' 'LuaLS aids' 'static release readiness' 'hybrid release readiness' 'release partiture' 'dev port'; do
  if ! grep -q "$needle" "$doctor_output"; then
    echo "expected doctor output to include $needle" >&2
    exit 1
  fi
done

curl -fsS http://127.0.0.1:8080/__meteorite/info > /tmp/meteorite-web-standards-info.json
python3 - /tmp/meteorite-web-standards-info.json "$ROOT" <<'PY'
import json
import sys

text = open(sys.argv[1], encoding="utf-8").read()
root = sys.argv[2]
info = json.loads(text)
assert info["format"] == "meteorite.info.v0", info
assert info["meteorite_mode"] == "release-hybrid", info
assert info["backend"] == "fast_http", info
assert info["lua_runtime"] is True, info
assert info["router_dispatch"], info
assert info["target"], info
assert root not in text, text
assert "/Users/" not in text, text
assert "fixtures/apps" not in text, text
PY

template_root="/tmp/meteorite-web-standards-init-templates"
rm -rf "$template_root"
mkdir -p "$template_root"
for template in minimal static hybrid middleware cors json-api static-site; do
  ./.moonstone/env/bin/lua src/cli/main.lua init "$template_root/$template" --template "$template" --no-sync --name "web-$template" >/tmp/meteorite-web-standards-init-$template.log
  test -f "$template_root/$template/src/main.lua"
  test -f "$template_root/$template/src/app.lua"
  test -f "$template_root/$template/moonstone.toml"
  test -f "$template_root/$template/partiture.lua"
  mode="hybrid"
  if [ "$template" = "static" ]; then mode="release-static"; fi
  (
    cd "$template_root/$template"
    LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current "$mode" >/tmp/meteorite-web-standards-template-graph-$template.log
  )
done
test -f "$template_root/static-site/site/dist/index.html"
test -f "$template_root/static-site/site/dist/assets/app.js"
grep -q 'ctx:cors_headers' "$template_root/cors/src/app.lua"
grep -q 'm.plugin' "$template_root/middleware/src/app.lua"
grep -q 'json = {' "$template_root/json-api/src/app.lua"

manifest_static_json="/tmp/meteorite-web-standards-manifest-static.json"
manifest_hybrid_json="/tmp/meteorite-web-standards-manifest-hybrid.json"
LUA_PATH='src/?.lua;src/?/init.lua;;' ./.moonstone/env/bin/lua <<'LUA' > "$manifest_static_json"
local manifest = require("ballad.release_manifest")
io.write(manifest.build({
  graph_hash = "b3:test-static",
  graph = {
    routes = {
      { method = "GET", raw_path = "/hello.txt", handler = { kind = "file", artifact_path = "static/hello.txt", content_type = "text/plain", content_length = 5, etag = "abc", cache_control = "public" } },
      { method = "GET", raw_path = "/assets/:path*", handler = { kind = "dir", manifest = { { request_path = "/assets/app.js", artifact_path = "static/assets/app.js", content_type = "application/javascript", content_length = 10, etag = "def", cache_control = "immutable", compressed_gzip_path = "static/assets/app.js.gz" } } } },
    },
  },
}, "static", "bin/server", {
  validation_mode = "static",
  retained_lua_nodes = {},
  requires_target_lua = false,
}, nil, { target = "native" }))
LUA
LUA_PATH='src/?.lua;src/?/init.lua;;' ./.moonstone/env/bin/lua <<'LUA' > "$manifest_hybrid_json"
local manifest = require("ballad.release_manifest")
io.write(manifest.build({
  graph_hash = "b3:test-hybrid",
  graph = { routes = { { method = "GET", raw_path = "/lua", handler = { kind = "inline_lua" } } } },
}, "hybrid", "bin/server", {
  validation_mode = "hybrid",
  retained_lua_nodes = { { kind = "inline route handler", label = "GET /lua", source = "src/main.lua:3:1", hint = "build hybrid" } },
  requires_target_lua = true,
}, { status = "target_build_required", target = "aarch64-linux-gnu", source_payload_path = "/store/lua-5.4.7.tar.gz", source_kind = "puc_lua_source" }, { target = "aarch64-linux-gnu" }))
LUA
python3 - "$manifest_static_json" "$manifest_hybrid_json" <<'PY'
import json
import sys

static = json.load(open(sys.argv[1], encoding="utf-8"))
hybrid = json.load(open(sys.argv[2], encoding="utf-8"))

assert static["format"] == "meteorite.release.v0", static
assert static["graph_hash"] == "b3:test-static", static
assert static["route_count"] == 2 and static["routes"] == 2, static
assert static["target"]["abi"] == "native", static
assert static["retained_lua_nodes"] == {"count": 0, "nodes": []}, static["retained_lua_nodes"]
assert static["contract"]["retained_lua_nodes"] == 0, static["contract"]
assert static["static"]["count"] == 2, static["static"]
assert static["static"]["guarantee"] == "no_lua_runtime_execution_nodes", static["static"]
assert static["static"]["lua_runtime_execution_nodes"] == 0, static["static"]
assert any(asset["compressed_gzip_path"] == "static/assets/app.js.gz" for asset in static["static"]["assets"]), static["static"]
assert static["runtime_source"]["status"] == "not_required", static["runtime_source"]

assert hybrid["graph_hash"] == "b3:test-hybrid", hybrid
assert hybrid["route_count"] == 1, hybrid
assert hybrid["target"]["abi"] == "aarch64-linux-gnu", hybrid["target"]
assert hybrid["retained_lua_nodes"]["count"] == 1, hybrid["retained_lua_nodes"]
assert hybrid["retained_lua_nodes"]["nodes"][0]["source"] == "src/main.lua:3:1", hybrid["retained_lua_nodes"]
assert hybrid["contract"]["retained_lua_node_details"][0]["kind"] == "inline route handler", hybrid["contract"]
assert hybrid["runtime_source"]["status"] == "packaged", hybrid["runtime_source"]
assert hybrid["runtime_source"]["artifact_path"] == "runtime/source/lua-5.4.7.tar.gz", hybrid["runtime_source"]
assert hybrid["runtime_source"]["source_kind"] == "puc_lua_source", hybrid["runtime_source"]
assert hybrid["target_lua"]["source_payload_path"] == "runtime/source/lua-5.4.7.tar.gz", hybrid["target_lua"]
assert hybrid["static"]["count"] == 0, hybrid["static"]
PY

LUA_PATH='src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;;' ./.moonstone/env/bin/lua <<'LUA'
local release_contract = require("ballad.release_contract")
local release_assets = require("ballad.release_assets")

local function fail_context()
  local ctx = { message = nil }
  ctx.fail = function(first, second)
    local message = second or first
    ctx.message = message
    error(message, 0)
  end
  return ctx
end

local static_ctx = fail_context()
local ok = pcall(function()
  release_contract.assert_static_graph(static_ctx, {
    routes = {
      {
        method = "GET",
        raw_path = "/lua",
        handler = { kind = "inline_lua" },
        source = { file = "src/main.lua", line = 3, column = 1 },
      },
    },
  })
end)
assert(not ok, "static graph guard must reject retained Lua nodes")
assert(static_ctx.message:find("produced a graph with Lua runtime execution nodes", 1, true), static_ctx.message)
assert(static_ctx.message:find("Remediation:", 1, true), static_ctx.message)

local asset_ctx = fail_context()
ok = pcall(function()
  release_assets.assert_static_release_assets(asset_ctx, {
    assets = {
      { kind = "meteorite_server", virtual_path = "bin/server" },
      { kind = "lua_runtime", virtual_path = "runtime/lua/bin/lua" },
      { kind = "meteorite_lua_chunk", virtual_path = ".meteorite/lua/inline/route_1.lua" },
    },
  })
end)
assert(not ok, "static asset guard must reject Lua runtime artifacts")
assert(asset_ctx.message:find("attempted to package Lua runtime artifacts", 1, true), asset_ctx.message)
assert(asset_ctx.message:find("lua_runtime runtime/lua/bin/lua", 1, true), asset_ctx.message)
assert(asset_ctx.message:find("meteorite_lua_chunk .meteorite/lua/inline/route_1.lua", 1, true), asset_ctx.message)

release_assets.assert_static_release_assets(fail_context(), {
  assets = {
    { kind = "meteorite_server", virtual_path = "bin/server" },
    { kind = "meteorite_static_asset", virtual_path = "static/index.html" },
  },
})

local retained_contract = {
  validation_mode = "hybrid",
  requires_target_lua = true,
  retained_lua_nodes = {
    { kind = "inline route handler", label = "GET /lua", source = "src/main.lua:3:1" },
  },
}
local missing_runtime_ctx = fail_context()
ok = pcall(function()
  release_contract.validate_target_lua(missing_runtime_ctx, ".", retained_contract, { target = "aarch64-linux-gnu" })
end)
assert(not ok, "cross-target hybrid must fail without Lua runtime source provenance")
assert(missing_runtime_ctx.message:find("source_payload_path", 1, true), missing_runtime_ctx.message)
assert(missing_runtime_ctx.message:find("source provenance", 1, true), missing_runtime_ctx.message)
assert(missing_runtime_ctx.message:find("Target ABI:", 1, true), missing_runtime_ctx.message)
assert(missing_runtime_ctx.message:find("Remediation:", 1, true), missing_runtime_ctx.message)

local prebuilt_runtime_ctx = fail_context()
ok = pcall(function()
  release_contract.validate_target_lua(prebuilt_runtime_ctx, ".", retained_contract, {
    target = "aarch64-linux-gnu",
    runtime_source = "moonstone-runtime.tar.gz",
    runtime_source_kind = "runtime",
  })
end)
assert(not ok, "cross-target hybrid must reject prebuilt runtime payloads")
assert(prebuilt_runtime_ctx.message:find("cannot build a transportable Lua runtime", 1, true), prebuilt_runtime_ctx.message)
assert(prebuilt_runtime_ctx.message:find("source_kind: runtime", 1, true), prebuilt_runtime_ctx.message)
assert(prebuilt_runtime_ctx.message:find("target_abi: aarch64-linux-gnu", 1, true), prebuilt_runtime_ctx.message)
assert(prebuilt_runtime_ctx.message:find("Remediation:", 1, true), prebuilt_runtime_ctx.message)

local cmodule_ctx = fail_context()
ok = pcall(function()
  release_contract.validate_packages(cmodule_ctx, retained_contract, {
    target = "aarch64-linux-gnu",
    packages = { { name = "lfs", kind = "lua_cmodule" } },
  })
end)
assert(not ok, "cross-target hybrid must reject C modules without source provenance")
assert(cmodule_ctx.message:find("Lua C module `lfs`", 1, true), cmodule_ctx.message)
assert(cmodule_ctx.message:find("package.source_payload_path", 1, true), cmodule_ctx.message)
assert(cmodule_ctx.message:find("Remediation:", 1, true), cmodule_ctx.message)
LUA

hybrid_assets_root="/tmp/meteorite-web-standards-hybrid-assets"
rm -rf "$hybrid_assets_root"
mkdir -p "$hybrid_assets_root/.meteorite/lua/inline" "$hybrid_assets_root/src/utils" "$hybrid_assets_root/src/unused"
cat > "$hybrid_assets_root/.meteorite/lua/inline/route_1.lua" <<'LUA'
local helper = require("utils.helper")
return function(ctx)
  return ctx:text(helper.message)
end
LUA
cat > "$hybrid_assets_root/src/handler.lua" <<'LUA'
local extra = require("utils.extra")
return function(ctx)
  return ctx:text(extra.message)
end
LUA
cat > "$hybrid_assets_root/src/utils/helper.lua" <<'LUA'
return { message = "helper" }
LUA
cat > "$hybrid_assets_root/src/utils/extra.lua" <<'LUA'
return { message = "extra" }
LUA
cat > "$hybrid_assets_root/src/unused/secret.lua" <<'LUA'
return { message = "do not package" }
LUA
LUA_PATH='src/?.lua;src/?/init.lua;../ballad/src/?.lua;../ballad/src/?/init.lua;;' HYBRID_ASSETS_ROOT="$hybrid_assets_root" ./.moonstone/env/bin/lua <<'LUA'
local graph = require("ballad.graph")
local release_assets = require("ballad.release_assets")
local root = assert(os.getenv("HYBRID_ASSETS_ROOT"))
local collected = {}
local ctx = {
  graph = {
    add_asset = function(_, asset)
      local wrapped = graph.Asset.new(asset)
      collected[#collected + 1] = wrapped
      return wrapped
    end,
  },
}
local assets = release_assets.new_set()
release_assets.add_hybrid_lua_assets(ctx, assets, root, {
  routes = {
    { id = "route_1", handler = { kind = "inline_lua", lifted = { chunk_path = ".meteorite/lua/inline/route_1.lua" } } },
    { id = "route_2", handler = { kind = "lua", path = "src/handler.lua" } },
  },
  plugins = {},
})
local found = {}
local kinds = {}
for _, asset in ipairs(collected) do
  found[asset.virtual_path] = true
  kinds[asset.virtual_path] = asset.kind
end
assert(found[".meteorite/lua/inline/route_1.lua"], "inline chunk must be packaged")
assert(kinds[".meteorite/lua/inline/route_1.lua"] == "meteorite_lua_chunk", "inline chunk kind")
assert(found["src/handler.lua"], "Lua file handler must be packaged")
assert(kinds["src/handler.lua"] == "meteorite_lua_handler", "handler kind")
assert(found["src/utils/helper.lua"], "inline chunk dependency must be packaged")
assert(found["src/utils/extra.lua"], "handler dependency must be packaged")
assert(kinds["src/utils/helper.lua"] == "meteorite_lua_module", "dependency kind")
assert(not found["src/unused/secret.lua"], "unused source files must not be packaged")
assert(not found["src/main.lua"], "app entrypoint should not be copied unless required")
LUA

diag_root="/tmp/meteorite-web-standards-diagnostics"
rm -rf "$diag_root"
mkdir -p "$diag_root/static/src" "$diag_root/upvalue/src"
cat > "$diag_root/static/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "diag-static" })
app:get("/lua", function(ctx)
  return ctx:text("lua")
end)
return app
LUA
set +e
(
  cd "$diag_root/static"
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current release-static > /tmp/meteorite-web-standards-static-diag.log 2>&1
)
static_diag_status=$?
set -e
if [ "$static_diag_status" -eq 0 ]; then
  echo "expected release-static Lua diagnostic to fail" >&2
  exit 1
fi
for needle in 'static build cannot include inline Lua handler' 'mode:' 'release-static' 'route id:' 'route_1' 'route:' 'GET /lua' 'declared at:' 'remediation:' 'build hybrid'; do
  if ! grep -q "$needle" /tmp/meteorite-web-standards-static-diag.log; then
    echo "expected static diagnostic to include $needle" >&2
    exit 1
  fi
done

cat > "$diag_root/upvalue/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "diag-upvalue" })
local message = "captured"
app:get("/capture", function(ctx)
  return ctx:text(message)
end)
return app
LUA
set +e
(
  cd "$diag_root/upvalue"
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid > /tmp/meteorite-web-standards-upvalue-diag.log 2>&1
)
upvalue_diag_status=$?
set -e
if [ "$upvalue_diag_status" -eq 0 ]; then
  echo "expected inline Lua upvalue diagnostic to fail" >&2
  exit 1
fi
for needle in 'inline Lua handler captures outer local `message`' 'mode:' 'hybrid' 'route id:' 'route_1' 'route:' 'GET /capture' 'declared at:' 'remediation:' 'm.lua'; do
  if ! grep -q "$needle" /tmp/meteorite-web-standards-upvalue-diag.log; then
    echo "expected upvalue diagnostic to include $needle" >&2
    exit 1
  fi
done

dev_reload_root="/tmp/meteorite-web-standards-dev-reload"
rm -rf "$dev_reload_root"
mkdir -p "$dev_reload_root/lua/src" "$dev_reload_root/asset/src" "$dev_reload_root/asset/public" "$dev_reload_root/shape/src"
cat > "$dev_reload_root/lua/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "dev-lua" })
app:get("/", function(ctx)
  return ctx:text("one")
end)
return app
LUA
(
  cd "$dev_reload_root/lua"
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-lua-1.log
  perl -0pi -e 's/one/two/' src/main.lua
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-lua-2.log
)
lua_classification="$($ROOT/.moonstone/env/bin/lua "$ROOT/src/cli/dev.lua" --classify-partitions "$dev_reload_root/lua/.meteorite/graph/current")"
if [[ "$lua_classification" != $'reload	Lua-only handler chunks changed' ]]; then
  echo "expected Lua-only classification, got: $lua_classification" >&2
  exit 1
fi
(
  cd "$dev_reload_root/lua"
  perl -0pi -e 's/two/three/' src/main.lua
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-lua-3.log
)
lua_second_classification="$($ROOT/.moonstone/env/bin/lua "$ROOT/src/cli/dev.lua" --classify-partitions "$dev_reload_root/lua/.meteorite/graph/current")"
if [[ "$lua_second_classification" != $'reload	Lua-only handler chunks changed' ]]; then
  echo "expected second Lua-only classification, got: $lua_second_classification" >&2
  exit 1
fi

printf 'one\n' > "$dev_reload_root/asset/public/hello.txt"
cat > "$dev_reload_root/asset/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "dev-asset" })
app:get("/hello.txt", m.file("public/hello.txt", { content_type = "text/plain" }))
return app
LUA
(
  cd "$dev_reload_root/asset"
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-asset-1.log
  printf 'two\n' > public/hello.txt
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-asset-2.log
)
asset_classification="$($ROOT/.moonstone/env/bin/lua "$ROOT/src/cli/dev.lua" --classify-partitions "$dev_reload_root/asset/.meteorite/graph/current")"
if [[ "$asset_classification" != $'rebuild	static asset partitions changed' ]]; then
  echo "expected static-asset classification, got: $asset_classification" >&2
  exit 1
fi

cat > "$dev_reload_root/shape/src/main.lua" <<'LUA'
local m = require("meteorite")
local app = m.app({ name = "dev-shape" })
app:get("/one", function(ctx)
  return ctx:text("one")
end)
return app
LUA
(
  cd "$dev_reload_root/shape"
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-shape-1.log
  perl -0pi -e 's#/one#/two#' src/main.lua
  LUA_PATH="$ROOT/src/?.lua;$ROOT/src/?/init.lua;src/?.lua;src/?/init.lua;;" "$ROOT/.moonstone/env/bin/lua" "$ROOT/src/cli/main.lua" graph src/main.lua .meteorite/graph/current hybrid >/tmp/meteorite-web-standards-dev-shape-2.log
)
shape_classification="$($ROOT/.moonstone/env/bin/lua "$ROOT/src/cli/dev.lua" --classify-partitions "$dev_reload_root/shape/.meteorite/graph/current")"
if [[ "$shape_classification" != $'rebuild	graph-shape partitions changed' ]]; then
  echo "expected graph-shape classification, got: $shape_classification" >&2
  exit 1
fi
force_classification="$($ROOT/.moonstone/env/bin/lua "$ROOT/src/cli/dev.lua" --classify-partitions "$dev_reload_root/lua/.meteorite/graph/current" true)"
if [[ "$force_classification" != $'rebuild	zig/build input changed' ]]; then
  echo "expected Zig/build force classification, got: $force_classification" >&2
  exit 1
fi

LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua <<'LUA'
local app = require("main")
local hybrid = require("cli.hybrid")

local function expect_validation(response, domain, field, reason)
  assert(response.status == 400, "expected local invoke status 400, got " .. tostring(response.status))
  assert(response.body == "validation error", "expected validation error body")
  assert(response.headers["X-Meteorite-Validation-Domain"] == domain, "domain mismatch")
  assert(response.headers["X-Meteorite-Validation-Field"] == field, "field mismatch")
  assert(response.headers["X-Meteorite-Validation-Reason"] == reason, "reason mismatch")
end

expect_validation(hybrid.invoke(app, { method = "GET", path = "/query/typed?page=2" }, { mode = "dev" }), "query", "q", "missing")
expect_validation(hybrid.invoke(app, { method = "POST", path = "/validation/contracts/123", headers = { Cookie = "session=abc_123" } }, { mode = "dev" }), "header", "x-meteorite-token", "missing")
expect_validation(hybrid.invoke(app, { method = "POST", path = "/validation/contracts/123", headers = { ["X-Meteorite-Token"] = "abc_123" } }, { mode = "dev" }), "cookie", "session", "missing")
expect_validation(hybrid.invoke(app, { method = "POST", path = "/validation/contracts/123", headers = { ["X-Meteorite-Token"] = "abc_123", Cookie = "session=abc_123", ["Content-Type"] = "application/x-www-form-urlencoded" }, body = "csrf=bad token!" }, { mode = "dev" }), "form", "csrf", "invalid")
expect_validation(hybrid.invoke(app, { method = "POST", path = "/validation/contracts/123", headers = { ["X-Meteorite-Token"] = "abc_123", Cookie = "session=abc_123", ["Content-Type"] = "application/json" }, body = '{"email":"not-an-email"}' }, { mode = "dev" }), "json", "email", "invalid")
LUA

expect_body 'hello static' /static/hello.txt
expect_header /static/hello.txt content-type 'text/plain; charset=utf-8'
expect_header /static/hello.txt cache-control 'public, max-age=60'
static_etag="$(header_value /static/hello.txt etag)"
if [[ -z "$static_etag" ]]; then
  echo "expected /static/hello.txt to emit an etag" >&2
  exit 1
fi
expect_status 304 /static/hello.txt -H "If-None-Match: $static_etag"
raw_http_probe not-modified "$static_etag"
expect_method_status 200 HEAD /static/hello.txt
expect_head_no_body /static/hello.txt

expect_body '<!doctype html><title>Meteorite Standards</title><h1>standards</h1>' /static/html -H 'Accept: text/html'
expect_status 404 /static/html -H 'Accept: application/json'
expect_body 'console.log("meteorite standards");' /static/assets/app.js
expect_header /static/assets/app.js content-type application/javascript
expect_header /static/assets/app.js content-encoding gzip -H 'Accept-Encoding: gzip'
expect_status 404 /static/assets/../hello.txt --path-as-is
expect_status 404 /static/assets/%2e%2e/hello.txt --path-as-is
expect_status 404 /static/assets/app%2f.js --path-as-is
expect_status 404 /static/assets/app%5c.js --path-as-is

symlink_fixture="/tmp/meteorite-web-standards-symlink"
rm -rf "$symlink_fixture"
mkdir -p "$symlink_fixture/public"
printf 'safe\n' >"$symlink_fixture/public/safe.txt"
ln -s /etc/passwd "$symlink_fixture/public/escape.txt"
cat >"$symlink_fixture/main.lua" <<LUA
local m = require("meteorite")
local app = m.app({ name = "web-standards-symlink", host = "127.0.0.1", port = 8099 })
app:get("/assets/:path*", m.dir("$symlink_fixture/public", { param = "path" }))
return app
LUA
if ./.moonstone/env/bin/lua src/cli/main.lua graph "$symlink_fixture/main.lua" "$symlink_fixture/graph" release-hybrid >/tmp/meteorite-web-standards-symlink.log 2>&1; then
  echo "expected static symlink fixture graph generation to fail" >&2
  exit 1
fi
if ! grep -q 'static directory contains symlinks' /tmp/meteorite-web-standards-symlink.log; then
  echo "expected static symlink diagnostic" >&2
  cat /tmp/meteorite-web-standards-symlink.log >&2
  exit 1
fi
rm -rf "$symlink_fixture"

expect_body table-headers /headers/table
expect_header /headers/table X-Meteorite-Test table
expect_header /headers/table Access-Control-Allow-Origin '*'

expect_body text-helper /headers/text-helper
expect_header /headers/text-helper X-Meteorite-Test text-helper

expect_body '{"ok":true}' /headers/json-helper
expect_header /headers/json-helper X-Meteorite-Test json-helper
expect_header /headers/json-helper content-type application/json

expect_body bytes-helper /headers/bytes-helper
expect_header /headers/bytes-helper X-Meteorite-Test bytes-helper
expect_header /headers/bytes-helper content-type text/custom

expect_body 'lower=LuaValue;upper=LuaValue' /headers/request-lua -H 'X-Meteorite-Request: LuaValue'
expect_body 'lower=ZigValue;upper=ZigValue' /headers/request-zig -H 'x-meteorite-request: ZigValue'

expect_method_status_body 201 zig-text GET /headers/zig-text
expect_header /headers/zig-text X-Meteorite-Zig text
expect_method_status_body 202 '{"ok":true}' GET /headers/zig-json
expect_header /headers/zig-json X-Meteorite-Zig json
expect_header /headers/zig-json content-type application/json
expect_method_status_body 203 zig-bytes GET /headers/zig-bytes
expect_header /headers/zig-bytes X-Meteorite-Zig bytes
expect_header /headers/zig-bytes content-type application/octet-stream
expect_method_status 204 GET /headers/zig-empty
expect_header /headers/zig-empty X-Meteorite-Zig empty
expect_body pre-handler:hooked /middleware/pre-handler

expect_invalid_response_header() {
  local path="$1"
  local status headers
  headers="$(mktemp /tmp/meteorite-invalid-headers.XXXXXX)"
  status="$(curl -sS -D "$headers" -o /tmp/meteorite-web-standards-body -w '%{http_code}' "http://127.0.0.1:8080$path")"
  if [[ "$status" != "500" ]]; then
    echo "expected invalid response header route $path to return 500, got $status" >&2
    cat /tmp/meteorite-web-standards-body >&2 || true
    rm -f "$headers"
    exit 1
  fi
  if grep -qi '^Injected:' "$headers"; then
    echo "expected invalid response header route $path to avoid CRLF header injection" >&2
    cat "$headers" >&2
    rm -f "$headers"
    exit 1
  fi
  if grep -qi '^X-Bad:' "$headers" || grep -qi '^X-Meteorite-Test: safe' "$headers" || grep -qi '^X-Meteorite-Zig: safe' "$headers"; then
    echo "expected invalid response header route $path to avoid leaking rejected header" >&2
    cat "$headers" >&2
    rm -f "$headers"
    exit 1
  fi
  rm -f "$headers"
}

expect_invalid_response_header /headers/invalid/reserved
expect_invalid_response_header /headers/invalid/name-crlf
expect_invalid_response_header /headers/invalid/value-crlf
expect_invalid_response_header /headers/invalid/helper-reserved
expect_invalid_response_header /headers/invalid/table-value-crlf
expect_invalid_response_header /headers/invalid/zig-name-crlf
expect_invalid_response_header /headers/invalid/zig-value-crlf
expect_invalid_response_header /headers/invalid/zig-reserved
expect_invalid_response_header /headers/invalid/post-hook-value-crlf
for needle in \
  'pipeline stage error' \
  'route=/headers/invalid/post-hook-value-crlf' \
  'stage_id=post_header_injection_hook' \
  'kind=hook' \
  'strat=zig' \
  'phase=post_handler' \
  'symbol=response_post_header_injection_hook' \
  'error=InvalidResponseHeader'; do
  if ! grep -q "$needle" "$LOG"; then
    echo "expected pipeline stage diagnostic to include $needle" >&2
    cat "$LOG" >&2
    exit 1
  fi
done

expect_body cors:simple /cors/simple
expect_header /cors/simple Access-Control-Allow-Origin '*'

expect_method_status 200 HEAD /head/explicit
expect_method_header HEAD /head/explicit X-Meteorite-Test head-explicit
expect_head_no_body /head/explicit

expect_method_status 200 HEAD /head/implicit
expect_method_header HEAD /head/implicit X-Meteorite-Test head-implicit
expect_head_no_body /head/implicit

expect_method_body post-only POST /method/post-only
expect_method_status 405 GET /method/post-only
expect_method_header GET /method/post-only Allow POST
expect_method_status 405 DELETE /method/multi
expect_method_header DELETE /method/multi Allow 'GET, HEAD, POST'
expect_method_status 200 HEAD /method/get-and-head
expect_method_header DELETE /method/get-and-head Allow 'GET, HEAD'

expect_method_status 204 OPTIONS /cors/preflight
expect_method_header OPTIONS /cors/preflight Access-Control-Allow-Origin '*'
expect_method_header OPTIONS /cors/preflight Access-Control-Allow-Methods 'HEAD, POST'

expect_status 302 /redirect/basic
expect_header /redirect/basic Location /health
expect_status 302 /redirect/zig
expect_header /redirect/zig Location /health

expect_body security:headers /security/headers
expect_header /security/headers X-Content-Type-Options nosniff
expect_header /security/headers X-Frame-Options DENY
expect_header /security/headers Referrer-Policy no-referrer
expect_header /security/headers Cross-Origin-Opener-Policy same-origin
expect_body security:custom /security/headers/custom
expect_header /security/headers/custom Content-Security-Policy "default-src 'self'"
expect_header /security/headers/custom Strict-Transport-Security 'max-age=31536000; includeSubDomains'
expect_header /security/headers/custom Permissions-Policy 'geolocation=()'
expect_body request-id:req-123 /security/request-id -H 'X-Request-ID: req-123'
expect_header /security/request-id X-Request-ID req-123 -H 'X-Request-ID: req-123'
expect_body request-id-zig:req-zig /security/request-id-zig -H 'X-Request-ID: req-zig'
expect_header /security/request-id-zig X-Request-ID req-zig -H 'X-Request-ID: req-zig'
expect_body security:cors /security/cors -H 'Origin: https://app.example'
expect_header /security/cors Access-Control-Allow-Origin 'https://app.example' -H 'Origin: https://app.example'
expect_header /security/cors Access-Control-Allow-Credentials true -H 'Origin: https://app.example'
expect_header /security/cors Access-Control-Expose-Headers X-Request-ID -H 'Origin: https://app.example'
expect_header /security/cors Vary Origin -H 'Origin: https://app.example'
expect_method_status 204 OPTIONS /security/cors -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_header OPTIONS /security/cors Access-Control-Allow-Origin 'https://app.example' -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_header OPTIONS /security/cors Access-Control-Allow-Methods 'GET, POST, OPTIONS' -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_header OPTIONS /security/cors Access-Control-Allow-Headers 'Content-Type, Authorization' -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_header OPTIONS /security/cors Access-Control-Allow-Credentials true -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_header OPTIONS /security/cors Access-Control-Max-Age 600 -H 'Origin: https://app.example' -H 'Access-Control-Request-Method: POST'
expect_method_status 204 OPTIONS /security/cors -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: POST'
if [[ "$(header_value /security/cors Access-Control-Allow-Origin -H 'Origin: https://evil.example')" != "" ]]; then
  echo "expected disallowed CORS origin not to be reflected" >&2
  exit 1
fi

expect_body auth:basic-ok /security/auth/basic -H 'Authorization: Basic bWV0ZW9yaXRlOnJvY2tz'
expect_method_status_body 401 auth:basic-denied GET /security/auth/basic -H 'Authorization: Basic bWV0ZW9yaXRlOndyb25n'
expect_method_header GET /security/auth/basic WWW-Authenticate 'Basic realm="meteorite"'
expect_body auth:bearer-ok /security/auth/bearer -H 'Authorization: Bearer meteorite-secret'
expect_method_status_body 401 auth:bearer-denied GET /security/auth/bearer -H 'Authorization: Bearer wrong-secret'
expect_method_header GET /security/auth/bearer WWW-Authenticate 'Bearer realm="meteorite"'
expect_body 'authorization=[redacted];cookie=[redacted];trace=trace-123;csrf=[redacted]' \
  /security/logging/safe-headers \
  -H 'Authorization: Bearer meteorite-secret' \
  -H 'Cookie: session=abc123' \
  -H 'X-Meteorite-Trace: trace-123' \
  -H 'X-CSRF-Token: csrf-secret'
expect_body observability:log \
  /observability/log \
  -H 'Authorization: Bearer meteorite-secret' \
  -H 'X-Meteorite-Trace: trace-123'
grep -q '"message":"web standards json"' "$LOG"
grep -q '"secret":"\[redacted\]"' "$LOG"
grep -q 'message="web standards plain"' "$LOG"
grep -q 'trace=trace-123' "$LOG"
expect_body observability:timing /observability/server-timing
timing_header="$(header_value /observability/server-timing Server-Timing)"
case "$timing_header" in
  *'handler;dur='*'desc="Lua handler"'*'response;dur=2.500;desc="response write"'*) ;;
  *)
    echo "expected Server-Timing handler/response metrics, got: $timing_header" >&2
    exit 1
    ;;
esac

expect_method_status_body 500 'internal server error' GET /errors/lua-handler
expect_method_header GET /errors/lua-handler X-Meteorite-Error-Boundary route
expect_method_status_body 500 'internal server error' GET /errors/zig-handler
expect_method_header GET /errors/zig-handler X-Meteorite-Error-Boundary route
expect_method_status_body 500 'internal server error' GET /errors/plugin/boom
expect_method_header GET /errors/plugin/boom X-Meteorite-Error-Boundary route

expect_status 401 /middleware/scoped
expect_method_header GET /middleware/scoped X-Meteorite-Middleware short-circuit
expect_body middleware:scoped /middleware/scoped -H 'X-Meteorite-Auth: yes'
expect_body post-header /middleware/post-header
expect_header /middleware/post-header X-Meteorite-Post-Handler mutated

cookie_read="$(curl -fsS -H 'Cookie: session=abc123; theme=dark' http://127.0.0.1:8080/cookies/read)"
if [[ "$cookie_read" != "cookie:abc123" ]]; then
  echo "expected /cookies/read to parse session cookie, got $cookie_read" >&2
  exit 1
fi
expect_body cookie:'quoted value' /cookies/read -H 'Cookie: session="quoted value"'
expect_body cookie:'abc 123' /cookies/read -H 'Cookie: session=abc%20123'
expect_body cookie:missing /cookies/read -H 'Cookie: session=bad%zz'
expect_body cookie:missing /cookies/read -H $'Cookie: session="unterminated'
expect_body cookie:missing /cookies/read -H 'Cookie: session=abc; session=second'
expect_body cookie:set /cookies/set
expect_header /cookies/set Set-Cookie 'session=abc123; Path=/; HttpOnly; SameSite=Lax'
expect_body cookie:helper-lua /cookies/helper-lua
expect_header /cookies/helper-lua Set-Cookie 'session=luahelper; Path=/; Secure; HttpOnly; SameSite=Lax'
expect_body cookie:helper-zig /cookies/helper-zig
expect_header /cookies/helper-zig Set-Cookie 'session=zighelper; Path=/; Secure; HttpOnly; SameSite=Lax'

expect_body 'q=meteorite;page=2;exact=true' '/query/typed?q=meteorite&page=2&exact=true'
expect_body 'q=meteorite;page=;exact=' '/query/typed?q=meteorite'
expect_method_status_body 400 'validation error' GET '/query/typed?page=2'
expect_method_header GET '/query/typed?page=2' X-Meteorite-Validation-Domain query
expect_method_header GET '/query/typed?page=2' X-Meteorite-Validation-Field q
expect_method_header GET '/query/typed?page=2' X-Meteorite-Validation-Reason missing
expect_method_status_body 400 'validation error' GET '/query/typed?q=meteorite&page=NaN'
expect_method_header GET '/query/typed?q=meteorite&page=NaN' X-Meteorite-Validation-Field page
expect_method_header GET '/query/typed?q=meteorite&page=NaN' X-Meteorite-Validation-Reason invalid
expect_method_status_body 400 'validation error' GET '/query/typed?q=meteorite&exact=maybe'
expect_method_header GET '/query/typed?q=meteorite&exact=maybe' X-Meteorite-Validation-Field exact
expect_method_header GET '/query/typed?q=meteorite&exact=maybe' X-Meteorite-Validation-Reason invalid
expect_body 'tag=first' '/query/repeated?tag=first&tag=second'
expect_status 400 '/query/typed?q=%zz'
expect_status 400 '/query/typed?q=bad%0avalue'

expect_method_body validation:contracts POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'csrf=abc_123'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'Cookie: session=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain header -H 'Cookie: session=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field x-meteorite-token -H 'Cookie: session=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason missing -H 'Cookie: session=abc_123'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: bad token!' -H 'Cookie: session=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain header -H 'X-Meteorite-Token: bad token!' -H 'Cookie: session=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: bad token!' -H 'Cookie: session=abc_123'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain cookie -H 'X-Meteorite-Token: abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field session -H 'X-Meteorite-Token: abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason missing -H 'X-Meteorite-Token: abc_123'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=bad token!'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain cookie -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=bad token!'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=bad token!'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: text/plain' --data-binary 'csrf=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain form -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: text/plain' --data-binary 'csrf=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field content-type -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: text/plain' --data-binary 'csrf=abc_123'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: text/plain' --data-binary 'csrf=abc_123'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'csrf=bad token!'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain form -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'csrf=bad token!'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field csrf -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'csrf=bad token!'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'csrf=bad token!'
expect_method_body validation:contracts POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{"email":"dev@meteorite.dev"}'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{bad json'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain json -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{bad json'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field body -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{bad json'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{bad json'
expect_method_status_body 400 'validation error' POST /validation/contracts/123 -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{"email":"not-an-email"}'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Domain json -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{"email":"not-an-email"}'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Field email -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{"email":"not-an-email"}'
expect_method_header POST /validation/contracts/123 X-Meteorite-Validation-Reason invalid -H 'X-Meteorite-Token: abc_123' -H 'Cookie: session=abc_123' -H 'Content-Type: application/json' --data-binary '{"email":"not-an-email"}'

expect_body 'param-lua:123:missing' /params/lua/123
expect_body 'param-zig:123:missing' /params/zig/123
expect_status 404 /params/lua/not-a-number
expect_status 404 /params/zig/not-a-number

expect_method_body body: POST /body/echo
expect_method_body body:abcd POST /body/echo --data-binary abcd
expect_method_status 413 POST /body/echo --data-binary abcde
expect_method_status_body 413 'payload too large' POST /body/echo --data-binary abcde
expect_method_body repeat:xyz:xyz POST /body/repeat-read --data-binary xyz
expect_method_body repeat-zig:xyz:xyz POST /body/repeat-read-zig --data-binary xyz
expect_method_body json:meteorite:123:true POST /body/json -H 'Content-Type: application/json' --data-binary '{"name":"meteorite","n":123,"ok":true}'
expect_method_status_body 400 'invalid json body' POST /body/json -H 'Content-Type: application/json' --data-binary '{bad json'
expect_method_body 'form:Meteorite:Buenos Aires:' POST /body/form -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'name=Meteorite&city=Buenos+Aires&empty='
expect_method_body 'form:Meteorite:São Paulo:' POST /body/form -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' --data-binary 'name=Meteorite&city=S%C3%A3o+Paulo'
expect_method_status_body 400 'invalid form body' POST /body/form -H 'Content-Type: application/x-www-form-urlencoded' --data-binary 'name=%zz'
expect_method_status_body 400 'unsupported form content type' POST /body/form -H 'Content-Type: text/plain' --data-binary 'name=Meteorite'
expect_method_body delete:no-body DELETE /body/no-body
expect_method_status 413 DELETE /body/no-body --data-binary unexpected
expect_method_status_body 413 'payload too large' DELETE /body/no-body --data-binary unexpected

if grep -qi $'\r' <(curl -fsS -D - -o /tmp/meteorite-web-standards-body http://127.0.0.1:8080/headers/table); then
  : # curl preserves CRLF in raw headers; explicit injection checks belong in a negative fixture.
fi

# Hybrid invoke context API parity tests
invoke_query="/tmp/meteorite-web-standards-invoke-query.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json fixtures/apps/web-standards/src/main.lua GET '/query/repeated?tag=pepe&tag=pope' > "$invoke_query"
python3 - "$invoke_query" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["response"]["status"] == 200, result
assert result["response"]["body"] == "tag=pepe", result["response"]
assert result["response"]["content_type"] == "text/plain; charset=utf-8", result["response"]
PY

invoke_param="/tmp/meteorite-web-standards-invoke-param.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json fixtures/apps/web-standards/src/main.lua GET '/params/lua/456' > "$invoke_param"
python3 - "$invoke_param" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["response"]["status"] == 200, result
assert result["response"]["body"] == "param-lua:456:missing", result["response"]
PY

invoke_all="/tmp/meteorite-web-standards-invoke-all.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json fixtures/apps/web-standards/src/main.lua GET '/query/all?tag=a&tag=b&tag=c' > "$invoke_all"
python3 - "$invoke_all" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["response"]["status"] == 200, result
assert result["response"]["body"] == "tags=a,b,c", result["response"]
PY

invoke_decoded="/tmp/meteorite-web-standards-invoke-decoded.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json fixtures/apps/web-standards/src/main.lua GET '/query/decoded?q=hello%20world' > "$invoke_decoded"
python3 - "$invoke_decoded" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["response"]["status"] == 200, result
assert result["response"]["body"] == "q=hello world", result["response"]
PY

invoke_string="/tmp/meteorite-web-standards-invoke-string.json"
LUA_PATH='src/?.lua;src/?/init.lua;fixtures/apps/web-standards/src/?.lua;;' ./.moonstone/env/bin/lua src/cli/main.lua invoke --json fixtures/apps/web-standards/src/main.lua DELETE '/body/no-body' > "$invoke_string"
python3 - "$invoke_string" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["response"]["status"] == 200, result
assert result["response"]["body"] == "delete:no-body", result["response"]
assert result["response"]["content_type"] == "text/plain; charset=utf-8", result["response"]
PY

echo "web standards fixture: ok"
