# Thunderbolt Bridge Benchmark Mode Design Specification

## 1. Overview and Architecture

The **Thunderbolt Bridge Benchmark Mode** is a two-host benchmark harness for Meteorite and competitor servers. It uses a high-speed, direct Thunderbolt 4 / USB4 cable connection between:

- **Client Host (Load Generator)**: MacBook Air M1 (8-core CPU, 16 GB RAM).
- **Server Host (Target Server)**: MacBook Pro M3 Pro (12-core CPU, 18/36 GB RAM).

```text
  ┌──────────────────────────────┐                   ┌──────────────────────────────┐
  │     MacBook Air M1           │                   │     MacBook Pro M3 Pro       │
  │     (Client Host)            │                   │     (Server Host)            │
  │                              │                   │                              │
  │  ┌────────────────────────┐  │  Thunderbolt 4    │  ┌────────────────────────┐  │
  │  │ Controller / Loadgen   │  ├═══════════════════┼─►│ Meteorite / Competitor   │  │
  │  │ (oha / wrk)            │  │  169.254.X.Y/16   │  │ Server (port 8080)     │  │
  │  └───────────┬────────────┘  │  Direct Peer-Peer │  └───────────┬────────────┘  │
  │              │               │                   │              │               │
  │  ┌───────────▼────────────┐  │   SSH Management  │  ┌───────────▼────────────┐  │
  │  │ Client Stats Sampler   │  ├───────────────────┼─►│ Remote Stats Sampler   │  │
  │  └────────────────────────┘  │                   │  └────────────────────────┘  │
  └──────────────────────────────┘                   └──────────────────────────────┘
```

### Core Principles
1. **Loopback remains the framework ceiling benchmark.** Loopback measures local CPU/IPC overhead without physical network layers.
2. **Thunderbolt Bridge is a controlled two-host network benchmark.** It eliminates CPU contention between client generator and server process while providing sub-0.2 ms TCP/IP latency over physical hardware.
3. **No Unlabeled Merging.** Loopback and Thunderbolt Bridge results are stored separately and rendered in distinct, labeled sections of all comparison reports.

---

## 2. Discovery and Preflight Verification

Before executing HTTP benchmarks over Thunderbolt, the preflight script (`bench/lib/tb_preflight.sh`) dynamically discovers the Thunderbolt network interface and validates route integrity.

### 2.1 Interface & Route Discovery Workflow
The preflight script performs portable discovery without hardcoding `bridge0` or static IP addresses:

```bash
# 1. Locate network interface associated with Thunderbolt Bridge service
TB_SERVICE="$(networksetup -listallnetworkservices | grep -i 'Thunderbolt Bridge' || true)"
if [[ -z "$TB_SERVICE" ]]; then
  echo "error: Thunderbolt Bridge service not found in macOS network setup" >&2
  exit 1
fi

# 2. Get hardware port interface name (e.g. bridge0)
TB_IFACE="$(networksetup -listallhardwareports | awk -v s="$TB_SERVICE" '$0 ~ s {getline; print $2}')"

# 3. Verify route to target server IP uses the Thunderbolt interface
SERVER_IP="${SERVER_IP:-169.254.42.2}"
ROUTE_IFACE="$(route -n get "$SERVER_IP" 2>/dev/null | awk '/interface:/ {print $2}')"

if [[ "$ROUTE_IFACE" != "$TB_IFACE" ]]; then
  echo "PREFLIGHT FAILURE: Route to $SERVER_IP uses interface '$ROUTE_IFACE', expected Thunderbolt interface '$TB_IFACE'." >&2
  echo "Traffic would route over Wi-Fi or incorrect interface. Aborting run." >&2
  exit 1
fi
```

### 2.2 Preflight Assertions
The run is rejected immediately if any of these checks fail:
- Thunderbolt interface is inactive or has no IPv4 link-local/assigned address.
- Route to `$SERVER_IP` resolves to `en0` (Wi-Fi) or loopback `lo0`.
- Server port (8080) is unreachable over Thunderbolt IP.
- Host clock drift $|t_{client} - t_{server}| > 2.0\text{ seconds}$.

---

## 3. Link Calibration (`iperf3`)

Before running HTTP scenario matrices, the link is calibrated using `iperf3` to establish baseline TCP bandwidth and retransmit characteristics.

### 3.1 Calibration Matrix
The M1 Air controller initiates `iperf3` client tests against an `iperf3` daemon running on the M3 Pro server:

```bash
# Forward tests (M1 Air -> M3 Pro)
iperf3 -c "$SERVER_IP" -P 1 -t 5 --json > "$OUT/preflight/iperf-fwd-s1.json"
iperf3 -c "$SERVER_IP" -P 4 -t 5 --json > "$OUT/preflight/iperf-fwd-s4.json"
iperf3 -c "$SERVER_IP" -P 8 -t 5 --json > "$OUT/preflight/iperf-fwd-s8.json"

# Reverse test (M3 Pro -> M1 Air)
iperf3 -c "$SERVER_IP" -P 8 -t 5 -R --json > "$OUT/preflight/iperf-rev-s8.json"
```

