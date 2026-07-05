#!/usr/bin/env bash
set -euo pipefail

print_fd_tuning_hints() {
  cat >&2 <<'EOF_HINTS'

macOS/Unix FD tuning hints:
  ulimit -Sn
  ulimit -Hn
  ulimit -n 8192

If macOS launchctl is limiting the session:
  launchctl limit maxfiles
  sudo launchctl limit maxfiles 65536 200000

Open a new terminal and verify:
  ulimit -n
  launchctl limit maxfiles
EOF_HINTS
}


print_backlog_tuning_hints() {
  cat >&2 <<'EOF_HINTS'

Temporary backlog tuning hints:
  sysctl kern.ipc.somaxconn
  sudo sysctl -w kern.ipc.somaxconn=4096

On Linux:
  sysctl net.core.somaxconn
  sudo sysctl -w net.core.somaxconn=4096

Persist this through OS-specific configuration if needed.
EOF_HINTS
}


run_environment_preflight() {
  local env_file="$1"
  echo "bench environment preflight"

  local os_name os_version cpu_model host_cpu_count soft_nofile hard_nofile launch_soft launch_hard
  os_name="$(uname -s 2>/dev/null || printf unknown)"
  if [[ "$os_name" == "Darwin" ]] && command -v sw_vers >/dev/null 2>&1; then
    os_version="$(sw_vers -productVersion 2>/dev/null || printf unknown)"
  else
    os_version="$(uname -r 2>/dev/null || printf unknown)"
  fi
  cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || awk -F: '/model name/ { sub(/^ /, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null || printf unknown)"
  host_cpu_count="$(python3 -c 'import os; print(os.cpu_count() or 1)')"
  soft_nofile="$(ulimit -Sn 2>/dev/null || printf unknown)"
  hard_nofile="$(ulimit -Hn 2>/dev/null || printf unknown)"
  read -r launch_soft launch_hard < <(launchctl_maxfiles)

  local kern_maxfiles kern_maxfilesperproc somaxconn tcp_msl port_first port_last port_hifirst port_hilast ephemeral_count
  kern_maxfiles="$(sysctl_value kern.maxfiles)"
  kern_maxfilesperproc="$(sysctl_value kern.maxfilesperproc)"
  somaxconn="$(first_available_sysctl kern.ipc.somaxconn net.core.somaxconn)"
  tcp_msl="$(first_available_sysctl net.inet.tcp.msl net.ipv4.tcp_fin_timeout)"
  port_first="$(first_available_sysctl net.inet.ip.portrange.first net.ipv4.ip_local_port_range_first)"
  port_last="$(first_available_sysctl net.inet.ip.portrange.last net.ipv4.ip_local_port_range_last)"
  if [[ "$port_first" == "not_available" || "$port_last" == "not_available" ]]; then
    local linux_range
    linux_range="$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null || true)"
    if [[ -n "$linux_range" ]]; then
      port_first="$(awk '{print $1}' <<<"$linux_range")"
      port_last="$(awk '{print $2}' <<<"$linux_range")"
    fi
  fi
  port_hifirst="$(sysctl_value net.inet.ip.portrange.hifirst)"
  port_hilast="$(sysctl_value net.inet.ip.portrange.hilast)"
  ephemeral_count=0
  if [[ "$port_first" =~ ^[0-9]+$ && "$port_last" =~ ^[0-9]+$ && "$port_last" -ge "$port_first" ]]; then
    ephemeral_count=$((port_last - port_first + 1))
  fi

  local max_c fd_margin required_min required_better soft_num somax_num ephem_num
  max_c="$(max_concurrency_requested)"
  fd_margin=$((THREADS * 32))
  if ((fd_margin < 256)); then fd_margin=256; fi
  required_min=$((max_c + 256))
  required_better=$((max_c * 2 + 256))
  soft_num="$(num_or_zero "$soft_nofile")"
  somax_num="$(num_or_zero "$somaxconn")"
  ephem_num="$(num_or_zero "$ephemeral_count")"

  local fd_limit_ok fd_better_ok backlog_ok ephemeral_ports_ok loadgen_exists parser_available environment_suspicious environment_invalid_reason
  fd_limit_ok=true
  fd_better_ok=true
  backlog_ok=true
  ephemeral_ports_ok=true
  loadgen_exists=true
  parser_available=true
  environment_suspicious=false
  environment_invalid_reason=""

  if ((soft_num < required_min)); then
    fd_limit_ok=false
    environment_suspicious=true
    environment_invalid_reason="${environment_invalid_reason:+$environment_invalid_reason,}soft_nofile_${soft_nofile}_below_required_${required_min}"
  fi
  if ((soft_num < required_better)); then
    fd_better_ok=false
    environment_suspicious=true
  fi
  if [[ "$somaxconn" != "not_available" && "$somax_num" -lt "$max_c" ]]; then
    backlog_ok=false
    environment_suspicious=true
    environment_invalid_reason="${environment_invalid_reason:+$environment_invalid_reason,}somaxconn_${somaxconn}_below_requested_${max_c}"
  fi
  if ((ephem_num > 0 && ephem_num < max_c * 2)); then
    ephemeral_ports_ok=false
    environment_suspicious=true
    environment_invalid_reason="${environment_invalid_reason:+$environment_invalid_reason,}ephemeral_ports_${ephem_num}_below_required_$((max_c * 2))"
  fi
  if ! command -v "$LOADGEN" >/dev/null 2>&1; then
    loadgen_exists=false
    parser_available=false
    environment_suspicious=true
    environment_invalid_reason="${environment_invalid_reason:+$environment_invalid_reason,}loadgen_${LOADGEN}_missing"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    parser_available=false
    environment_suspicious=true
    environment_invalid_reason="${environment_invalid_reason:+$environment_invalid_reason,}python3_parser_missing"
  fi
  if [[ -z "$environment_invalid_reason" ]]; then
    environment_invalid_reason="none"
  fi

  local wrk_path oha_path wrk_version oha_version selected_path selected_version kqueue_capable
  wrk_path="$(loadgen_path_safe wrk)"
  oha_path="$(loadgen_path_safe oha)"
  wrk_version="$(loadgen_version_safe wrk)"
  oha_version="$(loadgen_version_safe oha)"
  selected_path="$(loadgen_path_safe "$LOADGEN")"
  selected_version="$(loadgen_version_safe "$LOADGEN")"
  kqueue_capable=false
  if [[ "$os_name" == "Darwin" && "$LOADGEN" == "wrk" ]]; then kqueue_capable=true; fi

  {
    printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'os_name=%s\n' "$os_name"
    printf 'os_version=%s\n' "$os_version"
    printf 'uname=%s\n' "$(uname -a 2>/dev/null || printf unknown)"
    printf 'cpu_model=%s\n' "$cpu_model"
    printf 'host_cpu_count=%s\n' "$host_cpu_count"
    printf 'soft_nofile=%s\n' "$soft_nofile"
    printf 'hard_nofile=%s\n' "$hard_nofile"
    printf 'ulimit_soft_nofile=%s\n' "$soft_nofile"
    printf 'ulimit_hard_nofile=%s\n' "$hard_nofile"
    printf 'launchctl_maxfiles_soft=%s\n' "$launch_soft"
    printf 'launchctl_maxfiles_hard=%s\n' "$launch_hard"
    printf 'kern_maxfiles=%s\n' "$kern_maxfiles"
    printf 'kern_maxfilesperproc=%s\n' "$kern_maxfilesperproc"
    printf 'somaxconn=%s\n' "$somaxconn"
    printf 'tcp_msl=%s\n' "$tcp_msl"
    printf 'ephemeral_port_first=%s\n' "$port_first"
    printf 'ephemeral_port_last=%s\n' "$port_last"
    printf 'ephemeral_port_count=%s\n' "$ephemeral_count"
    printf 'ephemeral_port_hifirst=%s\n' "$port_hifirst"
    printf 'ephemeral_port_hilast=%s\n' "$port_hilast"
    printf 'selected_loadgen=%s\n' "$LOADGEN_LABEL"
    printf 'loadgen=%s\n' "$LOADGEN_LABEL"
    printf 'loadgen_base=%s\n' "$LOADGEN"
    printf 'loadgen_path=%s\n' "$selected_path"
    printf 'loadgen_version=%s\n' "$selected_version"
    printf 'wrk_path=%s\n' "$wrk_path"
    printf 'wrk_version=%s\n' "$wrk_version"
    printf 'oha_path=%s\n' "$oha_path"
    printf 'oha_version=%s\n' "$oha_version"
    printf 'loadgen_threads=%s\n' "$THREADS"
    printf 'loadgen_duration=%s\n' "$DURATION"
    printf 'loadgen_warmup=%s\n' "$WARMUP"
    printf 'latency_correction=%s\n' "$OHA_LATENCY_CORRECTION"
    printf 'oha_latency_correction=%s\n' "$OHA_LATENCY_CORRECTION"
    printf 'target_qps=%s\n' "${TARGET_QPS:-none}"
    printf 'requested_concurrency=%s\n' "$CONCURRENCY"
    printf 'max_concurrency_requested=%s\n' "$max_c"
    printf 'requested_max_concurrency=%s\n' "$max_c"
    printf 'requested_threads=%s\n' "$THREADS"
    printf 'fd_margin=%s\n' "$fd_margin"
    printf 'required_loadgen_fds=%s\n' "$((max_c + fd_margin))"
    printf 'required_server_fds=%s\n' "$((max_c + fd_margin))"
    printf 'required_min_nofile=%s\n' "$required_min"
    printf 'required_better_nofile=%s\n' "$required_better"
    printf 'fd_limit_ok=%s\n' "$fd_limit_ok"
    printf 'fd_better_ok=%s\n' "$fd_better_ok"
    printf 'backlog_ok=%s\n' "$backlog_ok"
    printf 'ephemeral_ports_ok=%s\n' "$ephemeral_ports_ok"
    printf 'keepalive_ephemeral_status=%s\n' "$([[ "$ephemeral_ports_ok" == true ]] && printf ok || printf may_be_insufficient)"
    printf 'connection_churn_ephemeral_status=%s\n' "$([[ "$ephem_num" -ge $((max_c * 8)) || "$ephem_num" -eq 0 ]] && printf ok_or_unknown || printf may_be_insufficient)"
    printf 'loadgen_exists=%s\n' "$loadgen_exists"
    printf 'parser_available=%s\n' "$parser_available"
    printf 'wrk_kqueue_capable=%s\n' "$kqueue_capable"
    printf 'wrk_lua_script=%s\n' "$OUT/post.lua"
    printf 'wrk_lua_script_method=POST\n'
    printf 'wrk_lua_script_body_bytes=1024\n'
    printf 'env_policy=%s\n' "$ENV_POLICY"
    printf 'environment_suspicious=%s\n' "$environment_suspicious"
    printf 'environment_invalid_reason=%s\n' "$environment_invalid_reason"
    printf 'zig_version=%s\n' "$(zig version 2>/dev/null || printf unknown)"
    printf 'go_version=%s\n' "$(go version 2>/dev/null || printf unknown)"
    printf 'bun_version=%s\n' "$(bun --version 2>/dev/null || printf unknown)"
    printf 'rustc_version=%s\n' "$(rustc --version 2>/dev/null || printf unknown)"
    printf 'git_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'moonstone_lock_sha256=%s\n' "$(shasum -a 256 moonstone.lock 2>/dev/null | awk '{print $1}' || printf unknown)"
  } >"$env_file"

  if [[ "$ENV_POLICY" == "strict" ]]; then
    if [[ "$fd_limit_ok" != true ]]; then
      cat >&2 <<EOF_FD
INVALID_ENV_FD_LIMIT:
  soft_nofile=$soft_nofile
  max_concurrency=$max_c
  required_min=$required_min
Raise ulimit or rerun with lower concurrency.
EOF_FD
      print_fd_tuning_hints
      return 66
    fi
    if [[ "$backlog_ok" != true ]]; then
      cat >&2 <<EOF_BACKLOG
INVALID_ENV_BACKLOG_LIMIT:
  somaxconn=$somaxconn
  max_concurrency=$max_c
EOF_BACKLOG
      print_backlog_tuning_hints
      return 67
    fi
    if [[ "$loadgen_exists" != true || "$parser_available" != true ]]; then
      cat >&2 <<EOF_LOADGEN
INVALID_ENV_LOADGEN:
  loadgen=$LOADGEN
  loadgen_path=$selected_path
  parser_available=$parser_available
EOF_LOADGEN
      return 68
    fi
  elif [[ "$ENV_POLICY" == "warn" && "$environment_suspicious" == true ]]; then
    echo "WARNING: benchmark environment suspicious: $environment_invalid_reason" >&2
  fi

  if [[ "$loadgen_exists" != true ]]; then
    echo "Missing load generator: $LOADGEN" >&2
    if [[ "$LOADGEN" == "oha" ]]; then
      echo "Install oha or rerun with --loadgen=wrk" >&2
    else
      echo "Install wrk or rerun with --loadgen=oha" >&2
    fi
    return 127
  fi
}

