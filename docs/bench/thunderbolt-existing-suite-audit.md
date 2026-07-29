# Audit of Existing Meteorite Benchmark Suite for Remote Execution

## 1. Executive Summary

The Meteorite benchmark suite is a local benchmark harness written in Bash (`bench/run.sh`, `bench/lib/*.sh`) and Python (`bench/summarize.py`, `bench/compare.py`). It measures throughput, latency percentiles (`p50`, `p75`, `p90`, `p99`, `max`), memory consumption (RSS/VSZ), and worker scaling across Meteorite build modes (`release-static`, `release-hybrid`) and competitor servers (`hono`, `go-nethttp`, `go-fiber`, `rust-actix`, `openresty`, `lapis`, `turbo`, `pegasus`).

The current suite operates on **local loopback (`127.0.0.1`)**, where the HTTP load generator (`oha` or `wrk`) and the HTTP server run on the same physical machine and compete for CPU cores, memory bandwidth, and kernel socket locks.

This audit evaluates every component of the harness to identify loopback assumptions, reusable modules, and required changes for adding a two-host **Thunderbolt Bridge benchmark mode** (MacBook Air M1 client vs. MacBook Pro M3 Pro server).

---

## 2. Component Inventory and Remote Reusability

| Component | File Path | Current Purpose | Assumes Loopback? | Reusable Remotely? | Required Changes |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **Main Orchestrator** | `bench/run.sh` | CLI argument parsing, mode dispatch, result directory creation. | Yes | Yes (with flag additions) | Add `--transport=loopback\|thunderbolt`, `--server-host`, `--client-host`, `--config`. |
| **Environment Preflight** | `bench/lib/env_preflight.sh` | Checks local tools (`oha`, `wrk`, `zig`, `go`, `bun`), file descriptor limits (`ulimit -n`), sysctl settings. | Yes | Partially | Split into `client_preflight` (local M1 Air) and `server_preflight` (remote M3 Pro over SSH). |
| **Server Lifecycle** | `bench/lib/server.sh` | Builds server binaries, spawns background PIDs (`$!`), polls readiness (`wait_for_server`), runs stats tracker, kills PIDs (`lsof -tiTCP`). | Yes | No (Local PID assumption) | Refactor into remote SSH execution module (`remote_server.sh`) with remote PID tracking and cleanup. |
| **Load Generator Driver** | `bench/lib/loadgen.sh` | Invokes `oha` or `wrk` with specified concurrency, duration, threads; parses `oha` JSON output using Python. | No | **100% Reusable** | Pass remote `<server-ip>:<port>` instead of `127.0.0.1`. |
| **Matrix Runner** | `bench/lib/matrix.sh` | Sweeps scenarios (`plain-zig`, `health`, `echo-small`, `echo-8k`, etc.), concurrency levels, and repetitions; writes `.meta` files. | Partially | Yes | Add `client_cpu`, `client_saturated`, `limiting_factor`, `transport`, `client_interface` metadata keys. |
| **Route Verification** | `bench/lib/verify.sh` | Validates `/ __bench/fixture-info`, `/__bench/meta`, worker count, build mode, and route payload contracts before timing. | Partially | Yes | Target remote `<server-ip>:<port>` for pre-test and post-test HTTP probes. |
| **Scenario Registry** | `bench/lib/scenario.sh` | Defines scenarios, HTTP methods, paths, headers, claim classes, and latency floors. | No | **100% Reusable** | No structural changes needed. Payload contracts are transport-agnostic. |
| **Process Tracking** | `bench/lib/tracking.sh` | Registers local PIDs for clean teardown on `EXIT`/`INT`. | Yes | Partially | Expand to execute remote process cleanup over SSH on interrupt. |
| **Memory / CPU Sampler** | `bench/collect_memory.sh` | Polls `ps -o rss,vsz,pcpu` every 0.1s for a target local PID. | Yes | No (Local PID assumption) | Execute stats sampler remotely on M3 Pro server host during test window. |
| **Summary Generator** | `bench/summarize.py` | Reads raw JSON, `.meta`, `env.json`, `memory.csv`, and writes `summary.md`. | Yes (Single machine metadata) | Yes | Update to parse dual `client-env.json` + `server-env.json` and render separate transport sections. |
| **A/B Comparison** | `bench/compare.py` | Compares multiple result directories and builds markdown comparison tables. | No | **100% Reusable** | Add check ensuring loopback and Thunderbolt runs are never mixed into one table. |

---

## 3. Enumeration of Loopback Assumptions and Hardcoded Invariants

Code analysis revealed the following hardcoded loopback assumptions across the suite:

