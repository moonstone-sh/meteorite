# Thunderbolt Bridge Benchmark Implementation Plan

## 1. Overview and Phased Rollout

This document outlines the step-by-step implementation plan for introducing the Thunderbolt Bridge two-host benchmark mode to the Meteorite benchmark suite. The rollout is structured into four distinct, testable phases.

```text
  Phase 1: Manual-Assisted Remote Mode
    └── Basic SSH orchestration, explicit IPs, remote server build/launch/kill, single generator.
  
  Phase 2: Automatic Thunderbolt Discovery & Preflight
    └── macOS interface discovery, route verification, iperf3 calibration, client saturation sweep.
  
  Phase 3: Dual-Host Reporting & Summaries
    └── Dual-host metadata capture, separate loopback vs. Thunderbolt tables in summary.md.
  
  Phase 4: Coordinated Load Sweep & Advanced Latency
    └── Multi-process loadgen sweeps, fixed QPS pacing, coordinated omission reporting.
```

---

## 2. Phase 1 — Manual-Assisted Remote Mode

### Task 1.1: Remote Server Execution Module (`bench/lib/remote_server.sh`)
- **Affected Files**: `bench/lib/remote_server.sh` (New file).
- **Functions to Add**:
  ```bash
  remote_exec() { ssh -o ConnectTimeout=5 "$SERVER_SSH_HOST" "$@"; }
  start_remote_meteorite() { ... }
  start_remote_hono() { ... }
  start_remote_go_nethttp() { ... }
  kill_remote_server() { ... }
  ```
- **Behavior**: Compiles and launches target server on remote M3 Pro host over SSH, records remote PID to `/tmp/meteorite-remote.pid`, polls `http://$SERVER_IP:$PORT/health` from local M1 Air client until ready.

### Task 1.2: Main Harness Options (`bench/run.sh`)
- **CLI Flags**:
  ```bash
  bench/run.sh \
    --transport=thunderbolt \
    --server-host=m3-pro.local \
    --server-ip=169.254.42.2 \
    --loadgen=oha \
    --mode=public
  ```
- **Default Fallback**: If `--transport` is omitted or set to `loopback`, `run.sh` preserves existing loopback execution behavior 100%.

---

## 3. Phase 2 — Automatic Discovery and Link Preflight

### Task 2.1: Preflight & Route Verification (`bench/lib/tb_preflight.sh`)
- **Affected Files**: `bench/lib/tb_preflight.sh` (New file).
- **Functions to Add**:
  ```bash
  discover_thunderbolt_interface() # Uses networksetup & route get
  verify_route_to_peer()            # Asserts route uses bridgeX, NOT en0 (Wi-Fi)
  run_iperf_calibration()          # Runs iperf3 1, 4, 8 streams forward & reverse
  check_clock_drift()              # Compares client date vs server date over SSH
  ```

### Task 2.2: Client Saturation Detection (`bench/lib/saturation.sh`)
- **Affected Files**: `bench/lib/saturation.sh` (New file).
- **Functions to Add**:
  ```bash
  measure_client_cpu_load()        # Samples oha CPU usage on M1 Air
  detect_client_saturation()       # Compares QPS vs. client CPU and concurrency
  ```

---

## 4. Phase 3 — Report Generator Integration

### Task 3.1: Dual-Host Metadata Collection (`bench/collect_env.sh`)
- **Changes**: Modify `collect_env.sh` to generate `client-env.json` locally and execute `remote_exec bash bench/collect_env.sh` to generate `server-env.json`.

### Task 3.2: Markdown Summary & Comparison (`bench/summarize.py` & `bench/compare.py`)
- **Changes**:
  - `summarize.py`: Parse `manifest.json` for `transport.mode`. If `thunderbolt_bridge`, render separate **Thunderbolt 4 Direct-Link Results** section with `limiting_factor` annotations.
  - `compare.py`: Add validation enforcing that loopback directories and Thunderbolt directories are NEVER mixed into a single comparison table.

---

## 5. CLI Specification

### Recommended CLI Syntax
```bash
# Thunderbolt 2-Host Run (M1 Air client calling M3 Pro server)
bench/run.sh \
  --transport=thunderbolt \
  --server-host=macbook-pro-m3.local \
  --server-ip=169.254.42.2 \
  --loadgen=oha \
  --mode=public \
  --out=bench/results/2026-07-27_tb_public

# Default Local Loopback Run (Unchanged)
bench/run.sh \
  --transport=loopback \
  --mode=public
```

---

## 6. Acceptance Criteria

The Thunderbolt Bridge benchmark mode implementation is complete when:
1. `bench/run.sh --transport=thunderbolt` automatically discovers the Thunderbolt Bridge interface and fails preflight if traffic routes over Wi-Fi (`en0`).
2. Link calibration with `iperf3` executes before HTTP scenarios and records bandwidth/retransmit metrics to `$OUT/preflight/calibration.json`.
3. Server processes (`dist/server`, `hono`, `go-nethttp`, etc.) compile and execute cleanly on the M3 Pro server host via SSH, and terminate reliably on test completion or `Ctrl+C`.
4. Client CPU utilization and saturation status (`limiting_factor = client | server`) are recorded for every scenario rep.
5. Generated reports (`summary.md`) strictly separate Loopback and Thunderbolt Bridge benchmark results into distinct labeled sections with methodology notes.
