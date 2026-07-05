#!/usr/bin/env bash
set -euo pipefail

verify_fixture_info() {
  local label="$1"
  local info
  info="$(curl -fsS "http://$HOST:$PORT/__bench/fixture-info" 2>/dev/null)" || {
    echo "error: $label missing /__bench/fixture-info" >&2
    return 1
  }
  printf '%s' "$info" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data.get("fixture") == "bench-service"; assert data.get("entry") == "fixtures/apps/bench-service/src/main.lua"; routes=data.get("routes", {}); required=["zig-static","lua-return-string","lua-text-direct","lua-direct-param"]; missing=[r for r in required if r not in routes]; assert not missing, missing' || {
    echo "error: $label fixture-info is not the bench-service fixture" >&2
    return 1
  }
}


verify_meteorite_workers() {
  local label="$1"
  local expected_workers="$2"
  local meta
  meta="$(curl -fsS "http://$HOST:$PORT/__bench/meta" 2>/dev/null)" || {
    echo "error: $label missing /__bench/meta worker metadata" >&2
    return 1
  }

  printf '%s' "$meta" | python3 -c '
import json, sys
import os
label = sys.argv[1]
expected = int(sys.argv[2])
data = json.load(sys.stdin)
configured = int(data.get("fast_http_workers", -1))
workers = int(data.get("worker_count", 0))
host_cpus = os.cpu_count() or 1
if configured != expected:
    raise SystemExit(f"{label} configured fast_http_workers={configured}, expected {expected}")
if expected == 1 and workers != 1:
    raise SystemExit(f"{label} runtime worker_count={workers}, expected exactly 1")
if expected == 0 and host_cpus > 1 and workers <= 1:
    raise SystemExit(f"{label} runtime worker_count={workers}, host_cpus={host_cpus}, expected auto > 1")
print(f"  OK      worker config fast_http_workers={configured} runtime_workers={workers} host_cpus={host_cpus}")
' "$label" "$expected_workers" || {
    echo "Preflight failed for $label. Refusing to benchmark invalid worker configuration."
    return 1
  }
}


hono_process_count() {
  local root_pid="$1"
  get_descendants "$root_pid" | wc -l | tr -d '[:space:]'
}


verify_hono_workers() {
  local label="$1"
  local expected_mode="$2"
  local meta process_count
  meta="$(curl -fsS "http://$HOST:$PORT/__bench/meta" 2>/dev/null)" || {
    echo "error: $label missing /__bench/meta" >&2
    return 1
  }
  process_count="$(hono_process_count "$SERVER_PID")"

  printf '%s' "$meta" | python3 -c '
import json, sys
label = sys.argv[1]
expected = sys.argv[2]
process_count = int(sys.argv[3])
data = json.load(sys.stdin)
mode = data.get("mode", "")
reuse_port = bool(data.get("reuse_port", False))
if expected == "single":
    if mode != "single-process":
        raise SystemExit(f"{label} meta mode={mode}, expected single-process")
    if reuse_port:
        raise SystemExit(f"{label} single-process must not use reuse_port")
    if process_count != 1:
        raise SystemExit(f"{label} process_count={process_count}, expected exactly 1")
else:
    if mode != "multiprocess-worker":
        raise SystemExit(f"{label} meta mode={mode}, expected multiprocess-worker")
    if process_count <= 1:
        raise SystemExit(f"{label} process_count={process_count}, expected >1")
print(f"  OK      Hono mode={mode} reuse_port={reuse_port} processes={process_count}")
' "$label" "$expected_mode" "$process_count" || {
    echo "Preflight failed for $label. Refusing to benchmark invalid Hono process mode."
    return 1
  }
}


record_go_fiber_environment() {
  local file="$OUT/go-fiber-fasthttp.env"
  {
    printf 'go_version=%s\n' "$(go version 2>/dev/null || printf 'unknown')"
    printf 'gomaxprocs_env=%s\n' "${GOMAXPROCS:-}"
    printf 'ulimit_n=%s\n' "$(ulimit -n 2>/dev/null || printf 'unknown')"
    printf 'sysctl_kern_ipc_somaxconn=%s\n' "$(sysctl -n kern.ipc.somaxconn 2>/dev/null || printf 'unknown')"
    printf 'build_command=%s\n' 'go build -trimpath -ldflags=-s -w -o $OUT/go-fiber-server .'
    printf 'run_command=%s\n' '$OUT/go-fiber-server --port=$PORT'
  } >"$file"
}


verify_go_fiber() {
  local meta process_cmd process_count
  meta="$(curl -fsS "http://$HOST:$PORT/__bench/meta" 2>/dev/null)" || {
    echo "error: go-fiber-fasthttp missing /__bench/meta" >&2
    return 1
  }
  process_cmd="$(ps -p "$SERVER_PID" -o command= 2>/dev/null || true)"
  process_count="$(hono_process_count "$SERVER_PID")"
  printf '%s' "$meta" | python3 -c '
