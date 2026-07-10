#!/usr/bin/env python3
"""Estimate Meteorite subsystem costs from benchmark summary rows.

This is not a sampling profiler. It is a deterministic differential profiler for
Meteorite's benchmark fixture: it compares scenario medians from summary.json and
attributes incremental latency to router, parser, Lua bridge, handler/body IO,
and response writer slices. The goal is to make public benchmark claims auditable
without requiring OS-specific perf/dtrace/instruments support.
"""

import argparse
import json
from pathlib import Path

SLICE_PAIRS = [
    ("router", "plain_text", "typed_param", "static route match + typed param validation"),
    ("parser", "plain_text", "echo_small", "request body/header parse path beyond static GET"),
    ("lua_bridge", "zig-static", "lua-return-string", "embedded Lua call/pcall bridge over Zig handler"),
    ("handler", "lua-return-string", "lua-loop-1000", "application handler compute over trivial Lua return"),
    ("body_io", "lua-return-string", "lua-body-1k", "Lua body read/copy for 1 KiB request"),
    ("response_writer", "lua-return-string", "lua-json-small", "Lua JSON helper + response serialization over text return"),
]


def load_rows(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    return data.get("results", [])


def metric(row: dict, name: str) -> float:
    return float(row.get(name) or 0.0)


def choose_rows(rows: list[dict], variant: str, concurrency: int, loadgen: str) -> dict[str, dict]:
    selected = {}
    for row in rows:
        if row.get("variant") != variant:
            continue
        if int(row.get("concurrency") or 0) != concurrency:
            continue
        if row.get("loadgen") != loadgen:
            continue
        selected[row.get("scenario", "")] = row
    return selected


def estimate(summary: Path, variant: str, concurrency: int, loadgen: str, latency_metric: str) -> tuple[list[dict], list[str]]:
    rows = choose_rows(load_rows(summary), variant, concurrency, loadgen)
    notes = []
    estimates = []
    for subsystem, base_name, target_name, description in SLICE_PAIRS:
        base = rows.get(base_name)
        target = rows.get(target_name)
        if not base or not target:
            notes.append(f"missing {subsystem}: requires {base_name} and {target_name}")
            estimates.append({
                "subsystem": subsystem,
                "base": base_name,
                "target": target_name,
                "delta_us": None,
                "available": False,
                "description": description,
            })
            continue
        base_us = metric(base, latency_metric)
        target_us = metric(target, latency_metric)
        delta = max(0.0, target_us - base_us)
        claim_grade = bool(base.get("claim_grade")) and bool(target.get("claim_grade"))
        if not claim_grade:
            notes.append(f"quarantined {subsystem}: one or both source rows are not claim-grade")
        estimates.append({
            "subsystem": subsystem,
            "base": base_name,
            "target": target_name,
            "base_us": base_us,
            "target_us": target_us,
            "delta_us": delta,
            "available": True,
            "claim_grade": claim_grade,
            "description": description,
        })
    return estimates, notes


def write_markdown(path: Path, summary: Path, variant: str, concurrency: int, loadgen: str, latency_metric: str, estimates: list[dict], notes: list[str]) -> None:
    lines = [
        "# Meteorite Profiling Cost Breakdown",
        "",
        f"Source: `{summary}`",
        f"Variant: `{variant}`",
        f"Concurrency: `{concurrency}`",
        f"Loadgen: `{loadgen}`",
        f"Latency metric: `{latency_metric}`",
        "",
        "This differential profile compares benchmark scenarios to isolate broad subsystem costs. It complements sampling profilers and is intentionally portable across macOS/Linux CI.",
        "",
        "| Subsystem | Base Scenario | Target Scenario | Delta µs | Claim Grade | Meaning |",
        "|---|---|---|---:|---:|---|",
    ]
    for item in estimates:
        if not item.get("available"):
            delta = "n/a"
            claim = "False"
        else:
            delta = f"{item['delta_us']:.2f}"
            claim = str(bool(item.get("claim_grade")))
        lines.append(f"| {item['subsystem']} | {item['base']} | {item['target']} | {delta} | {claim} | {item['description']} |")
    lines.extend(["", "## Notes"])
    if notes:
        lines.extend(f"- {note}" for note in notes)
    else:
        lines.append("- all configured subsystem pairs were available and claim-grade")
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a differential profiling-cost report from Meteorite bench summary.json")
    parser.add_argument("summary", type=Path, help="Path to bench summary.json")
    parser.add_argument("--variant", default="meteorite-1worker")
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--loadgen", default="wrk")
    parser.add_argument("--latency-metric", default="p50_us_median", choices=["p50_us_median", "p90_us_median", "p99_us_median", "latency_avg_us_median"])
    parser.add_argument("--out", type=Path, default=None, help="Markdown output path; defaults beside summary.json")
    parser.add_argument("--json-out", type=Path, default=None, help="JSON output path; defaults beside summary.json")
    args = parser.parse_args()

    estimates, notes = estimate(args.summary, args.variant, args.concurrency, args.loadgen, args.latency_metric)
    out = args.out or args.summary.with_name("profile-costs.md")
    json_out = args.json_out or args.summary.with_name("profile-costs.json")
    write_markdown(out, args.summary, args.variant, args.concurrency, args.loadgen, args.latency_metric, estimates, notes)
    json_out.write_text(json.dumps({
        "source": str(args.summary),
        "variant": args.variant,
        "concurrency": args.concurrency,
        "loadgen": args.loadgen,
        "latency_metric": args.latency_metric,
        "estimates": estimates,
        "notes": notes,
    }, indent=2, sort_keys=True) + "\n")
    print(out)
    print(json_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
