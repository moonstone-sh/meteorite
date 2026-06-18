# Meteorite Benchmark Harness

This directory contains a reproducible local benchmark harness for Meteorite. It builds the current Meteorite service, starts the generated native server, drives a fixed set of HTTP scenarios with `oha`, records memory samples, captures binary metadata, and generates a Markdown summary from raw machine-readable artifacts.

These benchmarks measure local framework/runtime overhead on a single machine. They are not a claim of real-world network throughput. Public benchmark claims should include CPU, OS/kernel, Zig version, Meteorite commit, build mode, backend, route scenario, concurrency, load generator, duration, binary size, RSS, and p95/p99 latency.

## What It Measures

- Throughput / requests per second
- p50 / p95 / p99 latency and max latency, parsed from `oha` JSON when available
- Success/error counts
- Memory usage over time via `bench/collect_memory.sh`
- Idle RSS, max RSS under load, and max thread count
- Binary size and optional section output from `size`
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
- `perf`: CPU counters on Linux, skipped if unavailable or permission denied
- `size`: binary section output, skipped if unavailable
- `file`, `stat`, `curl`, `python3`: used for metadata, readiness, and summary generation

## Run Benchmarks

From the Meteorite project root:

```bash
bench/run.sh --mode release-static
bench/run.sh --mode release-hybrid
bench/run.sh --duration 60s --concurrency "1,8,32,128,256,512,1024"
```

Defaults:

```text
mode:        release-static
duration:    30s
concurrency: 1,8,32,128,256,512
host:        127.0.0.1
port:        8080
binary:      dist/server
```

The harness writes timestamped result directories:

```text
bench/results/20260618T120000Z/
  env.json
  bench.json
  binary.json
  binary-sections.txt
  build.txt
  server.log
  memory.csv
  health-oha-c1.json
  echo-small-oha-c256.json
  perf-c256.txt
  summary.md
```

Raw outputs are intentionally kept. `summary.md` is generated from those files and should not be treated as the only source of benchmark data.

## Scenarios

The harness runs scenarios against routes from the fixture/root service when they exist:

| Scenario | Request | Purpose |
|---|---|---|
| `health` | `GET /health` | Static route overhead |
| `echo-small` | `POST /echo`, small text body | Small body read/write path |
| `echo-8k` | `POST /echo`, 8192-byte body | Body limit/copy/response overhead |
| `typed-param` | `GET /users/123` | Typed numeric param parse path |
| `pattern-param` | `GET /devices/router_01` | DFA-backed param matcher path |
| `file-pattern` | `GET /files/readme-01.txt` | Pattern with dot/dash classes |

If a route is unavailable or returns `404`, the raw `oha` result is still preserved and the summary marks unavailable metrics as `n/a` where it cannot parse them.

## Interpreting Results

High max-throughput numbers are useful for detecting regressions, but p95/p99 latency and error rate are usually more important. Compare runs only when environment metadata is comparable: same CPU, OS/kernel, Zig version, build mode, backend, duration, and concurrency matrix.

Localhost benchmarks remove most real network effects. They help isolate Meteorite framework/runtime overhead and generated route behavior, not internet performance, deployment quality, TLS overhead, reverse proxy behavior, or database latency.

## Files

- `run.sh`: orchestrates build, server lifecycle, load generation, memory sampling, and summary generation
- `collect_env.sh`: writes environment/tool metadata to JSON
- `collect_memory.sh`: samples RSS/VSZ/thread count while the server runs
- `summarize.py`: defensively parses raw artifacts and generates Markdown
- `wrk/echo.lua`: `wrk` POST echo helper
- `results/.gitkeep`: keeps the results directory in the repository
