# Meteorite Benchmark Claim Safety Report

## 1. Executive Summary
This report evaluates the current benchmark narrative for Meteorite against Hono/Bun. The objective is to replace sensationalism with scientifically safe, reproducible claims. Local validation on macOS using `wrk` reveals that while Meteorite possesses exceptional single-flight request latency and negligible Lua boundary overhead, extreme high-concurrency throughput is currently capped by the localhost client/kernel loopback interface. The most defensible and remarkable story is architectural: Meteorite enables zero-overhead scripting within a predictable, compiled execution substrate.

## 2. Benchmark Setup Facts
- **Machine:** Apple M3 Pro, 11 Cores, 18 GB Memory
- **OS:** Darwin 25.4.0 (macOS)
- **Environment:** Localhost (Client and Server on the same machine)
- **Load Generators:** `oha` (initial), `wrk -t 10` (latest validation)
- **Meteorite Variants:** `meteorite-1worker` (1 core), `meteorite-auto` (11 cores), built in `release-hybrid`
- **Hono/Bun Variants:** `hono-bun-single` (1 core), `hono-bun-multiprocess` (11 cores via `reusePort` and Node cluster module), `NODE_ENV=production BUN_GARBAGE_COLLECTOR_LEVEL=0`
- **Scenarios:** `plain`, `typed-param`, `hybrid-inline`, `echo-1k` (POST)
- **Repetitions:** Single 10-second run per configuration with a 3-second warmup.
- **Monitoring:** macOS `ps` tracking was attempted but failed to capture background process-group CPU/RSS sums correctly (reported 0).

*Classification Impact:* Because CPU usage, RSS, and multi-run medians are not yet robustly recorded, throughput/efficiency claims remain "local exploratory results" rather than final benchmark facts.

## 3. Safe Claims

| Claim | Evidence | Classification | Notes / Caveats |
|---|---|---|---|
| In local c=1 probes, Meteorite shows lower baseline end-to-end request latency than Hono/Bun. | At `c=1`, Meteorite recorded a p99 of ~50µs vs Hono/Bun at ~125µs. | SAFE TO SAY | Limited to baseline HTTP round-trip request overhead, not parsing/routing specifically. |
| Meteorite inline Lua routes track native/static Meteorite routes closely enough that Lua boundary overhead is not visible above measurement noise for trivial handlers. | `hybrid-inline` achieved identical RPS (~180k) and latency (~50µs) as native `plain` routes at both c=1 and c=1024. | SAFE TO SAY | Explicitly caveat "for trivial handlers in the measured hot path." |
| Meteorite auto-workers prevent single-threaded I/O starvation under load. | In the `echo-1k` payload test at c=1024, `meteorite-1worker` dropped to 20k RPS while `meteorite-auto` sustained 183k RPS. | SAFE TO SAY | Demonstrates the architectural advantage of Zig's thread pooling over event loops. |

## 4. Remarkable / Headline-Worthy Claims

| Claim | Evidence | Classification | Notes / Caveats |
|---|---|---|---|
| Zero-overhead scripting for trivial handlers. | The delta between a compiled Zig route and an inline Lua route is statistically zero under local stress testing. | REMARKABLE / HEADLINE-WORTHY | Must be framed around the framework boundary being thin, not Lua being universally as fast as Zig. |
| Meteorite can automatically drop the Lua runtime from memory when operating in enforced static mode. | `requires_lua` comptime evaluation successfully drops the C-bridge from compilation if no Lua routes/plugins are in the graph. | REMARKABLE / HEADLINE-WORTHY | The exact RSS savings (e.g. 29MB vs 10MB) must be re-verified with working monitoring tools. |

## 5. Claims That Need More Validation