import json, os, sys
cmd = sys.argv[1]
process_count = int(sys.argv[2])
data = json.load(sys.stdin)
host_cpus = os.cpu_count() or 1
checks = {
    "framework": data.get("framework") == "go-fiber",
    "backend": data.get("backend") == "fasthttp",
    "prefork": data.get("prefork") is True,
    "keep_alive": data.get("keep_alive") is True,
    "logging_middleware": data.get("logging_middleware") is False,
    "recovery_middleware": data.get("recovery_middleware") is False,
    "build": data.get("build") == "go-build-release-trimpath-s-w",
    "not_go_run": "go run" not in cmd,
}
if host_cpus > 1:
    checks["prefork_processes"] = process_count > 1
bad = [k for k, ok in checks.items() if not ok]
if bad:
    raise SystemExit("failed checks: " + ",".join(bad))
prefork = data.get("prefork")
gomaxprocs = data.get("gomaxprocs")
print(f"  OK      Fiber meta prefork={prefork} gomaxprocs={gomaxprocs} processes={process_count} no_logging no_recovery release_binary")
' "$process_cmd" "$process_count" || {
    echo "Preflight failed for go-fiber-fasthttp. Refusing to benchmark invalid Fiber setup."
    return 1
  }
  {
    printf 'process_count=%s\n' "$process_count"
    printf 'meta_json=%s\n' "$meta"
  } >"$OUT/go-fiber-fasthttp.runtime.env"
}


assert_bench_graph() {
  local routes_file=".meteorite/graph/bench/routes.zon"
  local missing=0
  for route in \
    '/__bench/plain' \
    '/__bench/hybrid-inline' \
    '/users/:id' \
    '/echo' \
    '/__bench/zig-static' \
    '/__bench/lua-return-string' \
    '/__bench/lua-text-direct' \
    '/__bench/lua-direct-param/:id' \
    '/__bench/lua-loop-10000' \
    '/__bench/lua-loop-100000' \
    '/__bench/lua-sleep-1s'; do
    if ! grep -Fq "$route" "$routes_file" 2>/dev/null; then
      echo "error: bench graph missing route $route in $routes_file" >&2
      missing=1
    fi
  done
  if [[ "$missing" != "0" ]]; then
    return 1
  fi
  echo "Verified bench graph routes from fixtures/apps/bench-service/src/main.lua"
}


assert_scenario_response() {
  local name="$1" method="$2" path="$3" label="$4"
  local url="http://$HOST:$PORT$path"
  local expected actual
  expected="$(expected_body_for_scenario "$name")"

  if [[ "$method" == "POST" ]]; then
    actual="$(curl -fsS -X POST --data-binary "$BENCH_POST_BODY" "$url")" || {
      echo "error: $label $name preflight failed: $method $path did not return 2xx" >&2
      return 1
    }
  else
    actual="$(curl -fsS "$url")" || {
      echo "error: $label $name preflight failed: $method $path did not return 2xx" >&2
      return 1
    }
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "error: $label $name preflight body mismatch for $method $path" >&2
    echo "  expected bytes: ${#expected}" >&2
    echo "  actual bytes:   ${#actual}" >&2
    return 1
  fi
}


assert_scenario_content_type() {
  local name="$1" method="$2" path="$3" label="$4"
  local url="http://$HOST:$PORT$path"
  local expected actual
  expected="$(expected_content_type_for_scenario "$name")"

  if [[ "$method" == "POST" ]]; then
    actual="$(curl -fsS -o /tmp/meteorite-preflight-ct-body -w '%{content_type}' -X POST --data-binary "$BENCH_POST_BODY" "$url")" || return 1
  else
    actual="$(curl -fsS -o /tmp/meteorite-preflight-ct-body -w '%{content_type}' "$url")" || return 1
  fi

  local actual_lc expected_lc
  actual_lc="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"
  expected_lc="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  if [[ "$actual_lc" == "$expected_lc"* ]]; then
    return 0
  else
    echo "error: $label $name content-type mismatch for $method $path: expected prefix '$expected', actual '$actual'" >&2
    return 1
  fi
}


scenario_lines_for_variant() {
  local label="$1"
  printf '%s\n' "${SCENARIOS[@]}"
  if [[ "$MODE" == "--mode=public" && "$label" == meteorite-* ]]; then
    printf '%s\n' "${METEORITE_ONLY_SCENARIOS[@]}"
  fi
}


