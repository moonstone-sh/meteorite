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


def fmt(value, digits=0):
    if value is None:
        return "n/a"
    try:
        number = float(value)
    except Exception:
        return str(value)
    if math.isnan(number) or math.isinf(number):
        return "n/a"
    if abs(number) >= 1000:
        return f"{number:,.{digits}f}"
    if digits == 0:
        return str(int(number))
    return f"{number:.{digits}f}"


def fmt_latency(value):
    number = as_number(value)
    if number is None:
        return "n/a"
    if number < 10:
        number *= 1000
    return f"{number:.3f} ms"


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


def parse_oha(path):
    obj = load_json(path)
    match = re.match(r"(.+)-oha-c(\d+)\.json$", path.name)
    if not match:
        return None
    scenario = match.group(1)
    concurrency = int(match.group(2))
    summary = obj.get("summary") if isinstance(obj, dict) else None
    rps = None
    if isinstance(summary, dict):
        rps = find_metric(summary, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"])
    if rps is None:
        rps = find_metric(obj, ["requestsPerSec", "requests_per_sec", "requestRate", "throughput"])
    return {
        "scenario": scenario,
        "concurrency": concurrency,
        "rps": as_number(rps),
        "p50": latency_value(obj, "p50"),
        "p95": latency_value(obj, "p95"),
        "p99": latency_value(obj, "p99"),
    }


def collect_results(result_dir):
    result_dir = Path(result_dir)
    bench = load_json(result_dir / "bench.json")
    build_info = load_json(result_dir / "build-info.json")
    binary = load_json(result_dir / "binary.json")
    rows = []
    for path in sorted(result_dir.glob("*-oha-c*.json")):
        row = parse_oha(path)
        if row:
            rows.append(row)

    # Peak row per scenario
    peak_by_scenario = {}
    for row in rows:
        scen = row["scenario"]
        if scen not in peak_by_scenario or (row["rps"] or 0) > (peak_by_scenario[scen]["rps"] or 0):
            peak_by_scenario[scen] = row

    target = bench.get("target", "meteorite")
    framework = build_info.get("framework", "meteorite" if target == "meteorite" else "hono")
    runtime = build_info.get("runtime", "n/a")
    mode = bench.get("mode", "n/a")
    hybrid_profile = build_info.get("hybrid_profile", bench.get("hybrid_profile", "n/a"))
    backend = build_info.get("backend", bench.get("backend", "n/a"))
    strategy = build_info.get("connection_strategy", bench.get("fast_http_strategy", "n/a"))

    if target.startswith("hono"):
        label = f"{framework}-{runtime}"
    else:
        label = mode + (f"/{backend}" if backend != "n/a" else "") + (f"/{strategy}" if strategy != "n/a" else "") + (f" ({hybrid_profile})" if hybrid_profile != "default" and hybrid_profile != "n/a" else "")

    return {
        "dir": result_dir,
        "label": label,
        "target": target,
        "framework": framework,
        "runtime": runtime,
        "mode": mode,
        "hybrid_profile": hybrid_profile,
        "backend": backend,
        "strategy": strategy,
        "build_info": build_info,
        "binary": binary,
        "peak_by_scenario": peak_by_scenario,
    }


def peak_row(results, scenario):
    return results["peak_by_scenario"].get(scenario, {})


def peak_rps(results, scenario):
    return peak_row(results, scenario).get("rps")


def peak_latency(results, scenario, p):
    return peak_row(results, scenario).get(p)


def peak_concurrency(results, scenario):
    return peak_row(results, scenario).get("concurrency")


def relative_to_plain(results, scenario):
    plain = peak_rps(results, "plain-zig")
    val = peak_rps(results, scenario)
    if plain and val:
        return val / plain
    return None


def main():
    if len(sys.argv) < 2:
        print("usage: compare.py RESULT_DIR [RESULT_DIR ...]", file=sys.stderr)
        return 2

    results_list = [collect_results(arg) for arg in sys.argv[1:]]

    # Sort: meteorite static, meteorite hybrid, hono-bun, hono-node
    def sort_key(r):
        order = {"meteorite": 0, "hono-bun": 1, "hono-node": 2}
        base = order.get(r["target"], 99)
        if r["target"] == "meteorite" and "hybrid" in r["mode"]:
            base += 0.1
        return base
    results_list.sort(key=sort_key)

    scenarios = [
        "plain-zig",
        "raw-zig",
        "plain-static",
        "hybrid-zig",
        "hybrid-inline-bench",
        "hybrid-inline-text-literal",
        "hybrid-inline-params",
        "hybrid-inline-echo",
        "health",
        "typed-param",
        "pattern-param",
        "file-pattern",
        "echo-small",
        "echo-8k",
        "hybrid-inline",
    ]

    # Trust checks
    print("# Meteorite vs Hono Benchmark Comparison")
    print()
    print("These benchmarks measure local framework/runtime overhead on a single machine.")
    print()
    print("## Trust checks")
    print()
    print("| Target | Optimize/runtime | Keepalive verified | wrk/oha agreement | Notes |")
    print("|---|---|---|---|---|")
    for r in results_list:
        build_info = r["build_info"]
        optimize = build_info.get("zig_optimize", "n/a")
        runtime_info = f"{optimize} / {r['runtime']}" if r["target"] == "meteorite" else r["runtime"]

        ka_on = load_json(r["dir"] / "keepalive-on-smoke.json")
        ka_off = load_json(r["dir"] / "keepalive-off-smoke.json")
        ka_on_rps = as_number(find_metric(ka_on.get("summary", {}), ["requestsPerSec"]))
        ka_off_rps = as_number(find_metric(ka_off.get("summary", {}), ["requestsPerSec"]))
        keepalive_ok = "yes"
        if ka_on_rps and ka_off_rps and ka_on_rps > 0:
            if abs(ka_on_rps - ka_off_rps) / ka_on_rps <= 0.10:
                keepalive_ok = "⚠️ similar"
        else:
            keepalive_ok = "n/a"

        wrk_txt = r["dir"] / "wrk-health-c256.txt"
        wrk_rps = None
        if wrk_txt.exists():
            m = re.search(r"Requests/sec:\s+([\d,.]+)", wrk_txt.read_text(encoding="utf-8", errors="replace"))
            if m:
                wrk_rps = as_number(m.group(1))
        oha_rps = peak_rps(r, "health")
        wrk_agree = "n/a"
        if wrk_rps and oha_rps and oha_rps > 0:
            ratio = max(wrk_rps, oha_rps) / min(wrk_rps, oha_rps)
            wrk_agree = f"{ratio:.2f}x"
            if ratio > 2:
                wrk_agree = f"⚠️ {ratio:.2f}x"

        notes = []
        if r["target"] == "meteorite":
            if optimize == "Debug":
                notes.append("Debug build")
            if build_info.get("lua_runtime") and "static" in r["mode"]:
                notes.append("Lua runtime in static mode")
            if not build_info.get("lua_runtime") and "hybrid" in r["mode"]:
                notes.append("Lua runtime missing in hybrid mode")
        note_str = "; ".join(notes) if notes else "-"
        print(f"| {r['label']} | {runtime_info} | {keepalive_ok} | {wrk_agree} | {note_str} |")

    # Server ceiling
    print()
    print("## Server ceiling")
    print()
    print("| Target | Route | Handler | Peak req/s | p99 at peak | Binary/RSS |")
    print("|---|---|---:|---:|---:|---:|")
    for r in results_list:
        row = peak_row(r, "plain-zig")
        binary = r["binary"]
        bytes_val = binary.get("bytes", 0)
        rss = None
        mem_path = r["dir"] / "memory.csv"
        if mem_path.exists():
            try:
                with open(mem_path, newline="", encoding="utf-8") as handle:
                    reader = csv.DictReader(handle)
                    for row_mem in reader:
                        rss_val = as_number(row_mem.get("rss_kb"))
                        if rss_val is not None:
                            rss = rss_val if rss is None else max(rss, rss_val)
            except Exception:
                pass
        size_rss = f"{fmt(bytes_val)}B / {fmt(rss, 0)}KiB" if rss else f"{fmt(bytes_val)}B"
        handler = "static_zig" if r["target"] == "meteorite" else "hono_handler"
        print(f"| {r['label']} | /__bench/plain | {handler} | {fmt(row.get('rps'))} | {fmt_latency(row.get('p99'))} | {size_rss} |")

    # Route overhead relative to own plain baseline
    print()
    print("## Route overhead relative to own plain baseline")
    print()
    print("| Target | Scenario | Peak req/s | Relative to /__bench/plain |")
    print("|---|---|---:|---:|")
    for r in results_list:
        for scen in scenarios:
            if scen == "plain-zig":
                continue
            rel = relative_to_plain(r, scen)
            rel_str = f"{rel*100:.1f}%" if rel else "n/a"
            print(f"| {r['label']} | {scen} | {fmt(peak_rps(r, scen))} | {rel_str} |")

    # Meteorite hybrid overhead
    print()
    print("## Meteorite hybrid overhead")
    print()
    print("| Scenario | Static req/s | Hybrid Zig req/s | Hybrid Lua req/s | Lua overhead |")
    print("|---|---:|---:|---:|---:|")
    static_r = next((r for r in results_list if r["target"] == "meteorite" and "static" in r["mode"]), None)
    hybrid_r = next((r for r in results_list if r["target"] == "meteorite" and "hybrid" in r["mode"]), None)
    for scen in scenarios:
        static_rps = peak_rps(static_r, scen) if static_r else None
        hybrid_rps = peak_rps(hybrid_r, scen) if hybrid_r else None
        hybrid_lua_rps = peak_rps(hybrid_r, "hybrid-inline") if hybrid_r else None
        lua_overhead = None
        if static_rps and hybrid_lua_rps and static_rps > 0:
            lua_overhead = (static_rps - hybrid_lua_rps) / static_rps
        print(f"| {scen} | {fmt(static_rps)} | {fmt(hybrid_rps)} | {fmt(hybrid_lua_rps)} | {f'{lua_overhead*100:.1f}%' if lua_overhead is not None else 'n/a'} |")

    # Hono comparison
    print()
    print("## Hono comparison")
    print()
    print("| Scenario | Meteorite static | Meteorite hybrid Lua | Hono Bun | Hybrid Lua vs Hono |")
    print("|---|---:|---:|---:|---:|")
    hono_bun = next((r for r in results_list if r["target"] == "hono-bun"), None)
    for scen in scenarios:
        static_rps = peak_rps(static_r, scen) if static_r else None
        hybrid_lua_rps = peak_rps(hybrid_r, "hybrid-inline") if hybrid_r else None
        hono_rps = peak_rps(hono_bun, scen) if hono_bun else None
        vs_hono = None
        if hybrid_lua_rps and hono_rps and hono_rps > 0:
            vs_hono = hybrid_lua_rps / hono_rps
        print(f"| {scen} | {fmt(static_rps)} | {fmt(hybrid_lua_rps)} | {fmt(hono_rps)} | {f'{vs_hono*100:.1f}%' if vs_hono is not None else 'n/a'} |")

    # Gates / bottleneck diagnosis
    print()
    print("## Gate checks")
    print()
    failed_gates = []

    if static_r and hono_bun:
        static_plain = peak_rps(static_r, "plain-zig") or 0
        hono_plain = peak_rps(hono_bun, "plain-zig") or 0
        if hono_plain > 0:
            ratio = static_plain / hono_plain
            print(f"- **Gate 1 (static ceiling):** Meteorite static /__bench/plain = {fmt(static_plain)} req/s; Hono Bun = {fmt(hono_plain)} req/s; ratio = {ratio*100:.1f}%")
            if ratio < 0.90:
                failed_gates.append("Gate 1 (static ceiling): std.http/Zig backend is behind Bun serve")
        else:
            print("- **Gate 1 (static ceiling):** Hono Bun plain-zig data unavailable")

    if static_r and hybrid_r:
        # Use a static zig route from hybrid (e.g., health) vs static mode health
        static_health = peak_rps(static_r, "health") or 0
        hybrid_health = peak_rps(hybrid_r, "health") or 0
        if static_health > 0:
            ratio = hybrid_health / static_health
            print(f"- **Gate 2 (hybrid Zig overhead):** Meteorite hybrid static_zig health = {fmt(hybrid_health)} req/s; release-static health = {fmt(static_health)} req/s; ratio = {ratio*100:.1f}%")
            if ratio < 0.85:
                failed_gates.append("Gate 2 (hybrid Zig overhead): including Lua runtime hurts static routes")
        else:
            print("- **Gate 2 (hybrid Zig overhead):** static health data unavailable")

    if hybrid_r and hono_bun:
        hybrid_lua = peak_rps(hybrid_r, "hybrid-inline") or 0
        hono_trivial = peak_rps(hono_bun, "hybrid-inline") or 0
        if hono_trivial > 0:
            ratio = hybrid_lua / hono_trivial
            print(f"- **Gate 3 (inline Lua trivial):** Meteorite hybrid Lua /hybrid-inline = {fmt(hybrid_lua)} req/s; Hono Bun /hybrid-inline = {fmt(hono_trivial)} req/s; ratio = {ratio*100:.1f}%")
            if ratio < 0.50:
                failed_gates.append("Gate 3 (inline Lua trivial): hybrid Lua route is less than 50% of Hono Bun trivial route")
        else:
            print("- **Gate 3 (inline Lua trivial):** Hono Bun trivial data unavailable")

    if hybrid_r and hono_bun:
        hybrid_typed = peak_rps(hybrid_r, "typed-param") or 0
        hybrid_lua_typed = peak_rps(hybrid_r, "hybrid-inline") or 0
        if hybrid_lua_typed > 0:
            ratio = hybrid_typed / hybrid_lua_typed
            print(f"- **Gate 4 (typed param vs trivial):** Meteorite hybrid typed-param = {fmt(hybrid_typed)} req/s; hybrid Lua trivial = {fmt(hybrid_lua_typed)} req/s; ratio = {ratio*100:.1f}%")
            if ratio < 0.80:
                failed_gates.append("Gate 4 (typed param vs trivial): ctx.params materialization is expensive")
        else:
            print("- **Gate 4 (typed param vs trivial):** hybrid Lua trivial data unavailable")

    if hybrid_r and hono_bun:
        hybrid_echo = peak_rps(hybrid_r, "echo-small") or 0
        hono_echo = peak_rps(hono_bun, "echo-small") or 0
        if hono_echo > 0:
            ratio = hybrid_echo / hono_echo
            print(f"- **Gate 5 (echo-small):** Meteorite hybrid echo-small = {fmt(hybrid_echo)} req/s; Hono Bun echo-small = {fmt(hono_echo)} req/s; ratio = {ratio*100:.1f}%")
            if ratio < 0.80:
                failed_gates.append("Gate 5 (echo-small): body bridge is expensive")
        else:
            print("- **Gate 5 (echo-small):** Hono Bun echo data unavailable")

    print()
    print("## Bottleneck diagnosis")
    print()
    if failed_gates:
        print("Failed gates:")
        for g in failed_gates:
            print(f"- ⚠️ {g}")
    else:
        print("- All gates passed.")

    # Add per-scenario p99 at peak table
    print()
    print("## Peak latency comparison")
    print()
    print("| Scenario | Target | Peak req/s | Concurrency | p50 at peak | p95 at peak | p99 at peak |")
    print("|---|---|---:|---:|---:|---:|---:|")
    for scen in scenarios:
        for r in results_list:
            row = peak_row(r, scen)
            print(f"| {scen} | {r['label']} | {fmt(row.get('rps'))} | {fmt(row.get('concurrency'), 0)} | {fmt_latency(row.get('p50'))} | {fmt_latency(row.get('p95'))} | {fmt_latency(row.get('p99'))} |")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
