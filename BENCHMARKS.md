# Meteorite Benchmark Results

> **macOS aarch64, ReleaseFast**
> Latest comparison: [`bench/results/latest-comparison.md`](bench/results/latest-comparison.md)
> Raw artifacts:
> - Meteorite release-static: [`bench/results/latest-meteorite-release-static/`](bench/results/latest-meteorite-release-static/)
> - Meteorite release-hybrid optimized: [`bench/results/latest-meteorite-release-hybrid/`](bench/results/latest-meteorite-release-hybrid/)
> - Hono Bun: [`bench/results/latest-hono-bun/`](bench/results/latest-hono-bun/)

These benchmarks measure local framework/runtime overhead on one machine. They are **not** claims of real-world internet throughput.

## Scope and Caveat

The current headline results use Meteorite's experimental `fast_http_pool` backend, the optimized hybrid profile, and per-thread cached Lua states. They should be read as same-machine, local-loopback benchmark results under this harness.

`std_http` remains the correctness/default backend; `fast_http_pool` is the experimental high-performance backend used for current headline performance runs.

## Latest Publishable Results: Optimized Hybrid Stability Run

These results come from the per-thread cached Lua state validation sprint. The run used the `fast_http_pool` backend with the optimized hybrid profile and per-thread Lua states.

Environment:

```text
Commit: 1201f23
OS: macOS arm64
Zig: 0.16.0
Load generator: oha 1.14.0
Backend: fast_http_pool
Meteorite mode: release-hybrid
Hybrid profile: optimized
Lua state strategy: per_thread_cached_refs
```

### Correctness smoke

The optimized hybrid runtime passed the Lua correctness smoke test.

```text
lua_states_created = 2
threads_spawned = 2
lua_errors = 0
```

Validated behavior:

```text
- Lua state reuse works.
- Worker-local counters remain monotonic per Lua state.
- require() cache persists per Lua state.
- shared native store increments globally.
- request-local state does not leak between requests.
```

### 60s normal hybrid ladder

| Target | Peak route | Peak req/s | p50 | p95 | p99 |
|---|---|---:|---:|---:|---:|
| Meteorite release-static | `plain-static` | 199,129 | 0.050 ms | 0.095 ms | 0.120 ms |
| Meteorite release-hybrid | `hybrid-zig` | 199,210 | 0.050 ms | 0.094 ms | 0.117 ms |
| Meteorite release-hybrid | `hybrid-inline` | 192,199 | 0.051 ms | 0.101 ms | 0.131 ms |
| Hono Bun | inline equivalent | 158,023 | 0.757 ms | 1.130 ms | 1.751 ms |
| Hono Bun | echo equivalent | 128,281 | 0.962 ms | 1.216 ms | 1.940 ms |

Latency values are from the same `oha` run that produced the peak req/s for each row.

Key observations:

```text
- Optimized hybrid inline Lua routes were within roughly 93–98% of the release-static baseline on the tested routes.
- Hono Bun trailed the Meteorite optimized hybrid run on the measured inline, param, and echo workloads by roughly 18–27% in req/s and showed 10–15× higher p99 tail latency at the concurrency where its peak throughput occurred in this run.
- No queue drops were observed.
- No Lua errors were observed.
- RSS remained stable, around 29 MB idle to 31 MB max.
```

### 120s high-concurrency pressure run

The high-concurrency run used concurrency levels 512 and 1024.

```text
lua_states_created = 11
lua_errors = 0
dropped_connections = 0
max_queue_depth = 1,013
```

The queue drained cleanly and the worker pool did not show unbounded thread growth.

| Route | Concurrency | Req/s | p99 |
|---|---|---:|---:|
| `plain-static` | 1024 | 214,095 | ~0.122 ms |
| `hybrid-zig` | 1024 | 205,963 | ~0.121 ms |
| `raw-native` | 1024 | 203,732 | ~0.127 ms |
| `hybrid-inline` | 512 | 182,616 | ~0.124 ms |
| `hybrid-inline` | 1024 | 180,201 | ~0.131 ms |
| `hybrid-inline-params` | 1024 | 183,796 | ~0.123 ms |