### 3.2 Thresholds and Diagnostics
- **Bandwidth Floor**: Warn if 8-stream TCP throughput is $< 5.0\text{ Gbps}$ over Thunderbolt Bridge.
- **Retransmit Threshold**: Warn if TCP retransmits exceed $0.1\%$ of total packets transferred.
- **Symmetry Check**: Warn if forward vs. reverse throughput differs by more than $30\%$.

Calibration data is written to `$OUT/preflight/calibration.json` and attached to the run report.

---

## 4. Client Saturation Sweeps and Bottleneck Detection

Because the M3 Pro server host may outperform the M1 Air load generator, the client host must be continuously monitored for saturation.

### 4.1 Saturation Sweep Probe
Before recording official scenario runs, the controller executes a 5-second concurrency/thread sweep using `oha`:

$$\text{Concurrency } C \in \{1, 8, 32, 64, 128, 256, 512\}, \quad \text{Threads } T \in \{1, 2, 4, 8\}$$

### 4.2 Saturation Classification Logic
A scenario run is classified as **Client-Limited** if any of the following conditions hold:

1. **Client CPU Saturation**: M1 Air generator process CPU utilization $\ge 95\%$ of available core allocation while M3 Pro server CPU utilization is $< 60\%$.
2. **Throughput Plateau**: Increasing concurrency $C$ from $128 \to 256 \to 512$ yields $< 2\%$ increase in QPS on the client while server CPU remains unconstrained.
3. **Multi-Process Gain**: Spawning 2 parallel `oha` processes increases aggregate QPS by $> 15\%$ over a single `oha` process at the same concurrency.

When client saturation is detected, the run record sets:
```json
{
  "client_saturated": true,
  "limiting_factor": "client"
}
```
In generated reports, client-limited metrics are annotated with a dagger (`†`) footnote.

---

## 5. Result Schema and Metadata Capture

Every Thunderbolt Bridge run records dual-host system metadata and per-scenario metrics in `$OUT/manifest.json`:

```json
{
  "run_id": "2026-07-27T183000Z_thunderbolt_m1-m3pro",
  "transport": {
    "mode": "thunderbolt_bridge",
    "client_interface": "bridge0",
    "client_ip": "169.254.42.1",
    "server_ip": "169.254.42.2",
    "route_interface": "bridge0",
    "iperf_8stream_gbps": 18.4,
    "retransmits_pct": 0.002
  },
  "client_host": {
    "model": "MacBookAir10,1",
    "chip": "Apple M1 (4P+4E)",
    "ram_gb": 16,
    "os": "macOS 14.5",
    "loadgen": "oha 1.14.0"
  },
  "server_host": {
    "model": "MacBookPro18,1",
    "chip": "Apple M3 Pro (6P+6E)",
    "ram_gb": 18,
    "os": "macOS 14.5",
    "zig_version": "0.16.0"
  },
  "benchmark_result": {
    "scenario": "plain-zig",
    "implementation": "meteorite-auto",
    "mode": "release-static",
    "backend": "fast_http",
    "concurrency": 256,
    "duration_s": 30,
    "requests_completed": 3842100,
    "rps": 128070.0,
    "latency_p50_us": 1820,
    "latency_p95_us": 2410,
    "latency_p99_us": 3150,
    "latency_max_us": 8920,
    "socket_errors": 0,
    "client_cpu_pct": 98.2,
    "server_cpu_pct": 42.1,
    "client_saturated": true,
    "limiting_factor": "client"
  }
}
```

---

## 6. Directory Structure for Raw Artifacts

```text
bench/results/2026-07-27T183000Z_thunderbolt/
├── manifest.json
├── preflight/
│   ├── client-network.json
│   ├── server-network.json
│   ├── route-check.txt
│   └── iperf/
│       ├── fwd-s1.json
│       ├── fwd-s8.json
│       └── rev-s8.json
├── client/
│   ├── system.json
│   ├── cpu-samples.csv
│   └── raw-oha/
│       ├── meteorite-auto__plain-zig__c256.json
│       └── hono-bun-multiprocess__plain-zig__c256.json
├── server/
│   ├── system.json
│   ├── cpu-memory.csv
│   ├── meta/
│   │   ├── meteorite-auto.meta.json
│   │   └── hono-bun-multiprocess.meta.json
│   └── logs/
│       ├── meteorite-auto-server.log
│       └── hono-bun-multiprocess-server.log
└── report/
    └── summary.md
```

---

## 7. Failure Semantics and Cleanup Invariants

1. **Signal Trapping**: Controller installs a global signal handler for `EXIT`, `INT`, `TERM`, `HUP`.
2. **Remote Cleanup**: On signal or exit, controller executes:
   ```bash
   ssh "$SERVER_HOST" "pkill -f 'dist/server|go-nethttp-server|go-fiber-server|meteorite-bench-rust-actix' || true; lsof -tiTCP:$PORT | xargs kill -9 2>/dev/null || true"
   ```
3. **Local Cleanup**: Controller kills local `oha` processes and background stats collection scripts.
4. **Preservation of Partial Output**: If a run fails or is interrupted mid-matrix, partial `.json` raw files are preserved in `$OUT/raw/` and marked with `"run_status": "interrupted"`.