1. **Hardcoded IP Address (`HOST="127.0.0.1"`)**:
   - `bench/run.sh:9`: `HOST="127.0.0.1"`
   - `bench/lib/server.sh:11`: `curl -fsS "http://$HOST:$PORT/health"`
   - `bench/lib/matrix.sh:21`: `local url="http://$HOST:$PORT$path"`
   - *Fix*: Parameterize `$HOST` to accept a discovered Thunderbolt IP address (e.g. `169.254.X.Y` or statically configured peer IP).

2. **Local Process Management (`SERVER_PID=$!`)**:
   - `bench/lib/server.sh:97`: `./dist/server >"$OUT/${label}.log" 2>&1 & SERVER_PID=$!`
   - `bench/lib/server.sh:44`: `kill -0 "$SERVER_PID"`
   - `bench/lib/server.sh:59`: `lsof -tiTCP:$PORT | xargs kill -9`
   - *Fix*: When running in Thunderbolt mode, server compilation, launch, PID tracking, and port cleanup must execute on the M3 Pro server via SSH (`ssh m3-pro "..."`).

3. **Local Sampling (`collect_memory.sh $SERVER_PID`)**:
   - `bench/lib/server.sh:101`: `start_stats_tracker "$SERVER_PID" "$SERVER_STATS_FILE"`
   - `collect_memory.sh:24`: Uses local `ps -p "$PID"` to capture RSS/VSZ.
   - *Fix*: Execute `collect_memory.sh` on the M3 Pro host via background SSH process, writing output to `/tmp/meteorite-bench-remote/memory.csv`, then `scp` back to client output directory.

4. **Single Host Environment Metadata (`collect_env.sh`)**:
   - `collect_env.sh` gathers `uname`, CPU model, core count, RAM, sysctl limits from the local machine and writes `env.json`.
   - *Fix*: Create `client-env.json` (M1 Air load generator specs, thermal state, interface specs) and `server-env.json` (M3 Pro server specs, Zig/Go/Bun compiler versions, kernel limits).

5. **Assumed Monolithic Result Output (`$OUT/`)**:
   - The suite writes all logs, `.meta` files, and `.json` outputs to a single local directory `$OUT/`.
   - *Fix*: Maintain `$OUT/client/`, `$OUT/server/`, `$OUT/preflight/`, and `$OUT/raw/` subdirectories.

---

## 4. Answers to Audit Specifics

### Q1: Can the current parser consume `oha` or `wrk` output generated on another host without modification?
**Yes.** `parse_oha_metric` in `bench/lib/loadgen.sh` and `summarize.py` operate strictly on the structure of the JSON generated by `oha` (`--output-format json`) or stdout of `wrk`. They do not inspect network interfaces or host origins.

### Q2: Which scripts assume the server PID is local?
`bench/lib/server.sh` (all `start_*` and `kill_server` functions) and `bench/collect_memory.sh`.

### Q3: Which sampling features become unavailable remotely?
- Direct local `ps` / `top` memory tracking of the server PID (requires remote SSH sampler execution).
- Local `lsof -tiTCP:$PORT` port checks (requires remote `netstat` / `lsof` via SSH).
- Linux `perf stat` hardware counters (if benchmarking Linux remote target).

### Q4: Should the controller live on the client or server?
**The Controller must live on the M1 Air Client Host.**
- **Rationale**: The client host drives the load generator (`oha`/`wrk`), measures precise HTTP request latencies locally, controls benchmark duration, and monitors client CPU saturation.
- The controller uses SSH to orchestrate server builds, startup, readiness checks, and remote sampling on the M3 Pro server host.

### Q5: Can the M1 Air saturate the fastest Meteorite route on the M3 Pro?
**Yes.** On local loopback, Meteorite peak throughput reaches ~200,000 req/s. Single-process `oha` running on an M1 Air client over TCP/IP usually plateaus at ~80,000–120,000 req/s due to single-threaded Rust/Tokio event-loop limits and OS socket buffer overhead.
- **Consequence**: The suite MUST include **Client Saturation Detection** to flag when the M1 Air generator is the bottleneck.

### Q6: How will the suite prove when it cannot?
By recording client CPU utilization during the run, running multi-process generator sweeps, and comparing offered vs. achieved QPS. If client CPU reaches 100% and increasing generator processes/concurrency yields no QPS growth while server CPU remains under 50%, `client_saturated` is set to `true` and `limiting_factor` is set to `client`.

### Q7: Does using multiple generator processes improve the ceiling?
**Yes.** Running 2 or 4 parallel `oha` processes on separate M1 Air cores bypasses single-process event loop bottlenecks and increases maximum request generation capacity by 40–80%.

### Q8: Is the Thunderbolt Bridge route accidentally falling back to Wi-Fi?
This is a critical risk on macOS. If preflight resolves the server hostname via mDNS (`macbook-pro.local`) or if the routing table prioritizes `en0` (Wi-Fi), traffic will route over Wi-Fi (500–900 Mbps, high jitter) instead of Thunderbolt (`bridge0`, 10–40 Gbps).
- **Prevention**: Preflight executes `route get <server-ip>` and asserts `interface: bridgeX` (and `interface != en0`). It also executes an `iperf3` bandwidth check (> 5 Gbps required).