p99 latency stayed around 0.12–0.15 ms in the pressure run.

### Interpretation

The previous optimized hybrid bottleneck was the single Lua lock. Replacing the single locked cached Lua state with per-thread cached Lua states and handler references removed that bottleneck.

The benchmark ladder now shows:

```text
- Static native routes remain near the fast_http_pool backend ceiling.
- Hybrid Zig routes remain close to release-static routes.
- Inline Lua routes are close to the native baseline for trivial, param, and echo workloads.
- Request-local state isolation, per-state require caching, and shared native store behavior are validated.
```

The remaining caveat is high max-latency outliers where max latency exceeds 10× p99. On local macOS loopback this is likely scheduler noise, but the report keeps the warning visible and does not use max latency as the main performance claim.

## Current Claim

In these local benchmark scenarios, Meteorite's optimized hybrid Lua mode with `fast_http_pool` and per-thread Lua states matched the native baseline closely and exceeded the same-machine Hono Bun baseline on the tested inline, param, and echo routes.

The claim is limited to:

```text
- this machine
- this benchmark harness
- local loopback
- ReleaseFast builds
- fast_http_pool backend
- tested route shapes
```

## Recommended Short Claim

On macOS arm64 local loopback, Meteorite's experimental `fast_http_pool` backend with optimized hybrid Lua reached 192k req/s on an inline Lua route in a 60s strict run, while the same-machine Hono Bun inline baseline reached 158k req/s. These are local framework/runtime overhead benchmarks, not production throughput claims.

## Reproduce Latest Results

```bash
# Meteorite release-static
bench/run.sh \
  --target meteorite \
  --mode release-static \
  --backend fast_http \
  --fast-http-strategy pool \
  --duration 60s \
  --concurrency "1,8,32,128,256,512" \
  --strict-bench

# Meteorite release-hybrid optimized
bench/run.sh \
  --target meteorite \
  --mode release-hybrid \
  --hybrid-profile optimized \
  --backend fast_http \
  --fast-http-strategy pool \
  --duration 60s \
  --concurrency "1,8,32,128,256,512" \
  --strict-bench

# Hono Bun baseline
bench/run.sh \
  --target hono-bun \
  --duration 60s \
  --concurrency "1,8,32,128,256,512"

# Compare
python3 bench/compare.py \
  bench/results/latest-meteorite-release-static \
  bench/results/latest-meteorite-release-hybrid \
  bench/results/latest-hono-bun \
  > bench/results/latest-comparison.md
```

For the high-concurrency pressure run, use the same Meteorite configuration with concurrency levels `512,1024` and duration `120s`.

## Historical Results

<details>
<summary>Historical: std_http ceiling before fast_http_pool</summary>

Results below this heading are from earlier 15-second runs and are kept for reference only. They do not reflect the current optimized hybrid profile or the `fast_http_pool` backend.

## What was measured

| Run | Target | Mode / Runtime | Duration | Concurrency |
|---|---|---|---|---|
| 2026-06-19T00:12:04Z | Meteorite | release-static | 15 s | 1,8,32,128,256,512 |
| 2026-06-19T00:32:06Z | Meteorite | release-hybrid optimized | 15 s | 1,8,32,128,256,512 |
| 2026-06-19T00:46:51Z | Hono | Bun | 15 s | 1,8,32,128,256,512 |

All runs used the same route shapes, the same load generator (`oha v1.14.0`), the same host, and the same concurrency matrix. `wrk` was used as an independent cross-check; oha and wrk agreed within ~1.2x on health.

## Build metadata

| Field | Meteorite static | Meteorite hybrid | Hono Bun |
|---|---|---|---|
| Framework | meteorite | meteorite | hono |
| Runtime | native-zig | native-zig + Lua | bun |
| Mode | release-static | release-hybrid | n/a |
| Hybrid profile | default | optimized | n/a |
| Zig optimize | ReleaseFast | ReleaseFast | n/a |
| Backend | std.http | std.http | bun-serve |
| Lua runtime | no | yes | n/a |
| Binary file size | 482.6 KiB | 908.5 KiB | n/a |

