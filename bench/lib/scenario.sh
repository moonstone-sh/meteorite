#!/usr/bin/env bash
set -euo pipefail

expected_body_for_scenario() {
  local name="$1"
  case "$name" in
  work-cpu-50us) printf 'work:cpu:50us:50' ;;
  work-cpu-100us) printf 'work:cpu:100us:100' ;;
  work-cpu-250us) printf 'work:cpu:250us:250' ;;
  work-cpu-500us) printf 'work:cpu:500us:500' ;;
  work-cpu-1ms) printf 'work:cpu:1ms:1000' ;;
  work-cpu-2ms) printf 'work:cpu:2ms:2000' ;;
  work-cpu-5ms) printf 'work:cpu:5ms:5000' ;;
  work-sleep-1ms) printf 'sleep:1ms' ;;
  work-sleep-5ms) printf 'sleep:5ms' ;;
  work-sleep-10ms) printf 'sleep:10ms' ;;
  app-json-encode-small) printf 'json:encode-small:meteorite:123:true' ;;
  app-json-decode-1kb) printf 'json:decode-1kb:meteorite:123:xxxxxxxx' ;;
  app-json-roundtrip-1kb) printf 'json:roundtrip-1kb:meteorite:123:1024' ;;
  app-template-hello) printf 'template:hello:Hello Meteorite!' ;;
  app-template-list-100) printf 'template:list-100:1192:1:item-001' ;;
  app-sqlite-select-one) printf 'sqlite:select-one:item-042:420' ;;
  app-sqlite-select-100) printf 'sqlite:select-100:100' ;;
  app-sqlite-insert-small) printf 'sqlite:insert-small:1' ;;
  app-pipeline-cors) printf 'pipeline:cors:ok' ;;
  app-pipeline-cors-json-template) printf 'pipeline:cors-json-template:cors-json-template' ;;
  app-full-sqlite-json-template) printf 'full:sqlite-json-template:item-007:70' ;;
  plain_text | plain_text_hybrid | zig-static | lua-return-string | lua-text-direct | lua-response-table) printf 'ok' ;;
  typed_param | typed_param_hybrid | lua-direct-param | lua-ctx-param | lua-req-table) printf '123' ;;
  echo_small | echo_small_hybrid | lua-body-1k) printf '%s' "$BENCH_POST_BODY" ;;
  lua-empty) printf '' ;;
  lua-json-small) printf '{"ok":true}' ;;
  lua-state-counter) printf '1' ;;
  lua-sleep-1s) printf 'slept' ;;
  lua-echo-param) printf 'alpha' ;;
  lua-echo-body) printf '%s' "$BENCH_POST_BODY" ;;
  lua-loop-0) printf '0' ;;
  lua-loop-10) printf '55' ;;
  lua-loop-100) printf '5050' ;;
  lua-loop-1000) printf '500500' ;;
  lua-loop-10000) printf '50005000' ;;
  lua-loop-100000) printf '5000050000' ;;
  *) printf 'ok' ;;
  esac
}


expected_content_type_for_scenario() {
  local name="$1"
  case "$name" in
  typed_param | typed_param_hybrid) printf 'application/json' ;;
  *) printf 'text/plain' ;;
  esac
}


tier_for_scenario() {
  local name="$1"
  case "$name" in
  work-cpu-*) printf 'work-cpu' ;;
  work-sleep-*) printf 'work-sleep' ;;
  app-*) printf 'lua-app' ;;
  zig-static) printf 'native' ;;
  plain_text | typed_param | echo_small) printf 'native' ;;
  plain_text_hybrid | typed_param_hybrid | echo_small_hybrid) printf 'lua-direct-response' ;;
  lua-empty) printf 'lua-empty' ;;
  lua-return-string) printf 'lua-string-return' ;;
  lua-text-direct) printf 'lua-direct-response' ;;
  lua-response-table) printf 'lua-response-table' ;;
  lua-direct-param) printf 'lua-direct-param' ;;
  lua-ctx-param) printf 'lua-lazy-context' ;;
  lua-req-table) printf 'lua-full-req' ;;
  lua-body-1k) printf 'lua-body' ;;
  lua-json-small) printf 'lua-json' ;;
  lua-loop-*) printf 'lua-compute' ;;
  lua-sleep-1s) printf 'lua-proof-slow' ;;
  lua-state-counter | lua-echo-param | lua-echo-body) printf 'lua-dynamic' ;;
  *) printf 'external' ;;
  esac
}


validation_for_scenario() {
  local name="$1" tier="$2"
  case "$name" in
  lua-sleep-1s) printf 'pcall_at_least,latency_floor' ;;
  *)
    case "$tier" in
    native) printf 'native_no_lua' ;;
    external) printf 'not_applicable' ;;
    *) printf 'pcall_exact' ;;
    esac
    ;;
  esac
}


compare_for_scenario() {
  case "$1" in
  lua-sleep-1s | lua-state-counter | lua-echo-param | lua-echo-body) printf '0' ;;
  *) printf '1' ;;
  esac
}


latency_floor_us_for_scenario() {
  case "$1" in
  lua-sleep-1s) printf '900000' ;;
  *) printf '0' ;;
  esac
}


service_time_seconds_for_scenario() {
  case "$1" in
  work-cpu-50us) printf '0.000050' ;;
  work-cpu-100us) printf '0.000100' ;;
  work-cpu-250us) printf '0.000250' ;;
  work-cpu-500us) printf '0.000500' ;;
  work-cpu-1ms | work-sleep-1ms) printf '0.001000' ;;
  work-cpu-2ms) printf '0.002000' ;;
  work-cpu-5ms | work-sleep-5ms) printf '0.005000' ;;
  work-sleep-10ms) printf '0.010000' ;;
  *) printf '0' ;;
  esac
}


is_lua_bench_scenario() {
  case "$1" in lua-*) return 0 ;; *) return 1 ;; esac
}