### Q9: Is link bandwidth or packets-per-second (PPS) relevant for tested payloads?
- **Small Payloads (`plain-zig`, `health`, 27 bytes)**: At 200,000 req/s, total bandwidth is only ~192 Mbps. **Packets-Per-Second (PPS) and kernel TCP interrupt processing** are the bottlenecks, not link bandwidth.
- **Large Payloads (`echo-8k`, 8192 bytes)**: At 50,000 req/s, bandwidth is ~3.28 Gbps. **PCIe/USB4 DMA throughput and TCP window scaling** become relevant.

### Q10: Which existing routes are meaningful remotely?
- `plain-zig` (`GET /__bench/plain`): Framework/network baseline ceiling.
- `health` (`GET /health`): Static route overhead.
- `echo-small` (`POST /echo`, 50B): Bidirectional small payload transport.
- `echo-8k` (`POST /echo`, 8KB): Bounded payload streaming & socket buffer efficiency.
- `typed-param` (`GET /users/123`): Parameter parsing over remote TCP.
- `hybrid-inline` (`GET /hybrid-inline`): Remote inline Lua execution overhead.

### Q11: Which benchmarks are loopback-only by design?
- `legacy_scan` vs `method_buckets` micro-router dispatch comparisons (sub-microsecond differences obscured by physical network latency).
- Idle memory footprint & process startup time benchmarks.

### Q12: How are server binaries synchronized and verified?
The controller triggers git checkout and build on the M3 Pro via SSH (`ssh m3-pro "cd meteorite && zig build install-server ..."`). Before timing, the client executes HTTP GET requests to `http://<server-ip>:<port>/__bench/meta` and `/__bench/fixture-info` to verify commit hash, build mode, backend, and worker counts match expected values.

### Q13: How are competitor versions pinned?
Competitor lockfiles (`bun.lock`, `go.mod`, `Cargo.lock`) are checked in under `bench/competitors/<name>/`. Server preflight records `bun --version`, `go version`, `cargo --version`, `rustc --version` on the M3 Pro server host.

### Q14: How are clocks and run IDs correlated?
- **Run ID**: ISO-8601 UTC timestamp + transport mode (`2026-07-27T180000Z_thunderbolt_m1-m3pro`).
- **Clock Drift**: Preflight measures wall-clock delta $\Delta t = |t_{client} - t_{server}|$.
- **Latency Measurement**: Latency is measured strictly **locally on the M1 Air** using high-resolution monotonic timers in `oha`/`wrk`. Timestamps across hosts are never subtracted to calculate latency.

### Q15: How are failed remote processes cleaned up?
Controller installs a signal trap (`INT`, `TERM`, `EXIT`, `HUP`). On trigger, it executes `ssh m3-pro "pkill -f 'dist/server|go-nethttp-server|go-fiber-server|meteorite-bench-rust-actix' || true; lsof -tiTCP:$PORT | xargs kill -9 2>/dev/null || true"`.

### Q16: How are raw files collected if SSH drops?
Client-side `oha` JSON raw files are written directly to M1 Air local disk. Remote server logs and stats are buffered in `/tmp/meteorite-bench-server/` on the M3 Pro and synced via `scp` after each scenario. If SSH drops during a run, client raw data is saved and marked `incomplete_ssh_dropped` in metadata.

### Q17: Should `iperf3` calibration run once per session or before every matrix?
**Once per benchmark session** during preflight (testing 1, 4, 8 streams forward and reverse). If an individual scenario exhibits an unexpected >30% QPS drop between reps, a 2-second lightweight `iperf3` check is triggered to detect transient link degradation.

### Q18: How are thermal effects controlled?
- Preflight reads thermal level on both hosts (`powermetrics --samplers thermal` or `sysctl`).
- Imposes a 5-second cooldown between scenario repetitions and a 15-second cooldown between competitor server changes.
- Records `thermal_warning = true` in metadata if thermal throttling occurs during a run.

### Q19: How are client-limited results shown rather than hidden?
In `summary.md` and comparison tables, any row where `client_saturated = true` displays a dagger symbol `†` with a footnote:
`† Client load generator reached 100% CPU saturation; server capacity likely higher.`

### Q20: What exact claim will the resulting benchmark support?
**Supported Claim**: *"Under a direct 40 Gbps Thunderbolt 4 bridge link with zero shared CPU contention, Meteorite running on an M3 Pro server host achieved X req/s at Y ms p99 latency driven by an independent M1 Air client host."*
**Non-Claim**: It is NOT a claim of WAN internet performance, public edge network routing, or TLS termination performance over public networks.