## Trust checks

| Check | Meteorite static | Meteorite hybrid | Hono Bun |
|---|---|---|---|
| Zig optimize mode | ReleaseFast (not Debug) | ReleaseFast (not Debug) | n/a |
| Keep-alive reuse | on = 53.0k, off = 24.5k (53.8% separated) | on = 53.1k, off = 18.1k (66.0% separated) | on = 165.2k, off = 33.2k (79.9% separated) |
| oha / wrk agreement | ~1.19x | ~1.14x | ~1.11x |
| Native baseline | `plain-native` tracks other static routes | `plain-native` tracks hybrid static routes; inline Lua is 11–13% below | `plain-native` tracks other routes |
| Plateau | No — max ~55k, well above 20k | No — max ~54k, well above 20k | No — max ~169k, well above 20k |

## Peak throughput comparison

| Scenario | Meteorite static | Meteorite hybrid Lua | Hono Bun | Hybrid Lua vs Hono |
|---|---:|---:|---:|---:|
| /__bench/plain | 55,154 | 48,044 | 166,552 | 28.8% |
| /health | 54,931 | 48,044 | 169,235 | 28.4% |
| /users/123 | 53,981 | 48,044 | 157,468 | 30.5% |
| /devices/router_01 | 54,541 | 48,044 | 155,624 | 30.9% |
| /files/readme-01.txt | 53,666 | 48,044 | 155,369 | 30.9% |
| POST /echo (small) | 54,126 | 48,044 | 132,256 | 36.3% |
| POST /echo (8 KiB) | 48,053 | 48,044 | 100,974 | 47.6% |
| /hybrid-inline | 54,121 | 48,044 | 166,794 | 28.8% |

Latencies reported are **p50/p95/p99 at the concurrency where peak req/s occurs**, not mixed minima. See [`latest-comparison.md`](bench/results/latest-comparison.md) for full per-concurrency tables.

## Interpretation

1. **Meteorite release-static is optimized and consistent.** All static routes (including pattern-matched routes) cluster around the same ~55k req/s ceiling. `plain-native` matches them, so the bottleneck is not route-matcher or param-validation cost.
2. **Including the Lua runtime has negligible effect on static routes.** Hybrid static_zig routes are within 1–2% of release-static, so the runtime's global presence is not the bottleneck.
3. **Inline Lua adds ~11–13% overhead versus the same route as static Zig.** The optimized hybrid profile preloads and caches the Lua handler once, so the cost is the bridge call itself, not source lifting or file I/O.
4. **The dominant gap is the backend/server ceiling.** Hono on Bun reaches ~167k req/s on the same machine, while Meteorite's `plain-native` ceiling is ~55k req/s. That is roughly a 3x difference at the HTTP layer, before any routing or handler logic.
5. **Until the `/__bench/plain` ceiling is competitive with Hono Bun, optimizing the router or Lua bridge further will not close the overall gap.** The next optimization target is the std.http server shape (or an alternative backend), not routing or the Lua bridge.

## Gate checks

| Gate | Status |
|---|---|
| Gate 1: Meteorite static `/__bench/plain` ≥ Hono Bun `/__bench/plain` − 10% | **Failed** (33%) |
| Gate 2: Hybrid static_zig route within 15% of release-static static_zig route | **Passed** (~98%) |
| Gate 3: Hybrid inline Lua trivial route ≥ 50% of Hono Bun trivial route | **Failed** (~29%) |
| Gate 4: Hybrid typed-param close to hybrid trivial | **Passed** (~112%) |
| Gate 5: Hybrid echo-small within 20% of Hono Bun echo-small | **Failed** (~41%) |

The failed gates all trace back to Gate 1: the std.http/Zig backend ceiling is far below Bun serve. The Lua bridge itself is only ~11–13% slower than the equivalent static Zig route.

## Reproduce

