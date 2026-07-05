# Meteorite Benchmark Inventory and Lean Validation Plan

## 1. Executive Summary
This document inventories the existing benchmark sprawl and proposes a structured, tiered validation plan. The goal is to eliminate massive, multi-hour overlapping benchmark runs by separating quick directional checks (smoke/architecture) from rigorous, client-saturated public validations. This plan significantly reduces runtime, properly tracks macOS background process resources, and ensures we test true all-core capacity vs local loopback limits.

## 2. Existing Benchmark Assets

| Path | Purpose | Generator | Status | Notes |
|---|---|---|---|---|
| `bench/run-fair-matchup.sh` | Main legacy matrix script | `oha` | **Obsolete** | Hardcoded to 11-core Meteorite vs 1-core Bun. Broken CPU/RSS tracking. |
| `bench/run-focused-matrix.sh` | Experimental cluster test | `oha` | **Useful** | Initial test of single vs auto workers. |
| `bench/run-wrk-matrix.sh` | Latest true stress test | `wrk` | **Useful** | Uncovered kernel loopback ceiling. Needs CPU tracking fix. |
| `bench/check-lua-state-correctness.sh` | Validates Lua state isolation | `curl` | **Useful** | Keep for regression testing. |
| `bench/run-lua-stability.sh` | Hybrid route stress test | `oha` | **Merge** | Should be absorbed into Architecture Validation Suite. |
| `bench/compare.py` / `summarize.py` | JSON parsing & MD generation | N/A | **Useful** | |
| `bench/results/` | Output directories (`*.json`, `*.log`, `*.md`) | N/A | **Archive** | Dozens of past runs cluttering directory. Should be archived or cleared. |
| `bench/competitors/hono/server.ts` | Hono/Bun reference server | N/A | **Useful** | Now supports `reusePort: true`. |
| `bench/competitors/hono/server-cluster.ts` | Clustered Bun reference | N/A | **Useful** | Uses Node cluster + `reusePort` for all-core test. |
| `bench/competitors/hono/server-node.mjs` | Node/Fastify baseline | N/A | **Future** | Keep for optional Node comparisons. |

## 3. Server Variants Currently Supported

| Variant | Command / Config | Process/Worker Count | Fair Against | Status |
|---|---|---|---|---|
| `meteorite-static` | `mode=release-static` | Auto / 11 | All-Core | Supported |
| `meteorite-hybrid` | `mode=release-hybrid` | Auto / 11 | All-Core | Supported |
| `meteorite-1worker` | `-Dfast-http-workers=1` | 1 worker pool | 1-Core | Supported |
| `meteorite-auto` | `-Dfast-http-workers=0` | CPU Count (11) | All-Core | Supported |
| `meteorite-static-min` | `mode=release-static` (0 lua routes) | Auto / 11 | All-Core | Supported |
| `hono-bun-single` | `bun server.ts` | 1 | 1-Core | Supported |
| `hono-bun-multiprocess` | `bun server-cluster.ts` | CPU Count (11) | All-Core | Supported |

*Important:* We must strictly avoid comparing `hono-bun-single` against `meteorite-auto`. 

## 4. Route Scenario Coverage

| Scenario | Meteorite? | Hono? | Tests | Keep? |
|---|---|---|---|---|
| `health` | Both | Yes | Absolute baseline overhead | No (use `plain`) |
| `plain` | Both | Yes | Native/Static baseline | Yes |
| `raw` | Both | No | Framework bypass layer | Internal-only |
| `typed-param` | Both | Yes | Route compiler constraint logic | Yes |
| `pattern-param` | Both | Yes | Route compiler pattern matching | Merge |
| `hybrid-inline` | Both | Yes | Lua boundary cost (zero-penalty) | Yes |
| `echo-1k` | Both | Yes | Body/IO pressure | Yes |
| `Lua file handler` | Both | No | File-system IO inside Lua | Future |
| `pipeline-1` / `pipeline-3` | Both | No | Abstraction/middleware cost | Future |

## 5. Duplicate / Redundant Coverage
- **`plain` vs `health` vs `raw`:** Reduce to just `plain` for public benchmarks. `health` and `raw` prove the same baseline TCP boundary thesis.
- **`typed-param` vs `pattern-param`:** Reduce to `typed-param` for the public suite. Both test the route compiler's DFA execution efficiency.
- **`echo-small` vs `echo-1k` vs `hybrid-inline-echo`:** Reduce to `echo-1k`. This perfectly applies body IO pressure to test the single-threaded starvation thesis.

