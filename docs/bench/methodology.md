# Meteorite Benchmark Methodology

## 1. Benchmark Scope and Philosophy

The Meteorite benchmark suite evaluates web framework throughput, latency percentiles (`p50`, `p75`, `p90`, `p99`, `max`), memory consumption (RSS), and worker thread scaling.

To provide honest, reproducible performance measurements, the suite categorizes benchmarks into distinct **Transport Modes**. Results from different transport modes measure fundamentally different physical properties and MUST NEVER be combined into a single unlabeled ranking table.

---

## 2. Transport Modes

### Mode A: Local Loopback (`127.0.0.1`)
- **Topology**: Client (`oha`/`wrk`) and HTTP Server run on the **same physical machine** over local loopback.
- **What It Measures**: 
  - Pure framework and runtime CPU overhead.
  - Zero-copy string parsing, routing DFA speed, and Zig/Lua boundary cost.
  - Same-host worker pool thread scaling.
- **Limitations**: Client load generator and server process compete for CPU cores, L3 cache, and memory bandwidth. It is NOT a claim of network throughput.

### Mode B: Thunderbolt Bridge Direct-Link (`169.254.X.Y`)
- **Topology**: Client (`oha`/`wrk`) runs on a dedicated **MacBook Air M1**, connected via a direct 40 Gbps Thunderbolt 4 / USB4 cable to the server running on a dedicated **MacBook Pro M3 Pro**.
- **What It Measures**:
  - Server framework throughput under real TCP/IP network load with zero client/server CPU contention.
  - Server kernel socket buffer handling, epoll/kqueue event loop efficiency, and response serialization over physical hardware.
- **Methodology Note**: Thunderbolt Bridge is a direct, low-latency two-host transport (sub-0.2 ms RTT). It is not representative of WAN internet routing or public cloud load balancers.

### Mode C: Standard Ethernet LAN (Future Expansion)
- **Topology**: Client and server connected over a multi-tenant 1 GbE or 10 GbE network switch.
- **What It Measures**: Performance under standard local area network switching and packet queueing.

---

## 3. Link Calibration Protocol (`iperf3`)

Before executing HTTP scenario matrices in Thunderbolt Bridge mode, the harness runs `iperf3` link calibration to establish physical transport health:

1. **Forward & Reverse Streams**: Runs 1, 4, and 8 parallel TCP streams forward (client $\to$ server) and reverse (server $\to$ client).
2. **Bandwidth Threshold**: Rejects runs where 8-stream TCP throughput is $< 5.0\text{ Gbps}$.
3. **Retransmit Threshold**: Flags warnings if TCP packet retransmits exceed $0.1\%$.

Calibration output is saved to `preflight/calibration.json` alongside HTTP benchmark raw outputs.

---

## 4. Load Generator Roles and Client Saturation Audit

Different load generators serve specific measurement goals:

- **`oha` (HTTP/1.1 JSON Driver)**: Primary driver for publishable runs. Produces structured JSON output containing exact latency percentiles, error codes, and status distributions.
- **`wrk` (High-Throughput Driver)**: Used for secondary throughput sanity checks at high connection counts.

### Client Saturation Detection
When benchmarking a high-performance server (M3 Pro) from a lighter client host (M1 Air), the load generator process may reach 100% CPU saturation before the server reaches its framework limit.

The harness continuously audits client host CPU utilization:
- If client CPU reaches $\ge 95\%$ or QPS plateaus while server CPU remains $< 60\%$, the run is annotated with `limiting_factor = client` and marked with a dagger symbol `†` in summary tables.
- **Rule**: Server framework ceilings MUST NOT be published from client-saturated runs without explicit qualification.

---

## 5. Result Comparability Rules

To maintain strict scientific comparability:

1. **Identical Server Hardware**: All compared servers (`meteorite`, `hono`, `go-nethttp`, `go-fiber`, `rust-actix`) MUST run on the exact same M3 Pro server host.
2. **Identical Client Hardware**: All load generation MUST run from the exact same M1 Air client host.
3. **Identical Scenario Contracts**: Every competitor MUST serve the exact same HTTP response body, content-type header, and status code for each scenario.
4. **Separation of Modes**: Loopback and Thunderbolt Bridge results MUST remain in separate, clearly labeled Markdown sections.

---

## 6. Supported Performance Claims

| Supported Claim | Non-Supported Claim |
| :--- | :--- |
| *"Meteorite achieved 199,000 req/s on local loopback ReleaseFast build."* | *"Meteorite will handle 199,000 req/s over the public internet."* |
| *"Under a direct 40 Gbps Thunderbolt 4 bridge without CPU contention, Meteorite served 128,000 req/s to an M1 Air client at 2.4 ms p95 latency."* | *"Meteorite is faster than nginx over WAN networks."* |
| *"Meteorite p99 tail latency remained sub-0.2 ms under 1024 concurrent local connections."* | *"Client latency is unaffected by public network packet loss."* |
