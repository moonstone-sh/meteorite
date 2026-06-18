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
    
    # Match fixed-rate: r"(.+)-oha-c(\d+)-q(\d+)\.json$"
    # Match normal: r"(.+)-oha-c(\d+)\.json$"
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


def parse_size_sections(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) < 2:
        return "unknown", {}
    
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
    routes = []
    current_route = {}
    in_handler = False
    handler_type = None
    
    for line in text.splitlines():
        trimmed = line.strip()
        indent = len(line) - len(line.lstrip(' '))
        
        # Match .id = "..." at indent 8
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
                
            # Any other field at indent 8 ends the handler block
            if in_handler and trimmed.startswith('.'):
                if handler_type:
                    current_route["handler_type"] = handler_type
                in_handler = False
                
        if in_handler and indent == 12:
            # Check for handler type inside .handler
            type_match = re.match(r'\.([a-zA-Z_0-9]+)\s*=\s*\.{', trimmed)
            if type_match:
                handler_type = type_match.group(1)
                
        # If we see a line like `    },` (indent 4) and we have a route, save it
        if indent == 4 and trimmed == '},':
            if in_handler and handler_type:
                current_route["handler_type"] = handler_type
                in_handler = False
            if "raw_path" in current_route:
                routes.append(current_route)
            current_route = {}
            
    return routes


SCENARIO_TO_PATH = {
    "health": "/health",
    "typed-param": "/users/:id",
    "pattern-param": "/devices/:device_id",
    "file-pattern": "/files/:name",
    "echo-small": "/echo",
    "echo-8k": "/echo",
    "health-fixed": "/health",
}


def get_handler_kind(scenario, build_mode, routes):
    is_static = "static" in build_mode
    if is_static:
        return "static_zig"
        
    path = SCENARIO_TO_PATH.get(scenario)
    handler_type = None
    if path and routes:
        for r in routes:
            if r.get("raw_path") == path:
                handler_type = r.get("handler_type")
                break
                
    if handler_type == "zig_symbol" or handler_type == "zig_file":
        return "hybrid_zig"
    elif handler_type == "inline_lua":
        return "hybrid_inline_lua"
    elif handler_type == "lua_file":
        return "lua_file"
        
    return "hybrid_zig"


