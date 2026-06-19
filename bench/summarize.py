#!/usr/bin/env python3
import csv
import json
import math
import re
import sys
from pathlib import Path


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return {}


def find_metric(obj, names):
    if isinstance(obj, dict):
        for name in names:
            if name in obj:
                return obj[name]
        for value in obj.values():
            found = find_metric(value, names)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = find_metric(value, names)
            if found is not None:
                return found
    return None


def as_number(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        match = re.search(r"-?\d+(?:\.\d+)?", value.replace(",", ""))
        if match:
            try:
                return float(match.group(0))
            except ValueError:
                return None
    return None


def fmt(value, digits=2):
    if value is None:
        return "n/a"
    if isinstance(value, str):
        return value.strip() or "n/a"
    try:
        number = float(value)
    except Exception:
        return str(value)
    if math.isnan(number) or math.isinf(number):
        return "n/a"
    if abs(number) >= 1000:
        return f"{number:,.{digits}f}"
    if number == int(number):
        return str(int(number))
    return f"{number:.{digits}f}"


def fmt_bytes(value):
    number = as_number(value)
    if number is None:
        return "n/a"
    for unit in ["B", "KiB", "MiB", "GiB"]:
        if abs(number) < 1024 or unit == "GiB":
            return f"{number:.1f} {unit}"
        number /= 1024
    return f"{number:.1f} GiB"


def fmt_latency(value):
    number = as_number(value)
    if number is None:
        return "n/a"
    if number < 10:
        number *= 1000
    return f"{number:.3f} ms"


def latency_value(obj, percentile):
    names = [
        percentile,
        percentile.upper(),
        percentile.replace("p", "p_"),
        percentile.replace("p", "percentile"),
    ]
    value = find_metric(obj, names)
    if value is not None:
        return value
    percentiles = find_metric(obj, ["latencyPercentiles", "latency_percentiles", "percentiles"])
    if isinstance(percentiles, dict):
        for key in [percentile, percentile.upper(), percentile[1:], str(float(percentile[1:]))]:
            if key in percentiles:
                return percentiles[key]
    return None


def total_success(obj):
    direct = find_metric(obj, ["success", "successCount", "success_count"])
    if direct is not None:
        return direct
    status = find_metric(obj, ["statusCodeDistribution", "status_code_distribution", "status_codes"])
    if isinstance(status, dict):
        total = 0
        found = False
        for key, value in status.items():
            try:
                code = int(str(key).split()[0])
            except Exception:
                continue
            if 200 <= code < 400:
                number = as_number(value)
                if number is not None:
                    total += number
                    found = True
        if found:
            return total
    return None


def total_errors(obj, success):
    direct = find_metric(obj, ["error", "errors", "errorCount", "error_count", "failed", "failures"])
    if direct is not None:
        return direct
    total = find_metric(obj, ["total", "totalRequests", "total_requests", "requests"])
    total_number = as_number(total)
    success_number = as_number(success)
    if total_number is not None and success_number is not None:
        return max(0, total_number - success_number)
    status = find_metric(obj, ["statusCodeDistribution", "status_code_distribution", "status_codes"])
    if isinstance(status, dict):
        total_errors_value = 0
        found = False
        for key, value in status.items():
            try:
                code = int(str(key).split()[0])
            except Exception:
                continue
            if code >= 400:
                number = as_number(value)
                if number is not None:
                    total_errors_value += number
                    found = True
        if found:
            return total_errors_value
    return None


def parse_oha(path):
    obj = load_json(path)

    match_fixed = re.match(r"(.+)-oha-c(\d+)-q(\d+)\.json$", path.name)
    if match_fixed:
        scenario = match_fixed.group(1)
        concurrency = match_fixed.group(2)
        qps = match_fixed.group(3)
        is_fixed = True
    else:
        match = re.match(r"(.+)-oha-c(\d+)\.json$", path.name)
        scenario = match.group(1) if match else path.stem
        concurrency = match.group(2) if match else "n/a"
        qps = None
        is_fixed = False

    summary = obj.get("summary") if isinstance(obj, dict) else None
    rps = None
    if isinstance(summary, dict):
        rps = find_metric(summary, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"])
    if rps is None:
        rps = find_metric(obj, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"])
    success = total_success(obj)
    errors = total_errors(obj, success)
    return {
        "scenario": scenario,
        "concurrency": concurrency,
        "qps": qps,
        "is_fixed": is_fixed,
        "rps": rps,
        "p50": latency_value(obj, "p50"),
        "p95": latency_value(obj, "p95"),
        "p99": latency_value(obj, "p99"),
        "max": find_metric(obj, ["max", "slowest", "maxLatency", "max_latency"]),
        "success": success,
        "errors": errors,
    }


def parse_memory(path):
    idle = None
    max_rss = None
    max_threads = None
    try:
        with open(path, newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            for index, row in enumerate(reader):
                rss = as_number(row.get("rss_kb"))
                threads = as_number(row.get("threads"))
                if index == 0:
                    idle = rss
                if rss is not None:
                    max_rss = rss if max_rss is None else max(max_rss, rss)
                if threads is not None:
                    max_threads = threads if max_threads is None else max(max_threads, threads)
    except FileNotFoundError:
        pass
    return idle, max_rss, max_threads


def parse_size_sections(text, os_name):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) < 2:
        return "unknown", {}

    if os_name == "Darwin":
        return "darwin", {"raw": text.strip()}

    headers = re.split(r"\s+", lines[0])
    values = re.split(r"\s+", lines[1])
    if len(headers) != len(values):
        return "unknown", {}

    if all(h in headers for h in ["text", "data", "bss"]):
        out = {}
        for key, value in zip(headers, values):
            if key in ["text", "data", "bss", "dec", "hex"]:
                out[key] = value
        return "linux", out

    if "__TEXT" in headers and "__DATA" in headers:
        out = {}
        for key, value in zip(headers, values):
            out[key] = value
        return "darwin", out

    return "unknown", {}


def table_row(values):
    return "| " + " | ".join(str(value).replace("\n", "<br>") for value in values) + " |"


def scan_routes_zon(text):
    routes = {}
    current_route = {}
    in_handler = False
    in_runtime = False
    handler_type = None

    for line in text.splitlines():
        trimmed = line.strip()
        indent = len(line) - len(line.lstrip(" "))

        if indent == 8:
            id_match = re.match(r'\.id\s*=\s*"([^"]+)"', trimmed)
            if id_match:
                current_route["id"] = id_match.group(1)
            path_match = re.match(r'\.raw_path\s*=\s*"([^"]+)"', trimmed)
            if path_match:
                current_route["raw_path"] = path_match.group(1)
            if trimmed.startswith('.handler ='):
                in_handler = True
                handler_type = None
                continue
            if trimmed.startswith('.runtime ='):
                in_runtime = True
                continue
            if in_handler and trimmed.startswith('.'):
                if handler_type:
                    current_route["handler_type"] = handler_type
                in_handler = False
            if in_runtime and trimmed.startswith('.'):
                in_runtime = False

        if in_handler and indent == 12:
            type_match = re.match(r'\.([a-zA-Z_0-9]+)\s*=\s*\.{', trimmed)
            if type_match:
                handler_type = type_match.group(1)

        if in_runtime and indent == 12:
            req_lua_match = re.match(r'\.requires_lua\s*=\s*(true|false)', trimmed)
            if req_lua_match:
                current_route["requires_lua"] = req_lua_match.group(1) == "true"

        if indent == 4 and trimmed == '},':
            if in_handler and handler_type:
                current_route["handler_type"] = handler_type
                in_handler = False
            if "raw_path" in current_route:
                routes[current_route["raw_path"]] = current_route
            current_route = {}
            in_handler = False
            in_runtime = False
            handler_type = None

    return routes


SCENARIO_TO_PATH = {
    "plain-native": "/__bench/plain",
    "raw-native": "/__bench/raw",
    "plain-static": "/__bench/plain-static",
    "hybrid-zig": "/__bench/hybrid-zig",
    "hybrid-inline-bench": "/__bench/hybrid-inline",
    "hybrid-inline-text-literal": "/__bench/hybrid-inline-text-literal",
    "hybrid-inline-params": "/__bench/hybrid-inline-params/:id",
    "hybrid-inline-echo": "/__bench/hybrid-inline-echo",
    "health": "/health",
    "typed-param": "/users/:id",
    "pattern-param": "/devices/:device_id",
    "file-pattern": "/files/:name",
    "echo-small": "/echo",
    "echo-8k": "/echo",
    "hybrid-inline": "/hybrid-inline",
    "health-fixed": "/health",
}


def get_handler_kind(scenario, build_mode, routes, target, framework):
    if target.startswith("hono") or framework == "hono":
        return "hono_handler", False

    is_static_mode = "static" in build_mode
    path = SCENARIO_TO_PATH.get(scenario)
    route = routes.get(path) if path and routes else None
    handler_type = route.get("handler_type") if route else None
    requires_lua = route.get("requires_lua") if route else None

    if handler_type == "inline_lua":
        return "hybrid_inline_lua", bool(requires_lua)
    if handler_type == "lua_file":
        return "lua_file", True
    if handler_type == "zig_file":
        return "hybrid_zig", bool(requires_lua)
    if handler_type == "zig_symbol":
        return "static_zig", bool(requires_lua) if requires_lua is not None else False

    if is_static_mode:
        return "static_zig", False
    return "hybrid_zig", False


def parse_wrk_throughput(path):
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    match = re.search(r"Requests/sec:\s+([\d,.]+)", text)
    if match:
        return as_number(match.group(1))
    return None


def parse_keepalive_rps(path):
    obj = load_json(path)
    summary = obj.get("summary") if isinstance(obj, dict) else None
    if isinstance(summary, dict):
        return as_number(find_metric(summary, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"]))
    return as_number(find_metric(obj, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"]))


def main():
    if len(sys.argv) != 2:
        print("usage: summarize.py RESULT_DIR", file=sys.stderr)
        return 2
    result_dir = Path(sys.argv[1])
    env = load_json(result_dir / "env.json")
    binary = load_json(result_dir / "binary.json")
    bench = load_json(result_dir / "bench.json")
    build_info = load_json(result_dir / "build-info.json")

    target = bench.get("target", "meteorite")
    framework = build_info.get("framework", "meteorite" if target == "meteorite" else "hono")
    runtime = build_info.get("runtime", "n/a")
    hybrid_profile = build_info.get("hybrid_profile", bench.get("hybrid_profile", "n/a"))

    routes_zon_path = result_dir / "routes.zon"
    routes = {}
    if routes_zon_path.exists():
        try:
            routes = scan_routes_zon(routes_zon_path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            pass

    os_name = "Darwin" if "Darwin" in env.get("uname", "") else "Linux"
    binary_sections_file = result_dir / "binary-sections.txt"
    binary_size_raw_file = result_dir / "binary-size-raw.txt"
    if os_name == "Darwin" and binary_size_raw_file.exists():
        binary_sections_text = binary_size_raw_file.read_text(encoding="utf-8", errors="replace")
    else:
        binary_sections_text = binary_sections_file.read_text(encoding="utf-8", errors="replace") if binary_sections_file.exists() else ""
    parser_type, sections = parse_size_sections(binary_sections_text, os_name)

    idle_rss, max_rss, max_threads = parse_memory(result_dir / "memory.csv")

    oha_rows = [parse_oha(path) for path in sorted(result_dir.glob("*-oha-c*.json"))]
    build_mode = bench.get("mode", "release-static")

    for row in oha_rows:
        kind, requires_lua = get_handler_kind(row["scenario"], build_mode, routes, target, framework)
        row["handler_kind"] = kind
        row["route_runtime_requires_lua"] = requires_lua
        row["build_mode"] = build_mode

    def row_sort_key(row):
        scenario = row["scenario"]
        try:
            concurrency = int(row["concurrency"])
        except (ValueError, TypeError):
            concurrency = 999999
        return (scenario, concurrency)

    throughput_rows = [r for r in oha_rows if not r["is_fixed"]]
    fixed_rows = [r for r in oha_rows if r["is_fixed"]]
    throughput_rows.sort(key=row_sort_key)
    fixed_rows.sort(key=row_sort_key)

    title_framework = framework.capitalize() if framework else "Benchmark"
    print(f"# {title_framework} Benchmark Summary")
    print()
    print("These benchmarks measure local framework/runtime overhead on a single machine. They are not a claim of real-world network throughput.")
    print()

    warnings = []
    if env.get("git_status"):
        warnings.append("Git working directory has uncommitted changes (git dirty).")
    if not env.get("wrk_version"):
        warnings.append("`wrk` benchmark tool is missing from PATH; no independent load-generator cross-check.")
    if not env.get("perf_version"):
        warnings.append("`perf` tool is missing; CPU counters were not collected.")

    # Build metadata diagnostics
    if build_info and target == "meteorite":
        reported_mode = build_info.get("meteorite_mode", build_mode)
        zig_optimize = build_info.get("zig_optimize", "n/a")
        if reported_mode != build_mode:
            warnings.append(f"Harness mode is {build_mode} but server reports {reported_mode}.")
        if "static" in build_mode and zig_optimize == "Debug":
            warnings.append("⚠️ Meteorite mode is release-static but Zig optimize mode is Debug. The binary is not release-optimized.")
        if "static" in build_mode and build_info.get("lua_runtime"):
            warnings.append("⚠️ Meteorite mode is release-static but server reports lua_runtime=true.")
        if "hybrid" in build_mode and not build_info.get("lua_runtime"):
            warnings.append("⚠️ Meteorite mode is release-hybrid but server reports lua_runtime=false.")

    # Keep-alive smoke diagnostic
    ka_on = parse_keepalive_rps(result_dir / "keepalive-on-smoke.json")
    ka_off = parse_keepalive_rps(result_dir / "keepalive-off-smoke.json")
    if ka_on is not None and ka_off is not None and ka_on > 0:
        diff = abs(ka_on - ka_off) / ka_on
        if diff <= 0.10:
            warnings.append("⚠️ keep-alive on/off produced similar throughput; server or client may not be reusing connections.")

    # wrk/oha disagreement diagnostic
    health_wrk_rps = parse_wrk_throughput(result_dir / "wrk-health-c256.txt")
    health_oha_rps = None
    for row in oha_rows:
        if row["scenario"] == "health" and row["concurrency"] == "256" and not row["is_fixed"]:
            health_oha_rps = as_number(row["rps"])
            break
    if health_wrk_rps is not None and health_oha_rps is not None and health_oha_rps > 0:
        ratio = max(health_wrk_rps, health_oha_rps) / min(health_wrk_rps, health_oha_rps)
        if ratio > 2.0:
            warnings.append("⚠️ oha/wrk disagree by >2x; benchmark may be load-generator limited.")

    # Memory sampler diagnostic
    if idle_rss is None or max_rss is None:
        warnings.append("Memory sampling was degraded or unavailable (some metrics are n/a).")

    # Latency spike diagnostic
    has_spikes = False
    for row in oha_rows:
        max_val = as_number(row["max"])
        p99_val = as_number(row["p99"])
        if max_val is not None and p99_val is not None and max_val > 10 * p99_val:
            has_spikes = True
            break
    if has_spikes:
        warnings.append("High max latency spikes detected (max latency is more than 10x p99 latency).")

    # Plateau diagnostic
    peak_by_scenario = {}
    for row in throughput_rows:
        scen = row["scenario"]
        rps = as_number(row["rps"])
        if rps is None:
            continue
        if scen not in peak_by_scenario or rps > peak_by_scenario[scen]:
            peak_by_scenario[scen] = rps
    if len(peak_by_scenario) >= 2:
        peaks = list(peak_by_scenario.values())
        max_peak = max(peaks)
        min_peak = min(peaks)
        if max_peak > 0 and (max_peak - min_peak) / max_peak <= 0.15 and max_peak < 20000:
            warnings.append("⚠️ All route scenarios plateau at similar throughput. This likely indicates a backend, build-mode, keep-alive, or load-generator bottleneck rather than route matcher cost.")

    if warnings:
        print("## Warnings")
        print()
        for w in warnings:
            print(f"- {w}")
        print()

    print("## Run Metadata")
    print()
    print("| Field | Value |")
    print("|---|---|")
    metadata = [
        ("Timestamp", env.get("timestamp", "n/a")),
        ("Git commit", env.get("git_commit", "n/a")),
        ("Git dirty", "yes" if env.get("git_status") else "no"),
        ("Target", target),
        ("Framework", framework),
        ("Runtime", runtime),
        ("Meteorite mode", build_info.get("meteorite_mode", bench.get("mode", "n/a"))),
        ("Hybrid profile", hybrid_profile),
        ("Lua state strategy", build_info.get("lua_state_strategy", "n/a")),
        ("Zig optimize", build_info.get("zig_optimize", "n/a")),
        ("Target arch", build_info.get("target", "n/a")),
        ("Backend", build_info.get("backend", bench.get("backend", "n/a"))),
        ("Connection strategy", build_info.get("connection_strategy", bench.get("fast_http_strategy", "n/a"))),
        ("Bounded backend", "yes" if build_info.get("bounded") else "no"),
        ("fast_http workers", build_info.get("fast_http_workers", bench.get("fast_http_workers", "n/a"))),
        ("fast_http queue", build_info.get("fast_http_queue", bench.get("fast_http_queue", "n/a"))),
        ("Lua runtime", "yes" if build_info.get("lua_runtime") else "no"),
        ("Keepalive", bench.get("keepalive", "n/a")),
        ("Target QPS", bench.get("qps", "n/a")),
        ("Host", f"{bench.get('host', 'n/a')}:{bench.get('port', 'n/a')}"),
        ("Duration", bench.get("duration", "n/a")),
        ("Concurrency", bench.get("concurrency", "n/a")),
        ("OS/kernel", env.get("uname", "n/a")),
        ("Zig version", env.get("zig_version", "n/a")),
        ("Moon version", env.get("moon_version", "n/a")),
        ("oha version", env.get("oha_version", "n/a")),
        ("wrk version", env.get("wrk_version", "n/a")),
    ]
    for key, value in metadata:
        print(table_row([key, value or "n/a"]))

    counters = load_json(result_dir / "backend-counters.json")
    if counters:
        print()
        print("## Backend Counters")
        print()
        print("| Counter | Value |")
        print("|---|---:|")
        for key in ["connection_strategy", "bounded", "active_connections", "total_connections", "accepted_connections", "threads_spawned", "requests_served", "requests_per_connection", "keepalive_reuse_count", "connection_close_count", "bytes_read", "bytes_written", "connection_errors", "max_active_connections", "queue_depth", "max_queue_depth", "dropped_connections"]:
            print(table_row([key, fmt(counters.get(key), 0)]))

    print()
    print("## Binary")
    print()
    print("| Metric | Value |")
    print("|---|---:|")
    print(table_row(["File size", fmt_bytes(binary.get("bytes"))]))
    file_size_path = result_dir / "binary-file-size.txt"
    if file_size_path.exists():
        print(table_row(["File size (raw)", file_size_path.read_text(encoding="utf-8", errors="replace").strip() + " bytes"]))

    if parser_type == "linux":
        for key in ["text", "data", "bss", "dec", "hex"]:
            if key in sections:
                print(table_row([key, sections[key]]))
    elif parser_type == "darwin":
        print(table_row(["Mach-O size output", "see binary-size-raw.txt"]))

    if binary.get("file"):
        print(table_row(["file", binary.get("file")]))

    if parser_type == "unknown" and binary_sections_text.strip():
        print()
        print("Raw `size` output:")
        print("```text")
        print(binary_sections_text.strip())
        print("```")

    # Only print the throughput section matching the actual build mode.
    if target.startswith("hono"):
        section_title = f"Throughput and Latency ({framework} {runtime})"
    else:
        section_title = f"Throughput and Latency ({build_mode})"
    print()
    print(f"## {section_title}")
    print()
    print("| Scenario | Concurrency | Handler Kind | Requires Lua | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Success | Errors |")
    print("|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    if not throughput_rows:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for row in throughput_rows:
        print(table_row([
            row["scenario"], row["concurrency"], row["handler_kind"],
            "yes" if row["route_runtime_requires_lua"] else "no",
            fmt(row["rps"]), fmt_latency(row["p50"]), fmt_latency(row["p95"]),
            fmt_latency(row["p99"]), fmt_latency(row["max"]), fmt(row["success"], 0), fmt(row["errors"], 0),
        ]))

    print()
    print("## Fixed-Rate Latency Runs")
    print()
    print("| Scenario | Concurrency | Target QPS | Handler Kind | Requires Lua | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Success | Errors |")
    print("|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
    if not fixed_rows:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for row in fixed_rows:
        print(table_row([
            row["scenario"], row["concurrency"], row["qps"], row["handler_kind"],
            "yes" if row["route_runtime_requires_lua"] else "no",
            fmt(row["rps"]), fmt_latency(row["p50"]), fmt_latency(row["p95"]),
            fmt_latency(row["p99"]), fmt_latency(row["max"]), fmt(row["success"], 0), fmt(row["errors"], 0),
        ]))

    print()
    print("## Peak Summary")
    print()
    print("| Mode | Scenario | Peak Req/s | Peak Concurrency | p50 at Peak | p95 at Peak | p99 at Peak | Best p99 | Best p99 Concurrency |")
    print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
    groups = {}
    for row in oha_rows:
        if target.startswith("hono"):
            mode_label = f"{framework}-{runtime}"
        else:
            mode_label = row["build_mode"]
        row["mode_label"] = mode_label
        key = (mode_label, row["scenario"])
        if key not in groups:
            groups[key] = []
        groups[key].append(row)

    if not groups:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for (b_mode, scen), rows in sorted(groups.items()):
        peak_row = max(rows, key=lambda r: as_number(r["rps"]) or 0)
        best_p99_row = min(rows, key=lambda r: as_number(r["p99"]) or float("inf"))

        peak_rps_val = peak_row["rps"]
        peak_rps_c = peak_row["concurrency"] + (f" (QPS: {peak_row['qps']})" if peak_row.get("is_fixed") else "")
        best_p99_c = best_p99_row["concurrency"] + (f" (QPS: {best_p99_row['qps']})" if best_p99_row.get("is_fixed") else "")

        print(table_row([
            mode_label, scen, fmt(peak_rps_val), peak_rps_c,
            fmt_latency(peak_row["p50"]), fmt_latency(peak_row["p95"]), fmt_latency(peak_row["p99"]),
            fmt_latency(best_p99_row["p99"]), best_p99_c
        ]))

    print()
    print("## Memory")
    print()
    print("| Metric | Value |")
    print("|---|---:|")
    print(table_row(["Idle RSS KB", fmt(idle_rss, 0)]))
    print(table_row(["Max RSS KB", fmt(max_rss, 0)]))
    if max_threads is None:
        print(table_row(["Max threads", "n/a (Thread count unavailable on Darwin sampler.)"]))
    else:
        print(table_row(["Max threads", fmt(max_threads, 0)]))

    perf = result_dir / "perf-c256.txt"
    if perf.exists():
        print()
        print("## CPU Counters")
        print()
        print("```text")
        print(perf.read_text(encoding="utf-8", errors="replace").strip())
        print("```")

    print()
    print("## Raw Artifacts")
    print()
    print("Raw outputs are in this directory.")


if __name__ == "__main__":
    raise SystemExit(main())
