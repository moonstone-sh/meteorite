#!/usr/bin/env bash
set -euo pipefail

run_scenario() {
  check_interrupted

  local name="$1" method="$2" path="$3" label="$4" c="$5" rep="$6"
  local tier validation_modes compare proof_only latency_floor_us
  tier="$(tier_for_scenario "$name")"
  validation_modes="$(validation_for_scenario "$name" "$tier")"
  if [[ "$label" != meteorite-* ]]; then
    validation_modes="not_applicable"
  fi
  compare="$(compare_for_scenario "$name")"
  proof_only=0
  if [[ "$compare" == "0" ]]; then proof_only=1; fi
  latency_floor_us="$(latency_floor_us_for_scenario "$name")"
  local url="http://$HOST:$PORT$path"
  local raw_ext="out"
  if [[ "$LOADGEN" == "oha" ]]; then raw_ext="json"; fi
  local out_file="$RAW_DIR/${label}__${name}__c${c}__r${rep}__${LOADGEN_LABEL}.${raw_ext}"
  local meta_file="$META_DIR/${label}__${name}__c${c}__r${rep}__${LOADGEN_LABEL}.meta"
  local lg_stats="$OUT/loadgen-${label}-${name}-c${c}-rep${rep}.log"
  local fd_stats="$OUT/fd-${label}-${name}-c${c}-rep${rep}.log"

  if [[ "$RESUME" == "1" && -f "$meta_file" && -f "$out_file" ]]; then
    local prior_invalid prior_exit prior_requests prior_p99
    prior_invalid="$(awk -F= '$1 == "invalid_reason" { value = substr($0, index($0, "=") + 1) } END { print value }' "$meta_file" 2>/dev/null)"
    prior_exit="$(awk -F= '$1 == "loadgen_exit_code" || $1 == "wrk_exit_code" { value = $2 } END { print value }' "$meta_file" 2>/dev/null)"
    prior_requests="$(awk -F= '$1 == "requests_completed" || $1 == "requests" { value = $2 } END { print value }' "$meta_file" 2>/dev/null)"
    prior_p99="$(awk -F= '$1 == "p99_us" { value = $2 } END { print value }' "$meta_file" 2>/dev/null)"
    prior_exit="${prior_exit:-0}"
    prior_requests="${prior_requests:-0}"
    prior_p99="${prior_p99:-0}"
    if [[ -z "$prior_invalid" && "$prior_exit" == "0" ]] && python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) > 0 and float(sys.argv[2]) > 0 else 1)' "$prior_requests" "$prior_p99"; then
      printf "  %-22s c=%-4s rep=%-2s SKIP existing-valid loadgen=%s\n" "$name" "$c" "$rep" "$LOADGEN_LABEL"
      return 0
    fi
  fi

  local active_threads=$THREADS
  if ((c < active_threads)); then
    active_threads=$c
  fi

  : >"$meta_file"

  echo "label=$label" >>"$meta_file"
  echo "loadgen=$LOADGEN_LABEL" >>"$meta_file"
  echo "loadgen_base=$LOADGEN" >>"$meta_file"
  echo "latency_correction=$OHA_LATENCY_CORRECTION" >>"$meta_file"
  echo "loadgen_version=$(loadgen_version)" >>"$meta_file"
  echo "loadgen_raw_file=$out_file" >>"$meta_file"
  echo "scenario=$name" >>"$meta_file"
  echo "tier=$tier" >>"$meta_file"
  echo "validation=$validation_modes" >>"$meta_file"
  echo "compare=$compare" >>"$meta_file"
  echo "proof_only=$proof_only" >>"$meta_file"
  echo "latency_floor_us=$latency_floor_us" >>"$meta_file"
  echo "concurrency=$c" >>"$meta_file"
  echo "configured_connections=$c" >>"$meta_file"
  echo "rep=$rep" >>"$meta_file"
  echo "method=$method" >>"$meta_file"
  echo "path=$path" >>"$meta_file"
  echo "threads=$active_threads" >>"$meta_file"
  echo "configured_threads=$active_threads" >>"$meta_file"
  echo "duration=$DURATION" >>"$meta_file"
  echo "warmup=$WARMUP" >>"$meta_file"
  echo "target_qps=${TARGET_QPS:-}" >>"$meta_file"
  echo "configured_service_time_seconds=$(service_time_seconds_for_scenario "$name")" >>"$meta_file"
  local env_soft_nofile env_hard_nofile env_somaxconn env_max_c env_fd_ok env_backlog_ok env_ephemeral_ok env_suspicious env_invalid_reason
  env_soft_nofile="$(system_env_field soft_nofile)"
  env_hard_nofile="$(system_env_field hard_nofile)"
  env_somaxconn="$(system_env_field somaxconn)"
  env_max_c="$(system_env_field max_concurrency_requested)"
  env_fd_ok="$(system_env_field fd_limit_ok)"
  env_backlog_ok="$(system_env_field backlog_ok)"
  env_ephemeral_ok="$(system_env_field ephemeral_ports_ok)"
  env_suspicious="$(system_env_field environment_suspicious)"
  env_invalid_reason="$(system_env_field environment_invalid_reason)"
  local row_required_min row_soft_num row_somax_num row_ephemeral_count row_reason
  row_required_min=$((c + 256))
  row_soft_num="$(num_or_zero "$env_soft_nofile")"
  row_somax_num="$(num_or_zero "$env_somaxconn")"
  row_ephemeral_count="$(num_or_zero "$(system_env_field ephemeral_port_count)")"
  env_fd_ok=true
  env_backlog_ok=true
  env_ephemeral_ok=true
  env_suspicious=false
  row_reason=""
  if ((row_soft_num > 0 && row_soft_num < row_required_min)); then
    env_fd_ok=false
    env_suspicious=true
    row_reason="${row_reason:+$row_reason,}soft_nofile_${env_soft_nofile}_below_required_${row_required_min}"
  fi
  if [[ "$env_somaxconn" != "not_available" && "$row_somax_num" -gt 0 && "$row_somax_num" -lt "$c" ]]; then
    env_backlog_ok=false
    env_suspicious=true
    row_reason="${row_reason:+$row_reason,}somaxconn_${env_somaxconn}_below_requested_${c}"
  fi
  if ((row_ephemeral_count > 0 && row_ephemeral_count < c * 2)); then
    env_ephemeral_ok=false
    env_suspicious=true
    row_reason="${row_reason:+$row_reason,}ephemeral_ports_${row_ephemeral_count}_below_required_$((c * 2))"
  fi
  if [[ -n "$row_reason" ]]; then
    env_invalid_reason="$row_reason"
  else
    env_invalid_reason="none"
  fi
  echo "soft_nofile=$env_soft_nofile" >>"$meta_file"
  echo "hard_nofile=$env_hard_nofile" >>"$meta_file"
  echo "somaxconn=$env_somaxconn" >>"$meta_file"
  echo "max_concurrency_requested=$env_max_c" >>"$meta_file"
  echo "fd_limit_ok=$env_fd_ok" >>"$meta_file"
  echo "backlog_ok=$env_backlog_ok" >>"$meta_file"
  echo "ephemeral_ports_ok=$env_ephemeral_ok" >>"$meta_file"
  echo "environment_suspicious=$env_suspicious" >>"$meta_file"
  echo "environment_invalid_reason=$env_invalid_reason" >>"$meta_file"
  echo "loadgen_threads=$active_threads" >>"$meta_file"
  echo "loadgen_concurrency=$c" >>"$meta_file"
  echo "loadgen_version=$(loadgen_version_safe "$LOADGEN")" >>"$meta_file"
  if [[ "$label" == "go-fiber-fasthttp" && -f "$OUT/go-fiber-fasthttp.env" ]]; then
    sed 's/^/go_fiber_/' "$OUT/go-fiber-fasthttp.env" >>"$meta_file"
  fi
  if [[ "$label" == "go-fiber-fasthttp" && -f "$OUT/go-fiber-fasthttp.runtime.env" ]]; then
    sed 's/^/go_fiber_/' "$OUT/go-fiber-fasthttp.runtime.env" >>"$meta_file"
  fi

  # Make sure the server is alive before warmup.
  if ! curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
    echo "server_alive_before=0" >>"$meta_file"
    printf "  %-22s c=%-4s rep=%-2s INVALID server-not-alive-before\n" "$name" "$c" "$rep"
    return 0
  fi

  echo "server_alive_before=1" >>"$meta_file"
  local server_fd_count_before server_fd_count_after loadgen_fd_count_before loadgen_fd_count_after server_fd_count_max loadgen_fd_count_max fd_usage_high fd_usage_critical soft_nofile_num
  server_fd_count_before="$(fd_count_for_pid "$SERVER_PID")"
  echo "server_fd_count_before=$server_fd_count_before" >>"$meta_file"

  if ! assert_scenario_response "$name" "$method" "$path" "$label"; then
    echo "preflight_ok=0" >>"$meta_file"
    printf "  %-22s c=%-4s rep=%-2s INVALID preflight-response\n" "$name" "$c" "$rep"
    return 0
  fi
  echo "preflight_ok=1" >>"$meta_file"

  # Warmup. Do not let a transient load-generator failure kill the whole suite.
  local warmup_ec=0
  if [[ "$WARMUP" != "0" ]]; then
    set +e
    run_loadgen_once "$method" "$url" "$c" "$active_threads" "$WARMUP" "/tmp/meteorite-${LOADGEN_LABEL}-warmup-${label}-${name}.out" "" >/dev/null 2>&1
    warmup_ec=$?
    set -e
  fi

  echo "warmup_exit_code=$warmup_ec" >>"$meta_file"

  local stats_supported=0 lua_before=0 native_before=0 active_probe_supported=0
  if [[ "$label" == meteorite-* ]] && reset_bench_stats; then
    active_probe_supported=1
    if [[ "$MODE" == "--mode=lua-bridge" || "$MODE" == "--mode=lua-bridge-smoke" || "$tier" == lua-* ]]; then
      stats_supported=1
    fi
    lua_before="$(stats_field "$name" lua_pcalls || printf '0')"
    native_before="$(stats_field "$name" native_calls || printf '0')"
  fi
  echo "active_probe_supported=$active_probe_supported" >>"$meta_file"
  echo "lua_pcalls_before=$lua_before" >>"$meta_file"
  echo "native_calls_before=$native_before" >>"$meta_file"

  sleep 2

  local accepted_before=0 completed_before=0 inflight_before=0 queue_before=0
  if [[ "$active_probe_supported" == "1" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
      accepted_total) accepted_before="$value" ;;
      completed_total) completed_before="$value" ;;
      inflight_current) inflight_before="$value" ;;
      queue_depth_current) queue_before="$value" ;;
      esac
    done < <(bench_meta_fields accepted_total completed_total inflight_current queue_depth_current)
  fi
  echo "accepted_total_before=$accepted_before" >>"$meta_file"
  echo "completed_total_before=$completed_before" >>"$meta_file"
  echo "inflight_current_before=$inflight_before" >>"$meta_file"
  echo "queue_depth_current_before=$queue_before" >>"$meta_file"

  # Run.
  set +e
  run_loadgen_once "$method" "$url" "$c" "$active_threads" "$DURATION" "$out_file" "latency" &

  LOADGEN_PID=$!
  register_pid "$LOADGEN_PID"
  sleep 0.2
  loadgen_fd_count_before="$(fd_count_for_pid "$LOADGEN_PID")"
  start_stats_tracker "$LOADGEN_PID" "$lg_stats"
  start_fd_tracker "$SERVER_PID" "$LOADGEN_PID" "$fd_stats"
  wait "$LOADGEN_PID"
  local loadgen_ec=$?
  loadgen_fd_count_after="$(fd_count_for_pid "$LOADGEN_PID")"
  unregister_pid "$LOADGEN_PID"
  LOADGEN_PID=""
  set -e
  server_fd_count_after="$(fd_count_for_pid "$SERVER_PID")"
  server_fd_count_max="$server_fd_count_before"
  if [[ "$server_fd_count_after" =~ ^[0-9]+$ && "$server_fd_count_after" -gt "$server_fd_count_max" ]]; then server_fd_count_max="$server_fd_count_after"; fi
  local server_fd_sample_max loadgen_fd_sample_max
  server_fd_sample_max="$(max_fd_from_log "$fd_stats" 1)"
  if [[ "$server_fd_sample_max" =~ ^[0-9]+$ && "$server_fd_sample_max" -gt "$server_fd_count_max" ]]; then server_fd_count_max="$server_fd_sample_max"; fi
  loadgen_fd_count_max="$loadgen_fd_count_before"
  if [[ "$loadgen_fd_count_after" =~ ^[0-9]+$ && "$loadgen_fd_count_after" -gt "$loadgen_fd_count_max" ]]; then loadgen_fd_count_max="$loadgen_fd_count_after"; fi
  loadgen_fd_sample_max="$(max_fd_from_log "$fd_stats" 2)"
  if [[ "$loadgen_fd_sample_max" =~ ^[0-9]+$ && "$loadgen_fd_sample_max" -gt "$loadgen_fd_count_max" ]]; then loadgen_fd_count_max="$loadgen_fd_sample_max"; fi
  soft_nofile_num="$(num_or_zero "$env_soft_nofile")"
  fd_usage_high=false
  fd_usage_critical=false
  if ((soft_nofile_num > 0)); then
    if ((server_fd_count_max * 100 > soft_nofile_num * 80 || loadgen_fd_count_max * 100 > soft_nofile_num * 80)); then fd_usage_high=true; fi
    if ((server_fd_count_max * 100 > soft_nofile_num * 95 || loadgen_fd_count_max * 100 > soft_nofile_num * 95)); then fd_usage_critical=true; fi
  fi

  echo "wrk_exit_code=$loadgen_ec" >>"$meta_file"
  echo "loadgen_exit_code=$loadgen_ec" >>"$meta_file"
  echo "server_fd_count_after=$server_fd_count_after" >>"$meta_file"
  echo "server_fd_count_max=$server_fd_count_max" >>"$meta_file"
  echo "loadgen_fd_count_before=$loadgen_fd_count_before" >>"$meta_file"
  echo "loadgen_fd_count_after=$loadgen_fd_count_after" >>"$meta_file"
  echo "loadgen_fd_count_max=$loadgen_fd_count_max" >>"$meta_file"
  echo "fd_usage_high=$fd_usage_high" >>"$meta_file"
  echo "fd_usage_critical=$fd_usage_critical" >>"$meta_file"

  sleep 1

  if curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; then
    echo "server_alive_after=1" >>"$meta_file"
  else
    echo "server_alive_after=0" >>"$meta_file"
  fi

  local accepted_after=0 completed_after=0 open_connections_max=0 inflight_after=0 inflight_max=0 queue_after=0 queue_max=0 worker_queue_max=0 budget_capacity=0 budget_rejections=0 backpressure_total=0
  if [[ "$active_probe_supported" == "1" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
      accepted_total) accepted_after="$value" ;;
      completed_total) completed_after="$value" ;;
      open_connections_max) open_connections_max="$value" ;;
      inflight_current) inflight_after="$value" ;;
      inflight_max) inflight_max="$value" ;;
      queue_depth_current) queue_after="$value" ;;
      queue_depth_max) queue_max="$value" ;;
      worker_queue_depth_max) worker_queue_max="$value" ;;
      budget_capacity) budget_capacity="$value" ;;
      budget_rejections_total) budget_rejections="$value" ;;
      backpressure_total) backpressure_total="$value" ;;
      esac
    done < <(bench_meta_fields accepted_total completed_total open_connections_max inflight_current inflight_max queue_depth_current queue_depth_max worker_queue_depth_max budget_capacity budget_rejections_total backpressure_total)
  fi
  local accepted_delta completed_delta
  accepted_delta=$(python3 -c 'import sys; print(max(0, int(float(sys.argv[2])) - int(float(sys.argv[1]))))' "$accepted_before" "$accepted_after")
  completed_delta=$(python3 -c 'import sys; print(max(0, int(float(sys.argv[2])) - int(float(sys.argv[1]))))' "$completed_before" "$completed_after")

  local rps p50 p99 p50_us p75_us p90_us p99_us latency_avg_us latency_stdev_us latency_max_us requests socket_errors non2xx lg_cpu invalid_reason lua_after native_after lua_delta native_delta lua_per_request

  if [[ "$LOADGEN" == "wrk" ]]; then
    rps=$(awk '/^Requests\/sec:/ { print $2; exit }' "$out_file" 2>/dev/null)
    rps="${rps:-0}"
    requests=$(awk '/ requests in / { print $1; exit }' "$out_file" 2>/dev/null)
    requests="${requests:-0}"
    p50=$(awk '/Latency Distribution/ { in_dist=1; next } in_dist && $1 == "50%" { print $2; exit }' "$out_file" 2>/dev/null)
    p50="${p50:-0}"
    p50_us="$(latency_to_us "$p50")"
    p75=$(awk '/Latency Distribution/ { in_dist=1; next } in_dist && $1 == "75%" { print $2; exit }' "$out_file" 2>/dev/null)
    p75_us="$(latency_to_us "${p75:-0}")"
    p90=$(awk '/Latency Distribution/ { in_dist=1; next } in_dist && $1 == "90%" { print $2; exit }' "$out_file" 2>/dev/null)
    p90_us="$(latency_to_us "${p90:-0}")"
    p99=$(awk '/Latency Distribution/ { in_dist=1; next } in_dist && $1 == "99%" { print $2; exit }' "$out_file" 2>/dev/null)
    p99="${p99:-0}"
    p99_us="$(latency_to_us "$p99")"
    latency_avg_raw="$(awk '/^[[:space:]]*Latency[[:space:]]/ { print $2; exit }' "$out_file" 2>/dev/null)"
    latency_avg_us="$(latency_to_us "${latency_avg_raw:-0}")"
    latency_stdev_raw="$(awk '/^[[:space:]]*Latency[[:space:]]/ { print $3; exit }' "$out_file" 2>/dev/null)"
    latency_stdev_us="$(latency_to_us "${latency_stdev_raw:-0}")"
    latency_max_raw="$(awk '/^[[:space:]]*Latency[[:space:]]/ { print $4; exit }' "$out_file" 2>/dev/null)"
    latency_max_us="$(latency_to_us "${latency_max_raw:-0}")"
    socket_errors=$(awk '/Socket errors:/ { total = 0; for (i = 1; i <= NF; i++) { gsub(",", "", $i); if ($i ~ /^[0-9]+$/) total += $i } print total; exit }' "$out_file" 2>/dev/null)
    socket_errors="${socket_errors:-0}"
    non2xx=$(awk '/Non-2xx or 3xx responses:/ { print $NF; exit }' "$out_file" 2>/dev/null)
    non2xx="${non2xx:-0}"
  else
    rps=0
    requests=0
    latency_avg_us=0
    latency_stdev_us=0
    latency_max_us=0
    p50_us=0
    p75_us=0
    p90_us=0
    p99_us=0
    socket_errors=0
    non2xx=0
    while IFS='=' read -r key value; do
      case "$key" in
      rps) rps="$value" ;;
      requests) requests="$value" ;;
      latency_avg_us) latency_avg_us="$value" ;;
      latency_stdev_us) latency_stdev_us="$value" ;;
      latency_max_us) latency_max_us="$value" ;;
      p50_us) p50_us="$value" ;;
      p75_us) p75_us="$value" ;;
      p90_us) p90_us="$value" ;;
      p99_us) p99_us="$value" ;;
      socket_errors) socket_errors="$value" ;;
      non2xx) non2xx="$value" ;;
      esac
    done < <(parse_oha_metric "$out_file")
    p50="${p50_us}us"
    p99="${p99_us}us"
  fi

  lg_cpu=$(awk '{ if ($1 > max) max = $1 } END { if (max == "") print 0; else print max }' "$lg_stats" 2>/dev/null)
  lg_cpu="${lg_cpu:-0}"

  lua_after="$lua_before"
  native_after="$native_before"
  lua_delta=0
  native_delta=0
  lua_per_request=0
  if [[ "$stats_supported" == "1" ]]; then
    lua_after="$(stats_field "$name" lua_pcalls || printf '0')"
    native_after="$(stats_field "$name" native_calls || printf '0')"
    lua_delta=$((lua_after - lua_before))
    native_delta=$((native_after - native_before))
    if [[ "$requests" =~ ^[0-9]+$ ]] && ((requests > 0)); then
      lua_per_request=$(python3 -c 'import sys; print(f"{int(sys.argv[1]) / max(1, int(sys.argv[2])):.6f}")' "$lua_delta" "$requests")
    fi
  fi

  invalid_reason=""

  if [[ "$loadgen_ec" != "0" ]]; then
    invalid_reason="loadgen-exit-$loadgen_ec"
  elif [[ "$rps" == "0" ]]; then
    invalid_reason="missing-rps"
  elif [[ "$requests" == "0" ]]; then
    invalid_reason="missing-requests"
  elif ! python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) > 0 and float(sys.argv[2]) > 0 else 1)' "$p50_us" "$p99_us"; then
    invalid_reason="missing-latency"
  elif [[ "$socket_errors" != "0" ]]; then
    invalid_reason="socket-errors-$socket_errors"
  elif [[ "$non2xx" != "0" ]]; then
    invalid_reason="non2xx-$non2xx"
  elif grep -q '^server_alive_after=0$' "$meta_file"; then
    invalid_reason="server-dead-after"
  elif [[ "$stats_supported" == "1" && "$validation_modes" == *native_no_lua* && "$lua_delta" != "0" ]]; then
    invalid_reason="native-called-lua"
  elif [[ "$stats_supported" == "1" && "$validation_modes" == *pcall_exact* ]]; then
    tolerance=$(python3 -c 'import sys; n=int(float(sys.argv[1])); print(max(10, int(n * 0.005)))' "$requests")
    diff=$((lua_delta > requests ? lua_delta - requests : requests - lua_delta))
    if ((diff > tolerance)); then
      invalid_reason="pcall-mismatch completed=$requests lua_pcalls=$lua_delta"
    fi
  elif [[ "$stats_supported" == "1" && "$validation_modes" == *pcall_at_least* ]]; then
    if ((lua_delta <= 0)); then
      invalid_reason="pcall-missing completed=$requests lua_pcalls=$lua_delta"
    elif ((lua_delta < requests)); then
      invalid_reason="pcall-undercount completed=$requests lua_pcalls=$lua_delta"
    fi
  fi

  if [[ -z "$invalid_reason" && "$tier" == lua-* && "$stats_supported" == "1" ]]; then
    if ! python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) >= 0.95 else 1)' "$lua_per_request"; then
      invalid_reason="invalid_hybrid_proof lua_pcalls_per_request=$lua_per_request"
    fi
  fi

  if [[ -z "$invalid_reason" && "$validation_modes" == *latency_floor* ]]; then
    if ! python3 -c 'import sys; raise SystemExit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$p99_us" "$latency_floor_us"; then
      invalid_reason="latency-floor p99_us=$p99_us floor_us=$latency_floor_us"
    fi
  fi

  echo "rps=$rps" >>"$meta_file"
  echo "requests_per_sec=$rps" >>"$meta_file"
  echo "requests=$requests" >>"$meta_file"
  echo "requests_completed=$requests" >>"$meta_file"
  echo "accepted_total_after=$accepted_after" >>"$meta_file"
  echo "completed_total_after=$completed_after" >>"$meta_file"
  echo "accepted_total_delta=$accepted_delta" >>"$meta_file"
  echo "completed_total_delta=$completed_delta" >>"$meta_file"
  echo "open_connections_max=$open_connections_max" >>"$meta_file"
  echo "inflight_current_after=$inflight_after" >>"$meta_file"
  echo "inflight_max=$inflight_max" >>"$meta_file"
  echo "observed_inflight_max=$inflight_max" >>"$meta_file"
  echo "queue_depth_current_after=$queue_after" >>"$meta_file"
  echo "queue_depth_max=$queue_max" >>"$meta_file"
  echo "observed_queue_depth_max=$queue_max" >>"$meta_file"
  echo "worker_queue_depth_max=$worker_queue_max" >>"$meta_file"
  echo "budget_capacity=$budget_capacity" >>"$meta_file"
  echo "budget_rejections_total=$budget_rejections" >>"$meta_file"
  echo "backpressure_total=$backpressure_total" >>"$meta_file"
  echo "p50=$p50" >>"$meta_file"
  echo "p99=$p99" >>"$meta_file"
  echo "latency_avg_us=$latency_avg_us" >>"$meta_file"
  echo "latency_stdev_us=$latency_stdev_us" >>"$meta_file"
  echo "latency_max_us=$latency_max_us" >>"$meta_file"
  echo "p50_us=$p50_us" >>"$meta_file"
  echo "p75_us=$p75_us" >>"$meta_file"
  echo "p90_us=$p90_us" >>"$meta_file"
  echo "p99_us=$p99_us" >>"$meta_file"
  echo "socket_errors=$socket_errors" >>"$meta_file"
  echo "non2xx=$non2xx" >>"$meta_file"
  echo "lua_pcalls_after=$lua_after" >>"$meta_file"
  echo "native_calls_after=$native_after" >>"$meta_file"
  echo "lua_pcalls_delta=$lua_delta" >>"$meta_file"
  echo "native_calls_delta=$native_delta" >>"$meta_file"
  echo "lua_pcalls_per_request=$lua_per_request" >>"$meta_file"
  echo "loadgen_cpu_max=$lg_cpu" >>"$meta_file"
  echo "invalid_reason=$invalid_reason" >>"$meta_file"
  sanitize_text_file "$out_file"
  sanitize_text_file "$meta_file"

  if [[ -n "$invalid_reason" ]]; then
    printf "  %-22s c=%-4s rep=%-2s INVALID %-22s RPS=%-10s p99=%-8s lg_cpu=%s%%\n" \
      "$name" "$c" "$rep" "$invalid_reason" "$rps" "$p99" "$lg_cpu"
  else
    printf "  %-22s c=%-4s rep=%-2s RPS=%-10s  p99=%-8s lg_cpu=%s%%\n" \
      "$name" "$c" "$rep" "$rps" "$p99" "$lg_cpu"
  fi
}

run_matrix_for_variant() {
  local label="$1"
  local variant_scenarios=()
  echo "--- $label ---"
  preflight_variant "$label" || return 1
  for _ in 1 2 3; do curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1 || true; done

  variant_scenarios=()
  while IFS= read -r scenario_line; do
    [[ -n "$scenario_line" ]] && variant_scenarios+=("$scenario_line")
  done < <(scenario_lines_for_variant "$label")

  for C in "${CONCURRENCY_VALUES[@]}"; do
    for scenario in "${variant_scenarios[@]}"; do
      IFS='|' read -r name method path <<<"$scenario"
      for rep in $(seq 1 $REPS); do
        run_scenario "$name" "$method" "$path" "$label" "$C" "$rep"
      done
    done
  done
}


should_run_variant() {
  local label="$1"
  [[ -z "$ONLY_VARIANT" || "$ONLY_VARIANT" == "$label" ]]
}


run_selected_variant() {
  local label="$1"
  local starter="$2"
  shift 2
  if ! should_run_variant "$label"; then
    return 0
  fi
  kill_server
  "$starter" "$@"
  run_matrix_for_variant "$label"
}