def main():
    if len(sys.argv) != 2:
        print("usage: summarize.py RESULT_DIR", file=sys.stderr)
        return 2
    result_dir = Path(sys.argv[1])
    env = load_json(result_dir / "env.json")
    binary = load_json(result_dir / "binary.json")
    bench = load_json(result_dir / "bench.json")
    
    # Load routes.zon if available
    routes_zon_path = result_dir / "routes.zon"
    routes = []
    if routes_zon_path.exists():
        try:
            routes = scan_routes_zon(routes_zon_path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            pass
            
    binary_sections_file = result_dir / "binary-sections.txt"
    binary_sections_text = binary_sections_file.read_text(encoding="utf-8", errors="replace") if binary_sections_file.exists() else ""
    parser_type, sections = parse_size_sections(binary_sections_text)
    
    idle_rss, max_rss, max_threads = parse_memory(result_dir / "memory.csv")
    
    # Parse all oha rows
    oha_rows = [parse_oha(path) for path in sorted(result_dir.glob("*-oha-c*.json"))]
    build_mode = bench.get("mode", "release-static")
    
    for row in oha_rows:
        row["handler_kind"] = get_handler_kind(row["scenario"], build_mode, routes)
        row["build_mode"] = build_mode
        
    # Sort key: scenario asc, concurrency numeric asc
    def row_sort_key(row):
        scenario = row["scenario"]
        try:
            concurrency = int(row["concurrency"])
        except ValueError:
            concurrency = 999999
        return (scenario, concurrency)
        
    # Split throughput and fixed-rate runs
    throughput_rows = [r for r in oha_rows if not r["is_fixed"]]
    fixed_rows = [r for r in oha_rows if r["is_fixed"]]
    
    static_rows = [r for r in throughput_rows if "static" in r["build_mode"]]
    hybrid_rows = [r for r in throughput_rows if "hybrid" in r["build_mode"]]
    
    static_rows.sort(key=row_sort_key)
    hybrid_rows.sort(key=row_sort_key)
    fixed_rows.sort(key=row_sort_key)
    
    print("# Meteorite Benchmark Summary")
    print()
    print("These benchmarks measure local framework/runtime overhead on a single machine. They are not a claim of real-world network throughput.")
    print()
    
    # Warnings section (Requirement 8)
    warnings = []
    if env.get("git_status"):
        warnings.append("Git working directory has uncommitted changes (git dirty).")
    if not env.get("wrk_version"):
        warnings.append("`wrk` benchmark tool is missing from PATH.")
    if not env.get("perf_version"):
        warnings.append("`perf` tool is missing; CPU counters were not collected.")
    if idle_rss is None or max_rss is None or max_threads is None:
        warnings.append("Memory sampling was degraded or unavailable (some metrics are n/a).")
        
    has_spikes = False
    for row in oha_rows:
        max_val = as_number(row["max"])
        p99_val = as_number(row["p99"])
        if max_val is not None and p99_val is not None and max_val > 10 * p99_val:
            has_spikes = True
            break
    if has_spikes:
        warnings.append("High max latency spikes detected (max latency is more than 10x p99 latency).")
        
    if warnings:
        print("## Warnings")
        print()
        for w in warnings:
            print(f"- ⚠️ {w}")
        print()
        
    print("## Run Metadata")
    print()
    print("| Field | Value |")
    print("|---|---|")
    metadata = [
        ("Timestamp", env.get("timestamp", "n/a")),
        ("Git commit", env.get("git_commit", "n/a")),
        ("Git dirty", "yes" if env.get("git_status") else "no"),
        ("Mode", bench.get("mode", "n/a")),
        ("Backend", "std.http"),
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
        
    print()
    print("## Binary")
    print()
    print("| Metric | Value |")
    print("|---|---:|")
    print(table_row(["File size", fmt_bytes(binary.get("bytes"))]))
    
    if parser_type == "linux":
        for key in ["text", "data", "bss", "dec", "hex"]:
            if key in sections:
                print(table_row([key, sections[key]]))
    elif parser_type == "darwin":
        for key in ["__TEXT", "__DATA", "__OBJC", "others", "dec", "hex"]:
            if key in sections:
                print(table_row([key, sections[key]]))
                
    if binary.get("file"):
        print(table_row(["file", binary.get("file")]))
        
    if parser_type == "unknown" and binary_sections_text.strip():
        print()
        print("Raw `size` output:")
        print("```text")
        print(binary_sections_text.strip())
        print("```")
        
    print()
    print("## Throughput and Latency (release-static)")
    print()
    print("| Scenario | Concurrency | Handler Kind | Build Mode | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Success | Errors |")
    print("|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
    if not static_rows:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for row in static_rows:
        print(table_row([
            row["scenario"], row["concurrency"], row["handler_kind"], row["build_mode"],
            fmt(row["rps"]), fmt_latency(row["p50"]), fmt_latency(row["p95"]),
            fmt_latency(row["p99"]), fmt_latency(row["max"]), fmt(row["success"], 0), fmt(row["errors"], 0),
        ]))
        
    print()
    print("## Throughput and Latency (release-hybrid)")
    print()
    print("| Scenario | Concurrency | Handler Kind | Build Mode | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Success | Errors |")
    print("|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
    if not hybrid_rows:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for row in hybrid_rows:
        print(table_row([
            row["scenario"], row["concurrency"], row["handler_kind"], row["build_mode"],
            fmt(row["rps"]), fmt_latency(row["p50"]), fmt_latency(row["p95"]),
            fmt_latency(row["p99"]), fmt_latency(row["max"]), fmt(row["success"], 0), fmt(row["errors"], 0),
        ]))
        
    print()
    print("## Fixed-Rate Latency Runs")
    print()
    print("| Scenario | Concurrency | Target QPS | Handler Kind | Build Mode | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Success | Errors |")
    print("|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
    if not fixed_rows:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for row in fixed_rows:
        print(table_row([
            row["scenario"], row["concurrency"], row["qps"], row["handler_kind"], row["build_mode"],
            fmt(row["rps"]), fmt_latency(row["p50"]), fmt_latency(row["p95"]),
            fmt_latency(row["p99"]), fmt_latency(row["max"]), fmt(row["success"], 0), fmt(row["errors"], 0),
        ]))
        
    print()
    print("## Peak Summary")
    print()
    print("| Mode | Scenario | Peak Req/s | Concurrency | Min p50 | Concurrency |")
    print("|---|---|---:|---:|---:|---:|")
    groups = {}
    for row in oha_rows:
        key = (row["build_mode"], row["scenario"])
        if key not in groups:
            groups[key] = []
        groups[key].append(row)
        
    if not groups:
        print(table_row(["n/a", "n/a", "n/a", "n/a", "n/a", "n/a"]))
    for (b_mode, scen), rows in sorted(groups.items()):
        # Find peak rps
        peak_row = max(rows, key=lambda r: as_number(r["rps"]) or 0)
        # Find min p50
        min_p50_row = min(rows, key=lambda r: as_number(r["p50"]) or float('inf'))
        
        peak_rps_val = peak_row["rps"]
        peak_rps_c = peak_row["concurrency"] + (f" (QPS: {peak_row['qps']})" if peak_row.get("is_fixed") else "")
        min_p50_val = min_p50_row["p50"]
        min_p50_c = min_p50_row["concurrency"] + (f" (QPS: {min_p50_row['qps']})" if min_p50_row.get("is_fixed") else "")
        
        print(table_row([
            b_mode, scen, fmt(peak_rps_val), peak_rps_c, fmt_latency(min_p50_val), min_p50_c
        ]))
        
    print()
    print("## Memory")
    print()
    print("| Metric | Value |")
    print("|---|---:|")
    print(table_row(["Idle RSS KB", fmt(idle_rss, 0)]))
    print(table_row(["Max RSS KB", fmt(max_rss, 0)]))
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