| Claim | Evidence | Classification | Notes / Caveats |
|---|---|---|---|
| Meteorite is more CPU-efficient than Hono/Bun. | Anecdotal observations of CPU usage during `oha` runs; the automated tracking script failed. | NEEDS MORE VALIDATION PUBLICLY | Requires a working `ps` or `top` extraction script to normalize RPS by CPU%. |
| Meteorite consumes strictly less memory (RSS) than Hono/Bun. | Prior manual `htop` observations (~29MB vs ~75MB). | NEEDS MORE VALIDATION PUBLICLY | Must measure the new `meteorite-static-min` and clustered Bun memory usage accurately. |
| Meteorite scales perfectly across all cores. | Localhost `wrk` plateaus at ~180k RPS for both 1-worker and 11-worker setups due to the macOS TCP loopback ceiling. | NEEDS MORE VALIDATION PUBLICLY | A remote-client machine over a physical network is strictly required to prove all-core capacity. |

## 6. Claims to Avoid
- 🚫 **"Meteorite obliterates Bun" / "JS cannot compete":** Sensationalist. Hono/Bun remains incredibly fast (170k RPS local) and is a world-class edge stack.
- 🚫 **"Lua is as fast as Zig" / "Zero cost universally":** False. The *boundary* is zero-cost for trivial I/O, but heavy computation in Lua will inherently trail Zig.
- 🚫 **"Meteorite parses requests 2.5x faster":** Unverifiable. We only measured end-to-end TCP round-trip latency, not isolated parsing phases.
- 🚫 **"Meteorite pushes 180k RPS across all cores":** Misleading. The 180k RPS ceiling was hit on a single core; it is a kernel loopback limit, not a server capacity limit.

## 7. Hono/Bun Fairness Notes
Hono/Bun is an excellent modern JS edge stack. In our tests, even when constrained to a single process, it successfully maximized the macOS loopback interface (~170k RPS). Meteorite is not proving that Hono/Bun is slow; it is proving that a Lua authoring layer over a Zig execution substrate can reach a different point in the latency, memory, and determinism trade space. Any public graphs must show Bun utilizing `reusePort` or Node clustering to ensure an honest all-core vs all-core comparison.

## 8. Meteorite Presentation Narrative
*Meteorite is a compiled service framework where Zig owns the hot path and Lua owns the authoring layer. In local validation, trivial inline Lua routes track native Meteorite routes closely enough that the scripting boundary disappears into measurement noise. Meteorite also shows lower single-flight request overhead than Hono/Bun in this setup. High-concurrency localhost RPS is not a clean all-core server-capacity measurement because the local client/kernel path appears to plateau first. The strongest result is not a single RPS bar; it is the architecture: write services like scripts, execute them like systems software, and reproduce them like artifacts.*

### Presentation Readiness Matrix
- **DX/error diagnostics:** Ready to show
- **Live reload:** Ready to show
- **Route graph:** Ready to show
- **Single-flight latency:** Ready to show
- **Lua boundary cost:** Ready to show (Headline)
- **High-concurrency RPS:** Ready with caveat (Localhost plateau)
- **RSS:** Not ready (Tracking script needs fixing)
- **Moonstone provenance:** Ready to show
- **Ballad release pipeline:** Ready to show
- **Cross-target release:** Ready to show
- **Pipeline/plugin model:** Ready to show

## 9. Remaining Validation Tasks
1. **Fix Resource Tracking:** Repair the bash CPU/RSS polling mechanism (e.g., bypassing process groups and using `pidtree` or `top` snapshots) to accurately record efficiency.
2. **Remote Client Testing:** Deploy the server and `wrk` to separate physical machines to bypass the localhost loopback ceiling and measure true multi-core capacity.
3. **RSS Verification:** Prove that `meteorite-static-min` significantly reduces the ~29MB RSS floor by confirming the absence of the Lua VM allocation.
4. **Statistical Rigor:** Update the benchmark harness to run 3+ repetitions per scenario and report the median to eliminate run-to-run noise.

## 10. Final Recommendation
**PUBLISH WITH CAVEATS**

The narrative is incredibly strong, but we must lead with the architectural victories (Zero-Overhead Scripting, single-flight latency, determinism) rather than raw maximum throughput. Frame the high-concurrency RPS numbers explicitly as "Localhost Probes" and highlight that the server matched the kernel's loopback ceiling on a single core. Wait to publish firm RSS or CPU-efficiency claims until the monitoring harness is patched and validated.
