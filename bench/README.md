# Meteorite Benchmark Harness

This directory contains a reproducible local benchmark harness for Meteorite. It builds the current Meteorite service, starts the generated native server, drives a fixed set of HTTP scenarios with `oha`, records memory samples, captures binary metadata, and generates a Markdown summary from raw machine-readable artifacts.

Benchmarks use the dedicated `fixtures/apps/bench-service` fixture. Keep `/__bench/*` routes and Lua-state stress routes there so showcase and acceptance fixtures stay focused.

These benchmarks measure local framework/runtime overhead on a single machine. They are not a claim of real-world network throughput. Public benchmark claims should include CPU, OS/kernel, Zig version, Meteorite commit, build mode, backend, route scenario, concurrency, load generator, duration, binary size, RSS, and p95/p99 latency.

## What It Measures

- Throughput / requests per second
- p50 / p95 / p99 latency and max latency, parsed from `oha` JSON when available
- Success/error counts
- Memory usage over time via `bench/collect_memory.sh`
- Idle RSS, max RSS under load, and max thread count
- Binary file size and optional section output from `size`
- Build metadata (`zig_optimize`, target, backend, router dispatch, Meteorite mode, Lua runtime) from `GET /__bench/meta`
- Keep-alive behavior sanity check (`oha` with keep-alive on vs. off)
- Independent load-generator cross-check with `wrk` when installed
- Optional CPU counters from `perf stat`
- Benchmark environment metadata in `env.json`

## Required Tool

`oha` is required because it emits JSON used by `summary.md`.

Examples:

```bash
# macOS, if using Homebrew
brew install oha

# Linux, via Cargo
cargo install oha
```

## Optional Tools

- `wrk`: secondary sanity checks, skipped if unavailable
- `perf`: CPU counters on Linux, skipped if unavailable
- `size`: binary section output, skipped if unavailable
- `file`, `stat`, `curl`, `python3`: used for metadata, readiness, and summary generation

## Run Benchmarks

From the Meteorite project root:

```bash
# Default smoke-sized run through Moonstone scripts
moon run bench
moon run bench:matrix
moon run bench:hybrid
moon run bench:lua-stability

# Trustworthy, publishable run (fails on Debug build or keepalive mismatch)
bench/run.sh --mode release-static --strict-bench

bench/run.sh --mode release-hybrid
bench/run.sh --duration 60s --concurrency "1,8,32,128,256,512,1024" --strict-bench

# Router dispatch A/B comparison: old full scan vs generated per-method buckets
bench/run.sh --mode release-static --router-dispatch legacy_scan --out bench/results/router-legacy
bench/run.sh --mode release-static --router-dispatch method_buckets --out bench/results/router-method-buckets
bench/run.sh --mode release-static --router-dispatch static_fast_path --out bench/results/router-static-fast-path
bench/run.sh --mode release-static --router-dispatch param_matchers --out bench/results/router-param-matchers
python3 bench/compare.py bench/results/router-legacy bench/results/router-method-buckets bench/results/router-static-fast-path bench/results/router-param-matchers
```

Defaults:

```text
mode:        release-static (release-static maps to Zig ReleaseFast)
duration:    30s
concurrency: 1,8,32,128,256,512
host:        127.0.0.1
port:        8080
binary:      dist/server
router:      method_buckets
strict:      off
```

The harness writes timestamped result directories:

```text
bench/results/20260618T120000Z/
  env.json
  bench.json
  build-info.json
  binary.json
  binary-file-size.txt
  binary-sections.txt          # Linux GNU size output
  binary-size-raw.txt          # Darwin size -m output
  build.txt
  curl-health.txt
  keepalive-on-smoke.json
  keepalive-off-smoke.json
  server.log
  memory.csv
  plain-native-oha-c1.json
  health-oha-c256.json
  wrk-health-c256.txt
  perf-c256.txt
  summary.md
```

Raw outputs are intentionally kept. `summary.md` is generated from those files and should not be treated as the only source of benchmark data.

## Scenarios

| Scenario | Request | Handler Kind | Purpose |
|---|---|---|---|
| `plain-native` | `GET /__bench/plain` | static Zig | Server/backend ceiling baseline |
| `health` | `GET /health` | static Zig | Static route overhead |
| `echo-small` | `POST /echo`, small text body | static Zig | Small body read/write path |
| `echo-8k` | `POST /echo`, 8192-byte body | static Zig | Body limit/copy/response overhead |
| `typed-param` | `GET /users/123` | static Zig | Typed numeric param parse path |
| `pattern-param` | `GET /devices/router_01` | static Zig | DFA-backed param matcher path |
| `file-pattern` | `GET /files/readme-01.txt` | static Zig | Pattern with dot/dash classes |
| `hybrid-inline` | `GET /hybrid-inline` | release-static: static Zig; release-hybrid: inline Lua | Hybrid inline-Lua overhead |

If a route is unavailable or returns `404`, the raw `oha` result is still preserved and the summary marks unavailable metrics as `n/a` where it cannot parse them.

## Interpreting Results

High max-throughput numbers are useful for detecting regressions, but p95/p99 latency and error rate are usually more important. Compare runs only when environment metadata is comparable: same CPU, OS/kernel, Zig version, build mode, backend, duration, and concurrency matrix.

Localhost benchmarks remove most real network effects. They help isolate Meteorite framework/runtime overhead and generated route behavior, not internet performance, deployment quality, TLS overhead, reverse proxy behavior, or database latency.

The summary emits warnings for suspicious conditions:

- Zig `Debug` optimize mode when the harness mode is `release-static`.
- Keep-alive on/off producing similar throughput.
- `oha` and `wrk` disagreeing by more than 2x.
- All scenarios plateauing at similar low throughput (suggesting a build, keep-alive, or load-generator bottleneck).

Use `--strict-bench` to turn the Debug and keepalive checks into hard failures.
Use `--strict-bench-fail-dirty` to also fail when the git working directory is dirty.

## Files

- `run.sh`: orchestrates build, server lifecycle, load generation, memory sampling, and summary generation
- `collect_env.sh`: writes environment/tool metadata to JSON
- `collect_memory.sh`: samples RSS/VSZ/thread count while the server runs
- `summarize.py`: defensively parses raw artifacts and generates Markdown
- `wrk/echo.lua`: `wrk` POST echo helper
- `results/.gitkeep`: keeps the results directory in the repository