## 6. Gaps That Matter
1. **Remote Load Generation:** `wrk` on localhost hit the macOS kernel loopback ceiling (~180k RPS). We must run tests over a physical network to prove "true multi-core scaling."
2. **Resource Tracking:** Background macOS tracking (`ps -g`) failed. We must implement explicit child-pid iteration (or use tools like `pidtree`) to capture RSS/CPU accurately.
3. **Pipeline/Plugin Scenarios:** We need to implement and test `pipeline-3` (Auth, Logging, Trace) to prove the middleware cost is low.

---

## 7. Recommended Fast Smoke Suite
**Purpose:** Quick regression check during active development.
- **Duration:** 10s run, 2s warmup, 1 rep.
- **Variants:** `meteorite-hybrid`, `hono-bun-single`.
- **Scenarios:** `plain`, `hybrid-inline`, `echo-1k`.
- **Concurrency:** 1, 64, 1024.
- **Est. Runtime:** ~2 minutes.

## 8. Recommended Architecture Validation Suite
**Purpose:** Validate Meteorite’s internal thesis (boundary cost, body pressure, compiler efficiency) using `wrk`.
- **Duration:** 15s run, 3s warmup, 2 reps (report max).
- **Variants:** `meteorite-1worker`, `hono-bun-single`.
- **Scenarios:** `plain`, `typed-param`, `hybrid-inline`, `echo-1k`, `pipeline-1` (future).
- **Concurrency:** 1, 16, 64, 512, 1024.
- **Est. Runtime:** ~12 minutes.

## 9. Recommended Public/Presentation Suite
**Purpose:** Generate bulletproof, defensible charts.
- **Duration:** 20s run, 5s warmup, 3 reps (report median, min, max).
- **Variants:** `meteorite-1worker`, `meteorite-auto`, `hono-bun-single`, `hono-bun-multiprocess`.
- **Scenarios:** `plain`, `typed-param`, `hybrid-inline`, `echo-1k`.
- **Concurrency:** 1, 64, 512, 1024.
- **Est. Runtime:** ~35 minutes. *(Drastically down from 4 hours)*

## 10. Recommended Long-Run Headline Suite
**Purpose:** Validate explicitly bold text for the presentation.
- **Duration:** 60s run, 5s warmup, 3 reps.
- **Scenarios & Variants:**
  - `meteorite-1worker` vs `hono-single` on `plain` at `c=1`. (Headline: 2.5x Single-Flight Latency)
  - `meteorite-auto` vs `hono-multiprocess` on `hybrid-inline` at `c=1024`. (Headline: Zero-Overhead Scripting)
- **Est. Runtime:** ~10 minutes.

---

## 11. Resource Tracking Requirements
No claims regarding CPU efficiency or RSS will be made publicly until the following is implemented:
- Stop relying on `ps -g` (macOS process groups are unreliable in detached background jobs).
- Recursively collect explicitly spawned worker PIDs using `pgrep -P`.
- Sum RSS and CPU explicitly across all identified children.
- If the tracker fails (e.g., reports 0), the script must label the fields `unavailable`, not 0.

## 12. Claims Each Suite Can Support
- **Architecture Validation:** Can safely claim "Lua inline routes track native static routes" and "1-worker Zig matches 1-worker Bun".
- **Public Validation:** Can safely claim "Meteorite outperforms Node/Bun in baseline single-flight overhead" and "Meteorite auto-workers prevent I/O starvation on large payloads".
- *(Only with Remote Network Testing)*: Can safely claim "Meteorite pushes 1+ million RPS across all cores".

## 13. Final Recommendation
Our current benchmarks are diverse enough but dangerously bloated due to matrix multiplication (`6 concurrencies * 8 routes * 4 variants = 192 runs per suite`). By trimming the redundant scenarios (health, raw, pattern, echo-small) and dropping `c=4`, we eliminate duplicate work.

**Action Plan:** Do not run the 4-hour suite. We should consolidate `run-wrk-matrix.sh` into exactly these 4 tiered modes (e.g. `./bench/run.sh --mode=public`), repair the PID tree monitoring script, and focus entirely on the **Public Validation Suite (~35m)** to lock in the final presentation numbers.
