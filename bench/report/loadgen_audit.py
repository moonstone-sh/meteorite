import json, sys
from pathlib import Path

marker = Path(sys.argv[1])
entries = []
if marker.exists():
    for line in marker.read_text(errors="replace").splitlines():
        if "=" not in line:
            continue
        loadgen, path = line.split("=", 1)
        summary = Path(path) / "summary.json"
        if summary.exists():
            try:
                data = json.loads(summary.read_text(errors="replace"))
            except Exception:
                continue
            for row in data.get("results", []):
                if row.get("proof_only") or not row.get("compare", True):
                    continue
                entries.append((loadgen, row))

by_key = {}
for loadgen, row in entries:
    key = (row.get("variant"), row.get("scenario"), row.get("concurrency"))
    by_key.setdefault(key, {})[loadgen] = row

warnings = []
for key, rows in sorted(by_key.items()):
    wrk = rows.get("wrk")
    oha = rows.get("oha")
    corrected = rows.get("oha-corrected")
    if wrk and oha:
        wrk_p99 = float(wrk.get("p99_us_median") or 0)
        oha_p99 = float(oha.get("p99_us_median") or 0)
        base = min(wrk_p99, oha_p99)
        if base > 0 and abs(wrk_p99 - oha_p99) / base > 0.50:
            warnings.append((key, "loadgen_parser_problem", f"wrk p99={wrk_p99:.0f}us", f"oha p99={oha_p99:.0f}us"))
    if oha and corrected:
        oha_p99 = float(oha.get("p99_us_median") or 0)
        corrected_p99 = float(corrected.get("p99_us_median") or 0)
        if oha_p99 > 0 and corrected_p99 / oha_p99 > 1.50:
            warnings.append((key, "coordinated_omission_problem", f"oha p99={oha_p99:.0f}us", f"oha corrected p99={corrected_p99:.0f}us"))
    if wrk and oha:
        wrk_flags = wrk.get("latency_sanity_flags") or []
        oha_flags = oha.get("latency_sanity_flags") or []
        if wrk_flags and oha_flags:
            warnings.append((key, "closed_loop_active_concurrency_suspect", f"wrk flags={','.join(wrk_flags)}", f"oha flags={','.join(oha_flags)}"))
    for loadgen, row in rows.items():
        if row.get("environment_quarantined"):
            warnings.append((key, "os_harness_limit_problem", f"{loadgen} environment", row.get("environment_invalid_reason", "environment_quarantined")))

if warnings:
    print("\n## Loadgen Disagreement Audit")
    for (variant, scenario, concurrency), category, left, right in warnings:
        print(f"{category}: {variant} {scenario} c={concurrency}: {left}; {right}")
    print("Categories: loadgen_parser_problem, coordinated_omission_problem, active_concurrency_problem, os_harness_limit_problem.")
    print("Do not use raw p99 as headline without explaining loadgen and active-pressure behavior.")