See the [Reproduce Latest Results](#reproduce-latest-results) section above for the current commands.

## Environment

| Field | Value |
|---|---|
| OS/kernel | Darwin Maximos-MacBook-Pro.local 25.4.0 Darwin Kernel Version 25.4.0 arm64 |
| Zig version | 0.16.0 |
| Moon version | Moonstone v0.2.18 |
| Bun version | 1.3.14 |
| oha version | oha 1.14.0 |
| wrk version | wrk 4.2.0 [kqueue] |

## Backend-Ceiling Sprint Additions

The backend investigation now includes dedicated framework-bypass and backend-bypass probes:

- `GET /__bench/raw` bypasses Meteorite route response abstraction and writes a precomputed `HTTP/1.1 200 OK` response through the selected backend.
- `GET /__bench/counters` reports backend counters: `accepted_connections`, `requests_served`, `requests_per_connection`, `keepalive_reuse_count`, `connection_close_count`, `bytes_read`, and `bytes_written`.
- `bench/run.sh --backend std_http|fast_http` selects the backend at build time. `std_http` remains the default; `fast_http` is experimental and only implements the narrow benchmark/server subset: GET/POST, `Content-Length`, keep-alive, small fixed responses, and echo bodies.
- Benchmark runs now collect macOS artifacts when available: `sample $PID 5` into `sample-5s.txt`, plus `ps` snapshots in `ps-before.txt` and `ps-after.txt`.

### std_http Hot-Path Audit

- Per-request allocation: the Meteorite app still creates a fixed-buffer arena per request; no heap allocator is used for `/__bench/plain` or `/__bench/raw`. `std.http` parsing uses the connection buffers already owned by the backend request.
- Writes per small response: `std_http.respondText(200, "ok")` now uses the same precomputed raw response as `/__bench/raw`, with a single `writeAll` followed by one `flush`.
- Flush behavior: both `std_http` raw responses and `fast_http` responses flush once per response. This keeps correctness obvious while exposing whether `std.http` parsing/connection-loop overhead is the ceiling.
- Header formatting: `std_http` avoids dynamic header formatting for the hot `200 ok` text response. Other small text responses use a stack buffer and known `content-length`.
- Connection loop overhead: counters expose accepted connections, keep-alive reuse, and close counts so benchmark results can distinguish backend/parser ceilings from load-generator or keep-alive failures.

### Comparison Matrix

Use these runs to isolate the ceiling:

```bash
bench/run.sh --target meteorite --mode release-static --backend std_http --duration 30s --concurrency "1,8,32,128,256,512" --strict-bench
bench/run.sh --target meteorite --mode release-static --backend fast_http --duration 30s --concurrency "1,8,32,128,256,512" --strict-bench
bench/run.sh --target hono-bun --duration 30s --concurrency "1,8,32,128,256,512"
```

Then compare the resulting directories with:

```bash
python3 bench/compare.py \
  bench/results/<std-http-run> \
  bench/results/<fast-http-run> \
  bench/results/<hono-bun-run> \
  > bench/results/backend-ceiling-comparison.md
```

Interpretation guide:

- If `std_http /__bench/raw` remains near `std_http /__bench/plain`, Meteorite response abstraction is not the ceiling.
- If `fast_http /__bench/raw` is much faster than `std_http /__bench/raw`, `std.http` parsing/connection handling is the ceiling.
- If both backends plateau together and Hono Bun is also lower than expected, the load generator or machine is likely capped.
- If `fast_http /__bench/plain` crosses 120k req/s while `std_http` stays near 55k req/s, backend work should continue before optimizing router, DFA, or Lua bridge.

### Focused Probe Result

A short 5s local probe at concurrency 256 after this sprint showed:

| Target | Scenario | Req/s | Success |
|---|---|---:|---:|
| Meteorite `std_http` | `/__bench/plain` | 52,009 | 100% |
| Meteorite `std_http` | `/__bench/raw` | 52,894 | 100% |
| Meteorite `fast_http` threaded | `/__bench/plain` | 189,327 | 100% |
| Meteorite `fast_http` threaded | `/__bench/raw` | 189,487 | 100% |
| Hono Bun | `/__bench/plain` | 156,976 | 100% |

Conclusion: the 55k ceiling was not Meteorite response abstraction and not the load generator/machine. It was backend connection handling: the original accept loop served one keep-alive connection to completion before accepting and serving the rest. `fast_http` uses detached per-connection workers and raises `/__bench/plain` above the 120k target in the focused probe.

### Hybrid Mode Probe Result

Hybrid mode keeps the backend-ceiling win for static Zig routes when using `fast_http`. Because the Lua bridge owns a global `current_ctx` and the optimized profile uses a cached Lua state, Lua handler execution is protected by a `std.Io.Mutex`; this keeps threaded `fast_http` safe while allowing non-Lua routes to run concurrently.

Short 5s local probes at concurrency 256:

| Target | Scenario | Req/s | Success |
|---|---|---:|---:|
| Meteorite hybrid `std_http` optimized | `/__bench/plain` | 52,032 | 100% |
| Meteorite hybrid `std_http` optimized | `/health` | 51,987 | 99.98% |
| Meteorite hybrid `std_http` optimized | `/hybrid-inline` | 46,033 | 100% |
| Meteorite hybrid `fast_http` optimized | `/__bench/plain` | 188,397 | 100% |
| Meteorite hybrid `fast_http` optimized | `/health` | 188,515 | 100% |
| Meteorite hybrid `fast_http` optimized | `/hybrid-inline` | 114,987 | 100% |

Interpretation: hybrid static Zig routes are no longer capped at ~55k under `fast_http`. Inline Lua improves substantially too, but remains serialized through the Lua mutex until Meteorite grows per-worker Lua states or another concurrency-safe Lua execution model.

## Fast HTTP Validation Sprint

`fast_http` now has explicit strategy labels:

- `fast_http_threaded_probe`: the original high-throughput probe, using one detached worker thread per accepted connection. It is intentionally unbounded and is not presented as a production strategy.
- `fast_http_pool`: bounded worker-pool strategy. The main thread accepts sockets and enqueues them into a fixed-size queue. Workers default to `std.Thread.getCpuCount()` when `-Dfast-http-workers=0`. When the queue is full, the connection is closed and `dropped_connections` is incremented.

Build knobs:

```bash
zig build install-server \
  -Dmode=release-static \
  -Dbackend=fast_http \
  -Dfast-http-strategy=pool \
  -Dfast-http-workers=0 \
  -Dfast-http-queue=1024
```

Benchmark matrix:

```bash
bench/run-fast-http-matrix.sh
```

This runs:

1. `fast_http_threaded_probe` release-static
2. `fast_http_pool` release-static
3. `fast_http_threaded_probe` release-hybrid optimized
4. `fast_http_pool` release-hybrid optimized
5. Hono Bun

Use `RUN_STABILITY=1 bench/run-fast-http-matrix.sh` for the optional 5 minute pool stability run. The strict bounded-runtime check fails if configured pool workers spawn more threads than requested or if RSS grows beyond the current guardrail.

### Fast HTTP Counters

`/__bench/counters` now includes:

- backend identity: `backend`, `connection_strategy`, `bounded`
- connection/runtime: `active_connections`, `total_connections`, `threads_spawned`, `connection_errors`, `max_active_connections`
- traffic: `requests_served`, `requests_per_connection`, `bytes_read`, `bytes_written`
- pool pressure: `queue_depth`, `max_queue_depth`, `dropped_connections`

### Focused Strategy Probe

Short 5s local probes at concurrency 256 after the bounded-pool sprint:

| Target | Scenario | Req/s | Notes |
|---|---|---:|---|
| `fast_http_threaded_probe` static | `/__bench/plain` | 186,668 | unbounded thread-per-connection probe |
| `fast_http_threaded_probe` static | `/__bench/raw` | 188,604 | raw path still matches plain |
| `fast_http_pool` static, workers=4 | `/__bench/plain` | 139,715 | bounded, 4 workers |
| `fast_http_pool` static, workers=4 | `/__bench/raw` | 142,367 | bounded, 4 workers |
| `fast_http_pool` static, workers=CPU count | `/__bench/plain` | 198,665 | bounded default worker mode |
| `fast_http_pool` hybrid optimized, workers=4 | `/health` | 144,634 | static Zig route in hybrid binary |
| `fast_http_pool` hybrid optimized, workers=4 | `/hybrid-inline` | 118,145 | serialized Lua bridge, still >50% of Hono |
| Hono Bun | `/hybrid-inline` | 158,356 | same route shape as plain Hono |

These are focused probes, not headline benchmark claims. Headline claims should only use strict-bench matrix runs.

### Current Backend Positioning

`std_http` remains the correctness/default backend. It is documented as stable but still capped by the single-connection-loop shape measured earlier. `fast_http` is experimental and high-performance; `fast_http_pool` is the bounded candidate for further productionization, while `fast_http_threaded_probe` remains a diagnostic strategy only.

## Hybrid Ladder Attribution

The hybrid ladder adds focused routes for separating backend, static Zig, Lua call, response bridge, params, and body costs:

- `GET /__bench/plain-static` — release-static static Zig baseline.
- `GET /__bench/hybrid-zig` — static Zig route inside a hybrid binary.
- `GET /__bench/hybrid-inline` — inline Lua trivial return-string route.
- `GET /__bench/hybrid-inline-text-literal` — inline Lua `ctx:text("ok")` response bridge route.
- `GET /__bench/hybrid-inline-params/123` — inline Lua path-param materialization route.
- `POST /__bench/hybrid-inline-echo` — inline Lua body/echo route.

`bench/run-hybrid-ladder.sh` runs release-static, release-hybrid optimized, and Hono Bun, then writes `hybrid-ladder.md`. During full `bench/run.sh` runs, macOS captures `sample $PID 5` while applying load to `/__bench/hybrid-inline` and stores it as `sample-hybrid-inline-5s.txt`.

Metadata now records `handler_kind`, `requires_lua` through route analysis, plus runtime/build fields including `lua_state_strategy`, `hybrid_profile`, `connection_strategy`, and `fast_http_workers`.

### Per-thread Cached Lua State Prototype

The previous optimized hybrid bridge used a single cached Lua state protected by a mutex. The ladder strongly indicated that the remaining gap was the single Lua lock rather than router/DFA/backend cost, because hybrid static Zig routes were already high while inline Lua serialized through the bridge.

The optimized hybrid runtime now uses thread-local cached Lua state and handler refs (`lua_state_strategy = per_thread_cached_refs`). The bridge context pointers are thread-local too, so C callbacks no longer contend on global `current_ctx/current_vtable`.

Focused 5s probes at concurrency 256 with `fast_http_pool`, default CPU-count workers:

| Rung | Req/s | Attribution |
|---|---:|---|
| release-static `/__bench/plain-static` | 167,169 | static baseline probe |
| release-hybrid `/__bench/hybrid-zig` | 187,521 | backend + hybrid binary, no Lua |
| release-hybrid `/__bench/hybrid-inline` | 189,410 | inline Lua trivial, per-thread cached state |
| release-hybrid `/__bench/hybrid-inline-text-literal` | 182,748 | `ctx:text` response bridge cost is small |
| release-hybrid `/__bench/hybrid-inline-params/123` | 178,040 | params materialization cost is measurable but not dominant |
| release-hybrid `POST /__bench/hybrid-inline-echo` | 183,558 | body bridge cost is small for tiny bodies |
| Hono Bun `/__bench/hybrid-inline` | 158,398 | Hono equivalent |
| Hono Bun `/__bench/hybrid-inline-params/123` | 147,859 | Hono params equivalent |
| Hono Bun `POST /__bench/hybrid-inline-echo` | 122,653 | Hono echo equivalent |

Attribution: the former gap was primarily the single Lua lock. With per-thread cached Lua states, Lua function call overhead, `ctx:text`, params materialization, and tiny-body bridge costs are no longer the dominant ceiling in this focused probe. The acceptance target of 130k was met, and the 150k stretch was exceeded. Headline claims still require strict-bench ladder runs rather than these short probes.

</details>