preflight_variant() {
  local label="$1"
  local variant_scenarios=()
  echo "Preflighting $label routes..."
  if [[ "$label" == meteorite-* ]]; then
    verify_fixture_info "$label" || {
      echo "Preflight failed for $label. Refusing to benchmark invalid fixture."
      return 1
    }
    echo "  OK      GET  /__bench/fixture-info -> 200"
    case "$label" in
    meteorite-1worker) verify_meteorite_workers "$label" 1 || return 1 ;;
    meteorite-auto) verify_meteorite_workers "$label" 0 || return 1 ;;
    esac
  fi
  case "$label" in
  hono-bun-single) verify_hono_workers "$label" single || return 1 ;;
  hono-bun-multiprocess) verify_hono_workers "$label" multiprocess || return 1 ;;
  go-fiber-fasthttp) verify_go_fiber || return 1 ;;
  esac

  variant_scenarios=()
  while IFS= read -r scenario_line; do
    [[ -n "$scenario_line" ]] && variant_scenarios+=("$scenario_line")
  done < <(scenario_lines_for_variant "$label")
  for scenario in "${variant_scenarios[@]}"; do
    IFS='|' read -r name method path <<<"$scenario"
    local status
    if [[ "$method" == "POST" ]]; then
      status="$(curl -sS -o /tmp/meteorite-preflight-body -w '%{http_code}' -X POST --data-binary "$BENCH_POST_BODY" "http://$HOST:$PORT$path" 2>/dev/null)" || status="000"
    else
      status="$(curl -sS -o /tmp/meteorite-preflight-body -w '%{http_code}' "http://$HOST:$PORT$path" 2>/dev/null)" || status="000"
    fi
    if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
      printf '  INVALID %-4s %s -> %s\n' "$method" "$path" "$status"
      echo "Preflight failed for $label. Refusing to benchmark invalid route."
      return 1
    fi
    if ! assert_scenario_response "$name" "$method" "$path" "$label"; then
      printf '  INVALID %-4s %s -> bad-body\n' "$method" "$path"
      echo "Preflight failed for $label. Refusing to benchmark invalid body."
      return 1
    fi
    if [[ "$label" == "go-fiber-fasthttp" ]] && ! assert_scenario_content_type "$name" "$method" "$path" "$label"; then
      printf '  INVALID %-4s %s -> bad-content-type\n' "$method" "$path"
      echo "Preflight failed for $label. Refusing to benchmark invalid content type."
      return 1
    fi
    printf '  OK      %-4s %s -> %s\n' "$method" "$path" "$status"
  done

  if [[ "$MODE" == "--mode=lua-bridge" || "$MODE" == "--mode=lua-bridge-smoke" ]]; then
    local a b g
    a="$(curl -fsS "http://$HOST:$PORT/__bench/lua-echo-param/alpha")"
    b="$(curl -fsS "http://$HOST:$PORT/__bench/lua-echo-param/beta")"
    g="$(curl -fsS "http://$HOST:$PORT/__bench/lua-echo-param/gamma")"
    if [[ "$a" != alpha || "$b" != beta || "$g" != gamma ]]; then
      echo "Preflight failed for $label. Dynamic Lua echo proof failed."
      return 1
    fi
    echo "  OK      dynamic lua echo proof alpha/beta/gamma"

    local c1 c2 c3
    c1="$(curl -fsS "http://$HOST:$PORT/__bench/lua-state-counter")"
    c2="$(curl -fsS "http://$HOST:$PORT/__bench/lua-state-counter")"
    c3="$(curl -fsS "http://$HOST:$PORT/__bench/lua-state-counter")"
    if [[ "$label" == "meteorite-1worker" ]]; then
      if [[ "$c1" != "1" || "$c2" != "2" || "$c3" != "3" ]]; then
        echo "Preflight failed for $label. Single-worker Lua state counter expected 1/2/3, got $c1/$c2/$c3."
        return 1
      fi
    elif [[ ! "$c1$c2$c3" =~ ^[0-9]+$ ]]; then
      echo "Preflight failed for $label. Lua state counter returned non-numeric values $c1/$c2/$c3."
      return 1
    fi
    echo "  OK      lua state counter proof $c1/$c2/$c3"

    local sleep_start_ns sleep_end_ns sleep_elapsed_ms sleep_body
    sleep_start_ns="$(now_ns)"
    sleep_body="$(curl -fsS --max-time 3 "http://$HOST:$PORT/__bench/lua-sleep-1s")" || {
      echo "Preflight failed for $label. Slow Lua sleep proof route failed."
      return 1
    }
    sleep_end_ns="$(now_ns)"
    sleep_elapsed_ms=$(((sleep_end_ns - sleep_start_ns) / 1000000))
    if [[ "$sleep_body" != "slept" || "$sleep_elapsed_ms" -lt 800 ]]; then
      echo "Preflight failed for $label. Slow Lua proof expected body=slept and >=800ms, got body=$sleep_body elapsed=${sleep_elapsed_ms}ms."
      return 1
    fi
    echo "  OK      slow lua sleep proof ${sleep_elapsed_ms}ms"
  fi
}


