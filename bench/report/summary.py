import os
import json
import re
import statistics
from dataclasses import dataclass
from pathlib import Path

out = Path(os.environ["BENCH_OUT"])
mode = os.environ["BENCH_MODE"]
mode_name = mode.removeprefix("--mode=").removeprefix("--")
selected_loadgen = os.environ.get("BENCH_LOADGEN", "wrk")
selected_latency_correction = os.environ.get("BENCH_LATENCY_CORRECTION", "0") == "1"
meteorite_build_mode = os.environ.get("BENCH_METEORITE_BUILD_MODE", "release-hybrid")
if mode in ("--mode=lua-bridge", "--mode=lua-bridge-smoke", "--mode=meteorite-app"):
    labels = ["meteorite-1worker", "meteorite-auto"]
else:
    labels = ["meteorite-1worker", "meteorite-auto", "hono-bun-single", "hono-bun-multiprocess", "go-nethttp", "go-fiber-fasthttp", "rust-actix"]
concurrency = [int(x) for x in os.environ["BENCH_CONCURRENCY"].split(",") if x]
scenarios = [line.split("|", 1)[0] for line in Path(os.environ["BENCH_SCENARIOS_FILE"]).read_text().splitlines() if line]
reps = int(os.environ["BENCH_REPS"])
system_env = {}
system_env_path = out / "system.env"
if system_env_path.exists():
    for line in system_env_path.read_text(errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            system_env[key.strip()] = value.strip()

LOW_RPS_RATIO = 0.70
HIGH_RPS_RATIO = 1.35
MIN_VALID_REPS_FOR_OUTLIER_FILTER = 3

def parse_us(val: str) -> float:
    val = (val or "").strip()
    try:
        if val.endswith("ms"):
            return float(val[:-2]) * 1000.0
        if val.endswith("us"):
            return float(val[:-2])
        if val.endswith("s"):
            return float(val[:-1]) * 1000000.0
        return float(val)
    except Exception:
        return 0.0

def parse_transfer_bytes_per_sec(value: str) -> float:
    value = (value or "").strip()
    m = re.match(r"([\d.]+)([KMGTP]?B)$", value, re.I)
    if not m:
        try:
            return float(value)
        except Exception:
            return 0.0
    number = float(m.group(1))
    unit = m.group(2).upper()
    factors = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4, "PB": 1024**5}
    return number * factors.get(unit, 1)

def parse_scaled_number(value: str) -> float:
    value = (value or "").strip()
    m = re.match(r"([\d.]+)([kKmMgGtT]?)$", value)
    if not m:
        try:
            return float(value)
        except Exception:
            return 0.0
    number = float(m.group(1))
    suffix = m.group(2).lower()
    factors = {"": 1, "k": 1_000, "m": 1_000_000, "g": 1_000_000_000, "t": 1_000_000_000_000}
    return number * factors.get(suffix, 1)

def read_kv(path: Path) -> dict:
    data = {}
    if not path.exists():
        return data

    for line in path.read_text(errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip()
    return data

def walk_json(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk_json(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk_json(value)

def parse_oha_json(text: str) -> dict:
    try:
        data = json.loads(text)
    except Exception:
        data = {}

    def first(*names, default=0):
        wanted = {name.lower() for name in names}
        for d in walk_json(data):
            for key, value in d.items():
                if str(key).lower() in wanted and isinstance(value, (int, float)):
                    return value
        return default

    def duration_us(value):
        if isinstance(value, str):
            return parse_us(value)
        if isinstance(value, (int, float)):
            return float(value) * 1_000_000.0
        return 0.0

    def percentile(name):
        wanted = {name, name.lower(), name.upper(), name.replace("p", ""), name.replace("p", "") + ".0"}
        for d in walk_json(data):
            for key, value in d.items():
                if str(key) in wanted:
                    return duration_us(value)
        return 0.0

    non2xx = 0
    status_total = 0
    for d in walk_json(data):
        for key, value in d.items():
            if "status" in str(key).lower() and isinstance(value, dict):
                for code, count in value.items():
                    try:
                        code_i = int(code)
                        count_i = int(count)
                    except Exception:
                        continue
                    status_total += count_i
                    if not (200 <= code_i < 400):
                        non2xx += count_i

    errors = int(first("error", "errors", "failed", default=0))
    return {
        "rps": float(first("requestsPerSec", "requests_per_sec", "requestPerSec", "rps", default=0)),
        "requests": status_total or int(first("requests", "requests_completed", "successful", default=0)),
        "latency_avg_us": duration_us(first("average", "avg", "latency_avg", default=0)),
        "latency_stdev_us": duration_us(first("stddev", "stdev", "standardDeviation", "latency_stdev", default=0)),
        "latency_max_us": duration_us(first("slowest", "max", "latency_max", default=0)),
        "p50_us": percentile("p50"),
        "p75_us": percentile("p75"),
        "p90_us": percentile("p90"),
        "p99_us": percentile("p99"),
        "req_sec_avg": 0.0,
        "transfer_per_sec_bytes": float(first("sizePerSec", "bytesPerSec", "transfer_per_sec", default=0)),
        "socket_connect_errors": 0,
        "socket_read_errors": 0,
        "socket_write_errors": 0,
        "socket_timeout_errors": errors,
        "socket_errors": errors,
        "non2xx": non2xx,
        "parse_error": "",
    }

def parse_wrk_log(path: Path) -> dict:
    if not path.exists():
        return {
            "rps": 0.0,
            "requests": 0,
            "latency_avg_us": 0.0,
            "latency_stdev_us": 0.0,
            "latency_max_us": 0.0,
            "p50_us": 0.0,
            "p75_us": 0.0,
            "p90_us": 0.0,
            "p99_us": 0.0,
            "req_sec_avg": 0.0,
            "transfer_per_sec_bytes": 0.0,
            "socket_connect_errors": 0,
            "socket_read_errors": 0,
            "socket_write_errors": 0,
            "socket_timeout_errors": 0,
            "socket_errors": 0,
            "non2xx": 0,
            "parse_error": "missing-log",
        }

    text = path.read_text(errors="replace")
    if text.lstrip().startswith("{"):
        parsed = parse_oha_json(text)
        if parsed["rps"] <= 0:
            parsed["parse_error"] = "missing-rps"
        elif parsed["requests"] <= 0:
            parsed["parse_error"] = "missing-requests"
        elif parsed["p50_us"] <= 0 or parsed["p99_us"] <= 0:
            parsed["parse_error"] = "missing-latency"
        return parsed
    lines = text.splitlines()

    rps = 0.0
    requests = 0
    latency_avg_us = 0.0
    latency_stdev_us = 0.0
    latency_max_us = 0.0
    p50_us = 0.0
    p75_us = 0.0
    p90_us = 0.0
    p99_us = 0.0
    req_sec_avg = 0.0
    transfer_per_sec_bytes = 0.0
    socket_connect_errors = 0
    socket_read_errors = 0
    socket_write_errors = 0
    socket_timeout_errors = 0
    socket_errors = 0
    non2xx = 0

    m = re.search(r"^\s*Latency\s+(\S+)\s+(\S+)\s+(\S+)", text, re.MULTILINE)
    if m:
        latency_avg_us = parse_us(m.group(1))
        latency_stdev_us = parse_us(m.group(2))
        latency_max_us = parse_us(m.group(3))

    m = re.search(r"^\s*Req/Sec\s+(\S+)", text, re.MULTILINE)
    if m:
        req_sec_avg = parse_scaled_number(m.group(1))

    m = re.search(r"^Requests/sec:\s+([\d.]+)", text, re.MULTILINE)
    if m:
        rps = float(m.group(1))

    m = re.search(r"^\s*(\d+) requests in ", text, re.MULTILINE)
    if m:
        requests = int(m.group(1))

    m = re.search(r"Non-2xx or 3xx responses:\s+(\d+)", text)
    if m:
        non2xx = int(m.group(1))

    m = re.search(
        r"Socket errors:\s+connect\s+(\d+),\s+read\s+(\d+),\s+write\s+(\d+),\s+timeout\s+(\d+)",
        text,
    )
    if m:
        socket_connect_errors, socket_read_errors, socket_write_errors, socket_timeout_errors = [int(x) for x in m.groups()]
        socket_errors = socket_connect_errors + socket_read_errors + socket_write_errors + socket_timeout_errors

    m = re.search(r"^Transfer/sec:\s+(\S+)", text, re.MULTILINE)
    if m:
        transfer_per_sec_bytes = parse_transfer_bytes_per_sec(m.group(1))

    in_dist = False
    for line in lines:
        if "Latency Distribution" in line:
            in_dist = True
            continue

        if not in_dist:
            continue

        parts = line.split()
        if len(parts) >= 2:
            if parts[0] == "50%":
                p50_us = parse_us(parts[1])
            elif parts[0] == "75%":
                p75_us = parse_us(parts[1])
            elif parts[0] == "90%":
                p90_us = parse_us(parts[1])
            elif parts[0] == "99%":
                p99_us = parse_us(parts[1])

    parse_error = ""
    if rps <= 0:
        parse_error = "missing-rps"
    elif requests <= 0:
        parse_error = "missing-requests"
    elif p50_us <= 0 or p99_us <= 0:
        parse_error = "missing-latency"

    return {
        "rps": rps,
        "requests": requests,
        "latency_avg_us": latency_avg_us,
        "latency_stdev_us": latency_stdev_us,
        "latency_max_us": latency_max_us,
        "p50_us": p50_us,
        "p75_us": p75_us,
        "p90_us": p90_us,
        "p99_us": p99_us,
        "req_sec_avg": req_sec_avg,
        "transfer_per_sec_bytes": transfer_per_sec_bytes,
        "socket_connect_errors": socket_connect_errors,
        "socket_read_errors": socket_read_errors,
        "socket_write_errors": socket_write_errors,
        "socket_timeout_errors": socket_timeout_errors,
        "socket_errors": socket_errors,
        "non2xx": non2xx,
        "parse_error": parse_error,
    }

@dataclass
class Run:
    loadgen: str
    label: str
    scenario: str
    meteorite_build_mode: str
    claim_class: str
    tier: str
    concurrency: int
    rep: int
    rps: float = 0.0
    requests: int = 0
    latency_avg_us: float = 0.0
    latency_stdev_us: float = 0.0
    latency_max_us: float = 0.0
    p50_us: float = 0.0
    p75_us: float = 0.0
    p90_us: float = 0.0
    p99_us: float = 0.0
    req_sec_avg: float = 0.0
    transfer_per_sec_bytes: float = 0.0
    loadgen_version: str = "unknown"
    loadgen_threads: int = 0
    loadgen_concurrency: int = 0
    target_qps: float = 0.0
    configured_service_time_seconds: float = 0.0
    socket_connect_errors: int = 0
    socket_read_errors: int = 0
    socket_write_errors: int = 0
    socket_timeout_errors: int = 0
    socket_errors: int = 0
    non2xx: int = 0
    wrk_exit_code: int = 0
    warmup_exit_code: int = 0
    server_alive_before: bool = True
    server_alive_after: bool = True
    loadgen_cpu_max: float = 0.0
    lua_pcalls_delta: int = 0
    native_calls_delta: int = 0
    lua_pcalls_per_request: float = 0.0
    validation: str = ""
    compare: bool = True
    proof_only: bool = False
    latency_floor_us: float = 0.0
    latency_correction: bool = False
    active_probe_supported: bool = False
    accepted_total_delta: int = 0
    completed_total_delta: int = 0
    open_connections_max: int = 0
    inflight_current_after: int = 0
    inflight_max: int = 0
    queue_depth_current_after: int = 0
    queue_depth_max: int = 0
    worker_queue_depth_max: int = 0
    budget_capacity: int = 0
    budget_rejections_total: int = 0
    backpressure_total: int = 0
    soft_nofile: str = ""
    hard_nofile: str = ""
    somaxconn: str = ""
    max_concurrency_requested: int = 0
    fd_limit_ok: bool = True
    backlog_ok: bool = True
    ephemeral_ports_ok: bool = True
    environment_suspicious: bool = False
    environment_invalid_reason: str = "none"
    server_fd_count_before: int = 0
    server_fd_count_after: int = 0
    server_fd_count_max: int = 0
    loadgen_fd_count_before: int = 0
    loadgen_fd_count_after: int = 0
    loadgen_fd_count_max: int = 0
    fd_usage_high: bool = False
    fd_usage_critical: bool = False
    parse_error: str = ""
    hard_invalid_reason: str = ""
    soft_invalid_reason: str = ""

    @property
    def hard_valid(self) -> bool:
        return self.hard_invalid_reason == ""

    @property
    def valid(self) -> bool:
        return self.hard_invalid_reason == "" and self.soft_invalid_reason == ""

    @property
    def reason(self) -> str:
        return self.hard_invalid_reason or self.soft_invalid_reason

def read_server_stats(label: str):
    srv_stats = out / f"{label}-stats.log"
    if not srv_stats.exists():
        return 0.0, 0.0

    rows = []
    for line in srv_stats.read_text(errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                rows.append((float(parts[0]), float(parts[1])))
            except ValueError:
                pass

    if not rows:
        return 0.0, 0.0

    srv_cpu = max(cpu for cpu, _ in rows)
    srv_rss = max(rss for _, rss in rows) / 1024.0
    return srv_cpu, srv_rss

def median_attr(rows, attr: str) -> float:
    vals = [getattr(row, attr) for row in rows]
    return statistics.median(vals) if vals else 0.0

def sum_attr(rows, attr: str) -> int:
    return sum(int(getattr(row, attr)) for row in rows)

def implied_avg_latency_us(concurrency: int, rps: float) -> float:
    return (float(concurrency) / rps) * 1_000_000.0 if rps > 0 else 0.0

def safe_ratio(numerator: float, denominator: float) -> float:
    return float(numerator) / float(denominator) if denominator > 0 else 0.0

def latency_sanity_notes(concurrency: int, rps: float, p99_us: float, latency_avg_us: float) -> list[str]:
    implied = implied_avg_latency_us(concurrency, rps)
    notes = []
    if implied > 0 and p99_us > 0 and p99_us < implied * 0.25:
        notes.append(f"p99-below-implied-avg p99_us={p99_us:.0f} implied_avg_us={implied:.0f}")
    if implied > 0 and latency_avg_us > 0 and latency_avg_us < implied * 0.25:
        notes.append(f"latency-avg-below-implied-avg latency_avg_us={latency_avg_us:.0f} implied_avg_us={implied:.0f}")
    return notes

def is_corrected_latency(loadgen: str) -> bool:
    return loadgen == "oha-corrected"

def configured_concurrency_not_observed(configured: int, observed_open_connections_max: int, active_probe_supported: bool) -> bool:
    if configured <= 1:
        return False
    if not active_probe_supported:
        return False
    return observed_open_connections_max < configured * 0.80

def invalid_hybrid_proof(tier: str, lua_pcalls_per_request: float) -> bool:
    return tier.startswith("lua-") and lua_pcalls_per_request < 0.95

def claim_class_from_meta(meta: dict) -> str:
    raw = meta.get("claim_class", "static" if meta.get("tier") == "static" else "unknown")
    backend = meta.get("backend", "")
    transport = meta.get("transport", "")
    protocol = meta.get("protocol", "")
    ipc_class = ""
    if backend == "ipc_unixsocket" or protocol == "meteorite.ipc.v0":
        ipc_class = "native-ipc"
    elif backend == "ipc_unixsocket_http" or (transport == "unix" and protocol == "http/1.1"):
        ipc_class = "http-over-uds"
    if not ipc_class:
        return raw
    if raw == "proof-only":
        return ipc_class + ":proof-only"
    if raw in ("", "unknown", "static", "framework-parity"):
        return ipc_class
    return ipc_class + ":" + raw

def claim_grade_reasons(valid: list[Run], discarded: list[Run], sanity_notes: list[str], socket_errors: int, non2xx: int, environment_reasons: list[str]) -> list[str]:
    reasons = []
    if not valid:
        reasons.append("no-valid-reps")
    if discarded:
        reasons.append("discarded-or-outlier-reps")
    if socket_errors > 0:
        reasons.append(f"socket-errors-{socket_errors}")
    if non2xx > 0:
        reasons.append(f"non2xx-{non2xx}")
    reasons.extend(environment_reasons)
    reasons.extend(sanity_notes)
    return reasons

def load_run(label: str, scenario: str, c: int, rep: int):
    log_path = out / "raw" / f"{label}__{scenario}__c{c}__r{rep}__{selected_loadgen}.json"
    if not log_path.exists():
        log_path = out / "raw" / f"{label}__{scenario}__c{c}__r{rep}__{selected_loadgen}.out"
    meta_path = out / "meta" / f"{label}__{scenario}__c{c}__r{rep}__{selected_loadgen}.meta"
    if not log_path.exists():
        log_path = out / f"{label}-{scenario}-c{c}-rep{rep}.log"
    if not meta_path.exists():
        meta_path = out / f"{label}-{scenario}-c{c}-rep{rep}.meta"

    if not log_path.exists() and not meta_path.exists():
        return None

    meta = read_kv(meta_path)
    parsed = parse_wrk_log(log_path)

    def meta_int(key, default=0):
        try:
            return int(meta.get(key, default))
        except Exception:
            return default

    def meta_float(key, default=0.0):
        try:
            return float(meta.get(key, default))
        except Exception:
            return default

    run = Run(
        loadgen=meta.get("loadgen", selected_loadgen),
        label=label,
        scenario=scenario,
        meteorite_build_mode=meta.get("meteorite_build_mode", meteorite_build_mode),
        claim_class=claim_class_from_meta(meta),
        tier=meta.get("tier", "unknown"),
        concurrency=c,
        rep=rep,
        rps=parsed["rps"],
        requests=parsed["requests"],
        latency_avg_us=parsed["latency_avg_us"],
        latency_stdev_us=parsed["latency_stdev_us"],
        latency_max_us=parsed["latency_max_us"],
        p50_us=meta_float("p50_us", parsed["p50_us"]),
        p75_us=parsed["p75_us"],
        p90_us=parsed["p90_us"],
        p99_us=meta_float("p99_us", parsed["p99_us"]),
        req_sec_avg=parsed["req_sec_avg"],
        transfer_per_sec_bytes=parsed["transfer_per_sec_bytes"],
        loadgen_version=meta.get("loadgen_version", "unknown"),
        loadgen_threads=meta_int("loadgen_threads", meta_int("threads", 0)),
        loadgen_concurrency=meta_int("loadgen_concurrency", c),
        target_qps=meta_float("target_qps", 0.0),
        configured_service_time_seconds=meta_float("configured_service_time_seconds", 0.0),
        socket_connect_errors=parsed["socket_connect_errors"],
        socket_read_errors=parsed["socket_read_errors"],
        socket_write_errors=parsed["socket_write_errors"],
        socket_timeout_errors=parsed["socket_timeout_errors"],
        socket_errors=parsed["socket_errors"],
        non2xx=parsed["non2xx"],
        wrk_exit_code=meta_int("loadgen_exit_code", meta_int("wrk_exit_code", 0)),
        warmup_exit_code=meta_int("warmup_exit_code", 0),
        server_alive_before=meta.get("server_alive_before", "1") == "1",
        server_alive_after=meta.get("server_alive_after", "1") == "1",
        loadgen_cpu_max=meta_float("loadgen_cpu_max", 0.0),
        lua_pcalls_delta=meta_int("lua_pcalls_delta", 0),
        native_calls_delta=meta_int("native_calls_delta", 0),
        lua_pcalls_per_request=meta_float("lua_pcalls_per_request", 0.0),
        validation=meta.get("validation", ""),
        compare=meta.get("compare", "1") == "1",
        proof_only=meta.get("proof_only", "0") == "1",
        latency_floor_us=meta_float("latency_floor_us", 0.0),
        latency_correction=meta.get("latency_correction", "1" if selected_latency_correction else "0") == "1",
        active_probe_supported=meta.get("active_probe_supported", "0") == "1",
        accepted_total_delta=meta_int("accepted_total_delta", 0),
        completed_total_delta=meta_int("completed_total_delta", 0),
        open_connections_max=meta_int("open_connections_max", 0),
        inflight_current_after=meta_int("inflight_current_after", 0),
        inflight_max=meta_int("observed_inflight_max", meta_int("inflight_max", 0)),
        queue_depth_current_after=meta_int("queue_depth_current_after", 0),
        queue_depth_max=meta_int("observed_queue_depth_max", meta_int("queue_depth_max", 0)),
        worker_queue_depth_max=meta_int("worker_queue_depth_max", 0),
        budget_capacity=meta_int("budget_capacity", 0),
        budget_rejections_total=meta_int("budget_rejections_total", 0),
        backpressure_total=meta_int("backpressure_total", 0),
        soft_nofile=meta.get("soft_nofile", ""),
        hard_nofile=meta.get("hard_nofile", ""),
        somaxconn=meta.get("somaxconn", ""),
        max_concurrency_requested=meta_int("max_concurrency_requested", 0),
        fd_limit_ok=meta.get("fd_limit_ok", "true") == "true",
        backlog_ok=meta.get("backlog_ok", "true") == "true",
        ephemeral_ports_ok=meta.get("ephemeral_ports_ok", "true") == "true",
        environment_suspicious=meta.get("environment_suspicious", "false") == "true",
        environment_invalid_reason=meta.get("environment_invalid_reason", "none"),
        server_fd_count_before=meta_int("server_fd_count_before", 0),
        server_fd_count_after=meta_int("server_fd_count_after", 0),
        server_fd_count_max=meta_int("server_fd_count_max", 0),
        loadgen_fd_count_before=meta_int("loadgen_fd_count_before", 0),
        loadgen_fd_count_after=meta_int("loadgen_fd_count_after", 0),
        loadgen_fd_count_max=meta_int("loadgen_fd_count_max", 0),
        fd_usage_high=meta.get("fd_usage_high", "false") == "true",
        fd_usage_critical=meta.get("fd_usage_critical", "false") == "true",
        parse_error=parsed["parse_error"],
    )

    reasons = []

    if run.warmup_exit_code != 0:
        reasons.append(f"warmup-exit-{run.warmup_exit_code}")
    if run.wrk_exit_code != 0:
        reasons.append(f"loadgen-exit-{run.wrk_exit_code}")
    if not run.server_alive_before:
        reasons.append("server-dead-before")
    if not run.server_alive_after:
        reasons.append("server-dead-after")
    if meta.get("preflight_ok", "1") != "1":
        reasons.append("preflight-response")
    if meta.get("invalid_reason", ""):
        reasons.append(meta.get("invalid_reason", ""))
    if parsed["parse_error"]:
        reasons.append(parsed["parse_error"])
    if run.socket_errors > 0:
        reasons.append(f"socket-errors-{run.socket_errors}")
    if run.non2xx > 0:
        reasons.append(f"non2xx-{run.non2xx}")
    if run.p99_us > 0 and run.p50_us > 0 and run.p99_us < run.p50_us:
        reasons.append("p99-lower-than-p50")

    run.hard_invalid_reason = ",".join(reasons)
    return run

all_runs: list[Run] = []
summary_rows = []

for label in labels:
    for scenario in scenarios:
        for c in concurrency:
            group = []
            for rep in range(1, reps + 1):
                run = load_run(label, scenario, c, rep)
                if run is not None:
                    group.append(run)
                    all_runs.append(run)

            hard_valid = [r for r in group if r.hard_valid and r.rps > 0]

            if len(hard_valid) >= MIN_VALID_REPS_FOR_OUTLIER_FILTER:
                med_rps = statistics.median(r.rps for r in hard_valid)
                if med_rps > 0:
                    for r in hard_valid:
                        ratio = r.rps / med_rps
                        if ratio < LOW_RPS_RATIO:
                            r.soft_invalid_reason = f"low-rps-outlier-{ratio:.2f}x-median"
                        elif ratio > HIGH_RPS_RATIO:
                            r.soft_invalid_reason = f"high-rps-outlier-{ratio:.2f}x-median"

print("")
print("## Environment Preflight")
print("| Metric | Value |")
print("|---|---:|")
for key in ["os_name", "os_version", "cpu_model", "host_cpu_count", "env_policy", "environment_suspicious", "environment_invalid_reason"]:
    print(f"| {key} | {system_env.get(key, 'not_available')} |")

print("\n## FD / Socket Budget")
print("| Metric | Value |")
print("|---|---:|")
for key in ["soft_nofile", "hard_nofile", "launchctl_maxfiles_soft", "launchctl_maxfiles_hard", "kern_maxfiles", "kern_maxfilesperproc", "somaxconn", "max_concurrency_requested", "required_min_nofile", "required_better_nofile", "fd_limit_ok", "fd_better_ok", "backlog_ok", "ephemeral_port_first", "ephemeral_port_last", "ephemeral_port_count", "ephemeral_ports_ok", "keepalive_ephemeral_status", "connection_churn_ephemeral_status"]:
    print(f"| {key} | {system_env.get(key, 'not_available')} |")

print("\n## Load Generator Configuration")
print("| Metric | Value |")
print("|---|---:|")
for key in ["selected_loadgen", "loadgen_base", "loadgen_path", "loadgen_version", "loadgen_threads", "loadgen_duration", "loadgen_warmup", "latency_correction", "target_qps", "wrk_kqueue_capable", "wrk_lua_script", "wrk_lua_script_method", "wrk_lua_script_body_bytes"]:
    print(f"| {key} | {system_env.get(key, 'not_available')} |")

print("## Full Validation Matrix")
print("")
if mode in ("--mode=lua-bridge", "--mode=lua-bridge-smoke"):
    print("Lua bridge mode intentionally runs only Meteorite variants; public competitors are covered by --mode=public/--mode=smoke.")
elif mode == "--mode=work":
    print("Controlled work mode runs the same CPU/sleep endpoint shapes across contenders to audit load-generator active pressure; it is not the raw fast-path headline table.")
elif mode == "--mode=meteorite-app":
    print("Meteorite app mode is a Meteorite-only realistic Lua workload suite using JSON/template/SQLite libraries; it is not a fair framework comparison.")
else:
    print("Fair comparison set: meteorite-auto, hono-bun-multiprocess, go-nethttp, go-fiber-fasthttp, and rust-actix use their normal multi-core runtime. meteorite-1worker and hono-bun-single are diagnostic baselines, not headline fair-comparison rows.")
print("")
print(f"Outlier filter: discard hard failures, then discard RPS outside {LOW_RPS_RATIO:.2f}x–{HIGH_RPS_RATIO:.2f}x group median when at least {MIN_VALID_REPS_FOR_OUTLIER_FILTER} valid reps exist.")

for scenario in scenarios:
    scenario_runs = [r for r in all_runs if r.scenario == scenario]
    if scenario_runs and all(r.proof_only for r in scenario_runs):
        continue
    print(f"\n### Scenario: {scenario}")
    print("| Loadgen | Variant | Claim Class | Tier | Concurrency | Valid/Reps | RPS Median | p50 Median µs | p99 Median µs | Lua pcalls/request | Srv CPU% Max | Srv RSS MB | Notes |")
    print("|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")

    for c in concurrency:
        for label in labels:
            group = [
                r for r in all_runs
                if r.label == label and r.scenario == scenario and r.concurrency == c
            ]

            if not group:
                continue

            if all(r.proof_only for r in group):
                continue

            valid = [r for r in group if r.valid]
            discarded = [r for r in group if not r.valid]

            if valid:
                med_rps = statistics.median(r.rps for r in valid)
                med_latency_avg = median_attr(valid, "latency_avg_us")
                med_latency_stdev = median_attr(valid, "latency_stdev_us")
                med_latency_max = median_attr(valid, "latency_max_us")
                med_p50 = statistics.median(r.p50_us for r in valid)
                med_p75 = median_attr(valid, "p75_us")
                med_p90 = median_attr(valid, "p90_us")
                med_p99 = statistics.median(r.p99_us for r in valid)
                med_req_sec = median_attr(valid, "req_sec_avg")
                med_transfer = median_attr(valid, "transfer_per_sec_bytes")
                med_lua_ratio = statistics.median(r.lua_pcalls_per_request for r in valid)
                total_requests = sum_attr(valid, "requests")
                socket_connect = sum_attr(valid, "socket_connect_errors")
                socket_read = sum_attr(valid, "socket_read_errors")
                socket_write = sum_attr(valid, "socket_write_errors")
                socket_timeout = sum_attr(valid, "socket_timeout_errors")
                socket_errors = sum_attr(valid, "socket_errors")
                non2xx = sum_attr(valid, "non2xx")
                active_probe_supported = any(r.active_probe_supported for r in valid)
                accepted_delta = sum_attr(valid, "accepted_total_delta")
                completed_delta = sum_attr(valid, "completed_total_delta")
                open_connections_max = max((r.open_connections_max for r in valid), default=0)
                observed_inflight_max = max((r.inflight_max for r in valid), default=0)
                observed_queue_depth_max = max((r.queue_depth_max for r in valid), default=0)
                worker_queue_depth_max = max((r.worker_queue_depth_max for r in valid), default=0)
                queue_depth_current = max((r.queue_depth_current_after for r in valid), default=0)
                budget_capacity = max((r.budget_capacity for r in valid), default=0)
                budget_rejections = max((r.budget_rejections_total for r in valid), default=0)
                backpressure_total = max((r.backpressure_total for r in valid), default=0)
                server_fd_count_max = max((r.server_fd_count_max for r in valid), default=0)
                loadgen_fd_count_max = max((r.loadgen_fd_count_max for r in valid), default=0)
                fd_usage_high = any(r.fd_usage_high for r in valid)
                fd_usage_critical = any(r.fd_usage_critical for r in valid)
                tier = valid[0].tier
                claim_class = valid[0].claim_class
            else:
                med_rps = 0.0
                med_latency_avg = 0.0
                med_latency_stdev = 0.0
                med_latency_max = 0.0
                med_p50 = 0.0
                med_p75 = 0.0
                med_p90 = 0.0
                med_p99 = 0.0
                med_req_sec = 0.0
                med_transfer = 0.0
                med_lua_ratio = 0.0
                total_requests = 0
                socket_connect = socket_read = socket_write = socket_timeout = 0
                socket_errors = non2xx = 0
                active_probe_supported = False
                accepted_delta = completed_delta = 0
                open_connections_max = 0
                observed_inflight_max = observed_queue_depth_max = worker_queue_depth_max = queue_depth_current = 0
                budget_capacity = budget_rejections = backpressure_total = 0
                server_fd_count_max = loadgen_fd_count_max = 0
                fd_usage_high = fd_usage_critical = False
                tier = group[0].tier if group else "unknown"
                claim_class = group[0].claim_class if group else "unknown"

            row_source = valid[0] if valid else group[0]
            environment_reasons = []
            if row_source.environment_suspicious:
                environment_reasons.append("environment_quarantined")
            if not row_source.fd_limit_ok:
                environment_reasons.append(f"fd-limit {row_source.environment_invalid_reason}")
            if not row_source.backlog_ok:
                environment_reasons.append(f"backlog-below-requested-concurrency somaxconn={row_source.somaxconn}")
            if not row_source.ephemeral_ports_ok:
                environment_reasons.append("ephemeral-port-range-too-small")
            if fd_usage_high:
                environment_reasons.append("fd-usage-high")
            if fd_usage_critical:
                environment_reasons.append("fd-usage-critical")

            srv_cpu, srv_rss = read_server_stats(label)

            notes = ""
            if discarded:
                notes = "discarded " + ", ".join(
                    f"r{r.rep}:{r.reason}" for r in discarded
                )
            sanity_notes = latency_sanity_notes(c, med_rps, med_p99, med_latency_avg)
            implied_avg = implied_avg_latency_us(c, med_rps)
            p99_ratio = safe_ratio(med_p99, implied_avg)
            latency_avg_ratio = safe_ratio(med_latency_avg, implied_avg)
            configured_service_time_seconds = median_attr(valid, "configured_service_time_seconds") if valid else 0.0
            expected_inflight = med_rps * configured_service_time_seconds
            expected_observed_mismatch = bool(label.startswith("meteorite-") and expected_inflight >= 32 and observed_inflight_max < expected_inflight * 0.50)
            pressure_not_observed = configured_concurrency_not_observed(c, open_connections_max, active_probe_supported)
            hybrid_proof_invalid = invalid_hybrid_proof(tier, med_lua_ratio)
            corrected_latency = is_corrected_latency(selected_loadgen)
            target_qps = row_source.target_qps
            target_actual_ratio = safe_ratio(target_qps, med_rps)
            deadline_miss_latency_us = med_p99 if corrected_latency else 0.0
            audit_reasons = []
            if pressure_not_observed:
                audit_reasons.append(f"configured_concurrency_not_observed open_connections_max={open_connections_max} configured={c}")
            if expected_observed_mismatch:
                audit_reasons.append(f"expected_observed_mismatch expected_inflight={expected_inflight:.1f} observed_inflight_max={observed_inflight_max}")
            if hybrid_proof_invalid:
                audit_reasons.append(f"invalid_hybrid_proof lua_pcalls_per_request={med_lua_ratio:.2f}")
            if corrected_latency:
                audit_reasons.append("corrected_deadline_latency_not_closed_loop_response_latency")
            if row_source.parse_error:
                audit_reasons.append(f"loadgen_parser_error {row_source.parse_error}")
            claim_reasons = claim_grade_reasons(valid, discarded, sanity_notes, socket_errors, non2xx, environment_reasons + audit_reasons)
            latency_quarantined = len(sanity_notes) > 0
            environment_quarantined = len(environment_reasons) > 0
            claim_grade = len(claim_reasons) == 0
            if sanity_notes:
                notes = (notes + "; " if notes else "") + ", ".join(sanity_notes)
            if environment_reasons or audit_reasons:
                notes = (notes + "; " if notes else "") + ", ".join(environment_reasons + audit_reasons)

            summary_rows.append({
                "fixture": "bench-service",
                "mode": mode_name,
                "loadgen": selected_loadgen,
                "loadgen_version": row_source.loadgen_version,
                "loadgen_threads": row_source.loadgen_threads,
                "loadgen_concurrency": row_source.loadgen_concurrency,
                "latency_correction": selected_latency_correction,
                "latency_class": "oha-corrected deadline/CO-corrected latency" if corrected_latency else ("oha raw closed-loop latency" if selected_loadgen == "oha" else "wrk raw closed-loop latency"),
                "target_qps": target_qps,
                "target_actual_ratio": target_actual_ratio,
                "deadline_miss_latency_us": deadline_miss_latency_us,
                "configured_service_time_seconds": configured_service_time_seconds,
                "expected_inflight": expected_inflight,
                "expected_observed_mismatch": expected_observed_mismatch,
                "variant": label,
                "scenario": scenario,
                "meteorite_build_mode": row_source.meteorite_build_mode,
                "claim_class": claim_class,
                "tier": tier,
                "concurrency": c,
                "valid_reps": len(valid),
                "total_reps": len(group),
                "rps_median": med_rps,
                "latency_avg_us_median": med_latency_avg,
                "latency_stdev_us_median": med_latency_stdev,
                "latency_max_us_median": med_latency_max,
                "p50_us_median": med_p50,
                "p75_us_median": med_p75,
                "p90_us_median": med_p90,
                "p99_us_median": med_p99,
                "req_sec_avg_median": med_req_sec,
                "transfer_per_sec_bytes_median": med_transfer,
                "requests_total_valid": total_requests,
                "implied_avg_latency_us": implied_avg,
                "implied_avg_latency_ms": implied_avg / 1000.0,
                "p99_to_implied_ratio": p99_ratio,
                "latency_avg_to_implied_ratio": latency_avg_ratio,
                "latency_sanity_flags": sanity_notes,
                "socket_connect_errors": socket_connect,
                "socket_read_errors": socket_read,
                "socket_write_errors": socket_write,
                "socket_timeout_errors": socket_timeout,
                "socket_errors": socket_errors,
                "non2xx": non2xx,
                "active_probe_supported": active_probe_supported,
                "configured_concurrency": c,
                "accepted_total_delta": accepted_delta,
                "completed_total_delta": completed_delta,
                "open_connections_max": open_connections_max,
                "observed_open_connections_max": open_connections_max,
                "observed_inflight_max": observed_inflight_max,
                "inflight_max": observed_inflight_max,
                "queue_depth_current": queue_depth_current,
                "observed_queue_depth_max": observed_queue_depth_max,
                "queue_depth_max": observed_queue_depth_max,
                "worker_queue_depth_max": worker_queue_depth_max,
                "budget_capacity": budget_capacity,
                "budget_rejections_total": budget_rejections,
                "backpressure_total": backpressure_total,
                "soft_nofile": row_source.soft_nofile,
                "hard_nofile": row_source.hard_nofile,
                "somaxconn": row_source.somaxconn,
                "max_concurrency_requested": row_source.max_concurrency_requested,
                "fd_limit_ok": row_source.fd_limit_ok,
                "backlog_ok": row_source.backlog_ok,
                "ephemeral_ports_ok": row_source.ephemeral_ports_ok,
                "environment_suspicious": row_source.environment_suspicious,
                "environment_quarantined": environment_quarantined,
                "environment_invalid_reason": row_source.environment_invalid_reason,
                "server_fd_count_max": server_fd_count_max,
                "loadgen_fd_count_max": loadgen_fd_count_max,
                "fd_usage_high": fd_usage_high,
                "fd_usage_critical": fd_usage_critical,
                "configured_concurrency_not_observed": pressure_not_observed,
                "invalid_hybrid_proof": hybrid_proof_invalid,
                "loadgen_parser_error": row_source.parse_error,
                "lua_pcalls_per_request": med_lua_ratio,
                "latency_quarantined": latency_quarantined,
                "latency_quarantine_reasons": sanity_notes,
                "claim_grade": claim_grade,
                "claim_grade_reasons": claim_reasons,
                "compare": bool(valid[0].compare) if valid else bool(group[0].compare),
                "proof_only": bool(valid[0].proof_only) if valid else bool(group[0].proof_only),
                "validation": valid[0].validation if valid else group[0].validation,
                "notes": [r.reason for r in discarded if r.reason] + sanity_notes + environment_reasons + audit_reasons,
            })

            print(
                f"| {selected_loadgen} | {label} | {claim_class} | {tier} | {c} | {len(valid)}/{len(group)} | "
                f"{med_rps:,.0f} | {med_p50:.0f} | {med_p99:.0f} | "
                f"{med_lua_ratio:.2f} | {srv_cpu:.0f}% | {srv_rss:.1f} | {notes} |"
            )

if mode in ("--mode=lua-bridge", "--mode=lua-bridge-smoke"):
    print("\n## Native vs Thin Lua Delta")
    print("| Loadgen | Variant | Scenario | C | RPS Delta | p99 Delta µs | p99 Delta % |")
    print("|---|---|---|---:|---:|---:|---:|")
    thin_scenarios = {"lua-return-string", "lua-text-direct", "lua-direct-param", "lua-ctx-param", "lua-json-small"}
    by_key = {(row["variant"], row["scenario"], row["concurrency"]): row for row in summary_rows if row.get("compare")}
    for row in summary_rows:
        if row["scenario"] not in thin_scenarios or not row.get("compare"):
            continue
        base = by_key.get((row["variant"], "zig-static", row["concurrency"]))
        if not base or base["rps_median"] <= 0 or base["p99_us_median"] <= 0:
            continue
        rps_delta = ((row["rps_median"] / base["rps_median"]) - 1.0) * 100.0
        p99_delta_us = row["p99_us_median"] - base["p99_us_median"]
        p99_delta_pct = (p99_delta_us / base["p99_us_median"]) * 100.0
        print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {rps_delta:+.1f}% | {p99_delta_us:+.0f} | {p99_delta_pct:+.1f}% |")

claim_rows = [row for row in summary_rows if row.get("claim_grade") and row.get("compare") and not row.get("proof_only") and row.get("loadgen") != "oha-corrected"]
print("\n## Claim-Grade Headline Comparison")
print("Only raw closed-loop rows with no quarantine flags are included here. oha-corrected deadline latency is reported separately.")
print("| Loadgen | Variant | Scenario | C | RPS Median | p50 µs | p90 µs | p99 µs | Implied Avg µs | p99/Implied |")
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
if not claim_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 |")
else:
    for row in sorted(claim_rows, key=lambda r: (r["scenario"], r["concurrency"], r["variant"])):
        print(
            f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | "
            f"{row['rps_median']:,.0f} | {row['p50_us_median']:.0f} | {row['p90_us_median']:.0f} | {row['p99_us_median']:.0f} | "
            f"{row['implied_avg_latency_us']:.0f} | {row['p99_to_implied_ratio']:.2f} |"
        )

corrected_rows = [row for row in summary_rows if row.get("loadgen") == "oha-corrected"]
print("\n## Corrected Latency / Fixed Target QPS Audit")
print("oha-corrected values are deadline / coordinated-omission-corrected latency, not ordinary closed-loop response latency. If target QPS exceeds what configured concurrency can generate, corrected latency inflation is expected.")
print("| Variant | Scenario | C | Target QPS | Actual RPS | Target/Actual | Deadline p50 µs | Deadline p90 µs | Deadline p99 µs | Implied Avg µs | Open Conn Max | Inflight Max | Quarantine Reason |")
print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
if not corrected_rows:
    print("| n/a | n/a | 0 | 0 | 0 | 0.00 | 0 | 0 | 0 | 0 | 0 | 0 | none |")
else:
    for row in corrected_rows:
        reasons = row.get("claim_grade_reasons") or row.get("notes") or ["corrected-latency-audit"]
        print(
            f"| {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('target_qps', 0):.0f} | {row['rps_median']:,.0f} | {row.get('target_actual_ratio', 0):.2f} | "
            f"{row['p50_us_median']:.0f} | {row['p90_us_median']:.0f} | {row['p99_us_median']:.0f} | {row['implied_avg_latency_us']:.0f} | "
            f"{row.get('open_connections_max', 0)} | {row.get('observed_inflight_max', 0)} | {', '.join(reasons)} |"
        )

print("\n## Raw Loadgen Excerpt Summary")
print("| Loadgen | Latency Class | Variant | Scenario | C | Lat Avg µs | Lat Stdev µs | Lat Max µs | p50 µs | p75 µs | p90 µs | p99 µs | Req/Sec Avg | Requests | Transfer B/s | Socket connect/read/write/timeout | Implied Avg µs |")
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|")
for row in summary_rows:
    print(
        f"| {row['loadgen']} | {row.get('latency_class', 'raw closed-loop latency')} | {row['variant']} | {row['scenario']} | {row['concurrency']} | "
        f"{row['latency_avg_us_median']:.0f} | {row['latency_stdev_us_median']:.0f} | {row['latency_max_us_median']:.0f} | "
        f"{row['p50_us_median']:.0f} | {row['p75_us_median']:.0f} | {row['p90_us_median']:.0f} | {row['p99_us_median']:.0f} | "
        f"{row['req_sec_avg_median']:.0f} | {row['requests_total_valid']} | {row['transfer_per_sec_bytes_median']:.0f} | "
        f"{row['socket_connect_errors']}/{row['socket_read_errors']}/{row['socket_write_errors']}/{row['socket_timeout_errors']} | "
        f"{row['implied_avg_latency_us']:.0f} |"
    )

if mode == "--mode=work":
    work_rows = [row for row in summary_rows if str(row.get("scenario", "")).startswith("work-")]
    print("\n## Controlled Work Benchmark")
    print("Controlled CPU/sleep endpoints are isolated from raw fast-path framework comparisons.")
    print("| Loadgen | Variant | Scenario | C | Service Time s | RPS | p99 µs | Expected Inflight | Observed Open Max | Observed Inflight Max | Queue Max |")
    print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    if not work_rows:
        print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |")
    else:
        for row in work_rows:
            print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('configured_service_time_seconds', 0):.6f} | {row['rps_median']:,.0f} | {row['p99_us_median']:.0f} | {row.get('expected_inflight', 0):.1f} | {row.get('observed_open_connections_max', row.get('open_connections_max', 0))} | {row.get('observed_inflight_max', 0)} | {row.get('observed_queue_depth_max', 0)} |")

    mismatch_rows = [row for row in work_rows if row.get("expected_observed_mismatch")]
    print("\n## Harness Physics Validation")
    print("Meteorite rows flag expected_observed_mismatch when observed inflight is below 50% of RPS × configured service time and expected inflight is at least 32.")
    print("| Loadgen | Variant | Scenario | C | Expected Inflight | Observed Inflight Max | Status |")
    print("|---|---|---|---:|---:|---:|---|")
    if not mismatch_rows:
        print("| n/a | n/a | n/a | 0 | 0 | 0 | no Meteorite mismatches |")
    else:
        for row in mismatch_rows:
            print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('expected_inflight', 0):.1f} | {row.get('observed_inflight_max', 0)} | expected_observed_mismatch |")

    print("\n## Expected vs Observed Active Inflight")
    print("External contenders report process/socket diagnostics only; Meteorite active-pressure counters are the precise source for observed inflight.")
    print("| Loadgen | Variant | Scenario | C | Expected Inflight | Open Connections Max | Inflight Max | Queue Max |")
    print("|---|---|---|---:|---:|---:|---:|---:|")
    for row in work_rows:
        print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('expected_inflight', 0):.1f} | {row.get('observed_open_connections_max', row.get('open_connections_max', 0))} | {row.get('observed_inflight_max', 0)} | {row.get('observed_queue_depth_max', 0)} |")

    corrected_work_rows = [row for row in work_rows if row.get("loadgen") == "oha-corrected"]
    print("\n## Corrected Fixed-QPS Work Audit")
    print("oha-corrected work rows are deadline/schedule-lag tests, not ordinary closed-loop response-latency rows.")
    print("| Variant | Scenario | C | Target QPS | Actual RPS | Target/Actual | Deadline p99 µs | Expected Inflight | Observed Inflight Max |")
    print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
    if not corrected_work_rows:
        print("| n/a | n/a | 0 | 0 | 0 | 0.00 | 0 | 0 | 0 |")
    else:
        for row in corrected_work_rows:
            print(f"| {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('target_qps', 0):.0f} | {row['rps_median']:,.0f} | {row.get('target_actual_ratio', 0):.2f} | {row['p99_us_median']:.0f} | {row.get('expected_inflight', 0):.1f} | {row.get('observed_inflight_max', 0)} |")

if mode == "--mode=meteorite-app":
    app_rows = [row for row in summary_rows if str(row.get("scenario", "")).startswith("app-")]
    print("\n## Meteorite App Benchmark")
    print("Meteorite realistic Lua app workload using lua-cjson, etlua, and luasql-sqlite3. This is Meteorite-only and is not a fair Actix/Go/Bun comparison.")
    print("SQLite mode: memory")
    print("| Loadgen | Variant | Scenario | C | RPS | p50 µs | p99 µs | Lua pcalls/request | Claim Grade |")
    print("|---|---|---|---:|---:|---:|---:|---:|---|")
    if not app_rows:
        print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0.00 | false |")
    else:
        for row in app_rows:
            print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row['rps_median']:,.0f} | {row['p50_us_median']:.0f} | {row['p99_us_median']:.0f} | {row.get('lua_pcalls_per_request', 0):.2f} | {row.get('claim_grade')} |")

    print("\n## Meteorite App Correctness Checks")
    print("Every app route is body-preflighted, checks no socket/non-2xx errors, consumes stats after each rep, and requires lua_pcalls/request >= 0.95.")
    print("| Scenario | Proof |")
    print("|---|---|")
    proofs = {
        "app-json-encode-small": "lua-cjson encode/decode field correctness",
        "app-json-decode-1kb": "lua-cjson decode 1KB payload field correctness",
        "app-json-roundtrip-1kb": "lua-cjson decode/encode/decode payload length correctness",
        "app-template-hello": "etlua stable rendered body",
        "app-template-list-100": "etlua stable list render length/prefix",
        "app-sqlite-select-one": "luasql-sqlite3 expected selected value",
        "app-sqlite-select-100": "luasql-sqlite3 expected row count",
        "app-sqlite-insert-small": "luasql-sqlite3 insert count delta with cleanup",
        "app-pipeline-cors": "Lua pipeline route proof",
        "app-pipeline-cors-json-template": "lua-cjson + etlua combined proof",
        "app-full-sqlite-json-template": "luasql-sqlite3 + lua-cjson + etlua combined proof",
    }
    for scenario in scenarios:
        if scenario.startswith("app-"):
            print(f"| {scenario} | {proofs.get(scenario, 'Lua app proof')} |")

print("\n## FD Usage During Runs")
print("| Loadgen | Variant | Scenario | C | Soft nofile | Server FD Max | Loadgen FD Max | FD Usage High | FD Usage Critical | Headroom |")
print("|---|---|---|---:|---:|---:|---:|---|---|---:|")
if not summary_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | false | false | 0 |")
else:
    for row in summary_rows:
        try:
            soft = int(str(row.get("soft_nofile") or "0"))
        except Exception:
            soft = 0
        used = max(int(row.get("server_fd_count_max") or 0), int(row.get("loadgen_fd_count_max") or 0))
        headroom = soft - used if soft > 0 else 0
        print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('soft_nofile', 'n/a')} | {row.get('server_fd_count_max', 0)} | {row.get('loadgen_fd_count_max', 0)} | {row.get('fd_usage_high')} | {row.get('fd_usage_critical')} | {headroom} |")

env_rows = [row for row in summary_rows if row.get("environment_quarantined") or row.get("environment_suspicious")]
print("\n## Environment-Quarantined Rows")
print("Rows here are excluded from headline claims because OS/loadgen limits may constrain the requested concurrency.")
print("| Loadgen | Variant | Scenario | C | Soft nofile | somaxconn | FD OK | Backlog OK | Ephemeral OK | Reason |")
print("|---|---|---|---:|---:|---:|---|---|---|---|")
if not env_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | true | true | true | none |")
else:
    for row in env_rows:
        print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row.get('soft_nofile', 'n/a')} | {row.get('somaxconn', 'n/a')} | {row.get('fd_limit_ok')} | {row.get('backlog_ok')} | {row.get('ephemeral_ports_ok')} | {row.get('environment_invalid_reason', 'none')} |")

latency_flag_rows = [row for row in summary_rows if row.get("latency_sanity_flags")]
print("\n## Latency Sanity Flags")
print("| Loadgen | Variant | Scenario | C | RPS | p99 µs | Implied Avg µs | Flags |")
print("|---|---|---|---:|---:|---:|---:|---|")
if not latency_flag_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | none |")
else:
    for row in latency_flag_rows:
        print(f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['concurrency']} | {row['rps_median']:,.0f} | {row['p99_us_median']:.0f} | {row['implied_avg_latency_us']:.0f} | {', '.join(row.get('latency_sanity_flags', []))} |")

audit_rows = [row for row in summary_rows if not row.get("claim_grade") and not row.get("proof_only")]
print("\n## Claim-Quarantined Rows")
print("Rows here are preserved for RPS/stability/audit value but excluded from headline latency claims until the quarantine reason is resolved.")
print("| Loadgen | Variant | Scenario | Configured C | Open Connections Max | Observed Inflight Max | Observed Queue Max | Worker Queue Max | RPS | Reported p99 µs | Implied Avg µs | Avg/Implied | p99/Implied | Reason |")
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
if not audit_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | none |")
else:
    for row in audit_rows:
        reasons = row.get("latency_quarantine_reasons") or row.get("claim_grade_reasons") or ["not-claim-grade"]
        print(
            f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['configured_concurrency']} | "
            f"{row.get('observed_open_connections_max', row.get('open_connections_max', 0))} | {row['observed_inflight_max']} | {row['observed_queue_depth_max']} | {row['worker_queue_depth_max']} | "
            f"{row['rps_median']:,.0f} | {row['p99_us_median']:.0f} | {row['implied_avg_latency_us']:.0f} | "
            f"{row['latency_avg_to_implied_ratio']:.2f} | {row['p99_to_implied_ratio']:.2f} | {', '.join(reasons)} |"
        )

probe_rows = [row for row in summary_rows if row.get("active_probe_supported")]
print("\n## Meteorite Active Pressure")
print("Meteorite rows report how many requests were actually inside the server during each measured window.")
print("| Loadgen | Variant | Scenario | Configured C | Open Connections Max | Inflight Requests Max | Queue Current | Queue Max | Worker Queue Max | Budget Capacity | Budget Rejections | Backpressure | Accepted Δ | Completed Δ | RPS | Reported p99 µs | Implied Avg µs |")
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
if not probe_rows:
    print("| n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |")
else:
    for row in probe_rows:
        print(
            f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['configured_concurrency']} | "
            f"{row.get('open_connections_max', row['observed_inflight_max'])} | {row['observed_inflight_max']} | {row['queue_depth_current']} | {row['observed_queue_depth_max']} | {row['worker_queue_depth_max']} | "
            f"{row.get('budget_capacity', 0)} | {row.get('budget_rejections_total', 0)} | {row.get('backpressure_total', 0)} | "
            f"{row['accepted_total_delta']} | {row['completed_total_delta']} | {row['rps_median']:,.0f} | "
            f"{row['p99_us_median']:.0f} | {row['implied_avg_latency_us']:.0f} |"
        )

suspicious = [r for r in all_runs if not r.valid]

proof_runs = [r for r in all_runs if r.proof_only]
if proof_runs:
    print("\n## Proof-Only Routes")
    print("| Loadgen | Variant | Scenario | Claim Class | Tier | C | Valid/Reps | RPS Median | p99 Median µs | Lua pcalls/request | Validation | Notes |")
    print("|---|---|---|---|---|---:|---:|---:|---:|---:|---|---|")
    proof_keys = sorted({(r.label, r.scenario, r.concurrency) for r in proof_runs})
    for label, scenario, c in proof_keys:
        group = [r for r in proof_runs if r.label == label and r.scenario == scenario and r.concurrency == c]
        valid = [r for r in group if r.valid]
        discarded = [r for r in group if not r.valid]
        med_rps = statistics.median([r.rps for r in valid]) if valid else 0.0
        med_latency_avg = median_attr(valid, "latency_avg_us") if valid else 0.0
        med_latency_stdev = median_attr(valid, "latency_stdev_us") if valid else 0.0
        med_latency_max = median_attr(valid, "latency_max_us") if valid else 0.0
        med_p50 = statistics.median([r.p50_us for r in valid]) if valid else 0.0
        med_p75 = median_attr(valid, "p75_us") if valid else 0.0
        med_p90 = median_attr(valid, "p90_us") if valid else 0.0
        med_p99 = statistics.median([r.p99_us for r in valid]) if valid else 0.0
        med_req_sec = median_attr(valid, "req_sec_avg") if valid else 0.0
        med_transfer = median_attr(valid, "transfer_per_sec_bytes") if valid else 0.0
        med_lua_ratio = statistics.median([r.lua_pcalls_per_request for r in valid]) if valid else 0.0
        socket_connect = sum_attr(valid, "socket_connect_errors") if valid else 0
        socket_read = sum_attr(valid, "socket_read_errors") if valid else 0
        socket_write = sum_attr(valid, "socket_write_errors") if valid else 0
        socket_timeout = sum_attr(valid, "socket_timeout_errors") if valid else 0
        socket_errors = sum_attr(valid, "socket_errors") if valid else 0
        non2xx = sum_attr(valid, "non2xx") if valid else 0
        active_probe_supported = any(r.active_probe_supported for r in valid)
        accepted_delta = sum_attr(valid, "accepted_total_delta") if valid else 0
        completed_delta = sum_attr(valid, "completed_total_delta") if valid else 0
        open_connections_max = max((r.open_connections_max for r in valid), default=0)
        observed_inflight_max = max((r.inflight_max for r in valid), default=0)
        observed_queue_depth_max = max((r.queue_depth_max for r in valid), default=0)
        worker_queue_depth_max = max((r.worker_queue_depth_max for r in valid), default=0)
        queue_depth_current = max((r.queue_depth_current_after for r in valid), default=0)
        budget_capacity = max((r.budget_capacity for r in valid), default=0)
        budget_rejections = max((r.budget_rejections_total for r in valid), default=0)
        backpressure_total = max((r.backpressure_total for r in valid), default=0)
        server_fd_count_max = max((r.server_fd_count_max for r in valid), default=0)
        loadgen_fd_count_max = max((r.loadgen_fd_count_max for r in valid), default=0)
        fd_usage_high = any(r.fd_usage_high for r in valid)
        fd_usage_critical = any(r.fd_usage_critical for r in valid)
        tier = group[0].tier if group else "unknown"
        claim_class = group[0].claim_class if group else "unknown"
        validation = group[0].validation if group else ""
        row_source = valid[0] if valid else group[0]
        environment_reasons = []
        if row_source.environment_suspicious:
            environment_reasons.append("environment_quarantined")
        if not row_source.fd_limit_ok:
            environment_reasons.append(f"fd-limit {row_source.environment_invalid_reason}")
        if not row_source.backlog_ok:
            environment_reasons.append(f"backlog-below-requested-concurrency somaxconn={row_source.somaxconn}")
        if not row_source.ephemeral_ports_ok:
            environment_reasons.append("ephemeral-port-range-too-small")
        if fd_usage_high:
            environment_reasons.append("fd-usage-high")
        if fd_usage_critical:
            environment_reasons.append("fd-usage-critical")
        notes = ", ".join(f"r{r.rep}:{r.reason}" for r in discarded if r.reason)
        sanity_notes = latency_sanity_notes(c, med_rps, med_p99, med_latency_avg)
        implied_avg = implied_avg_latency_us(c, med_rps)
        p99_ratio = safe_ratio(med_p99, implied_avg)
        latency_avg_ratio = safe_ratio(med_latency_avg, implied_avg)
        configured_service_time_seconds = median_attr(valid, "configured_service_time_seconds") if valid else 0.0
        expected_inflight = med_rps * configured_service_time_seconds
        expected_observed_mismatch = bool(label.startswith("meteorite-") and expected_inflight >= 32 and observed_inflight_max < expected_inflight * 0.50)
        pressure_not_observed = configured_concurrency_not_observed(c, open_connections_max, active_probe_supported)
        hybrid_proof_invalid = invalid_hybrid_proof(tier, med_lua_ratio)
        corrected_latency = is_corrected_latency(selected_loadgen)
        target_qps = row_source.target_qps
        target_actual_ratio = safe_ratio(target_qps, med_rps)
        deadline_miss_latency_us = med_p99 if corrected_latency else 0.0
        audit_reasons = []
        if pressure_not_observed:
            audit_reasons.append(f"configured_concurrency_not_observed open_connections_max={open_connections_max} configured={c}")
        if expected_observed_mismatch:
            audit_reasons.append(f"expected_observed_mismatch expected_inflight={expected_inflight:.1f} observed_inflight_max={observed_inflight_max}")
        if hybrid_proof_invalid:
            audit_reasons.append(f"invalid_hybrid_proof lua_pcalls_per_request={med_lua_ratio:.2f}")
        if corrected_latency:
            audit_reasons.append("corrected_deadline_latency_not_closed_loop_response_latency")
        if row_source.parse_error:
            audit_reasons.append(f"loadgen_parser_error {row_source.parse_error}")
        claim_reasons = claim_grade_reasons(valid, discarded, sanity_notes, socket_errors, non2xx, environment_reasons + audit_reasons)
        latency_quarantined = len(sanity_notes) > 0
        environment_quarantined = len(environment_reasons) > 0
        claim_grade = len(claim_reasons) == 0
        if sanity_notes:
            notes = (notes + "; " if notes else "") + ", ".join(sanity_notes)
        if environment_reasons or audit_reasons:
            notes = (notes + "; " if notes else "") + ", ".join(environment_reasons + audit_reasons)
        print(f"| {selected_loadgen} | {label} | {scenario} | {claim_class} | {tier} | {c} | {len(valid)}/{len(group)} | {med_rps:,.0f} | {med_p99:.0f} | {med_lua_ratio:.2f} | {validation} | {notes} |")
        summary_rows.append({
            "fixture": "bench-service",
            "mode": mode_name,
            "loadgen": selected_loadgen,
            "loadgen_version": row_source.loadgen_version,
            "loadgen_threads": row_source.loadgen_threads,
            "loadgen_concurrency": row_source.loadgen_concurrency,
            "latency_correction": selected_latency_correction,
            "latency_class": "oha-corrected deadline/CO-corrected latency" if corrected_latency else ("oha raw closed-loop latency" if selected_loadgen == "oha" else "wrk raw closed-loop latency"),
            "target_qps": target_qps,
            "target_actual_ratio": target_actual_ratio,
            "deadline_miss_latency_us": deadline_miss_latency_us,
            "configured_service_time_seconds": configured_service_time_seconds,
            "expected_inflight": expected_inflight,
            "expected_observed_mismatch": expected_observed_mismatch,
            "variant": label,
            "scenario": scenario,
            "meteorite_build_mode": row_source.meteorite_build_mode,
            "claim_class": claim_class,
            "tier": tier,
            "concurrency": c,
            "valid_reps": len(valid),
            "total_reps": len(group),
            "rps_median": med_rps,
            "latency_avg_us_median": med_latency_avg,
            "latency_stdev_us_median": med_latency_stdev,
            "latency_max_us_median": med_latency_max,
            "p50_us_median": med_p50,
            "p75_us_median": med_p75,
            "p90_us_median": med_p90,
            "p99_us_median": med_p99,
            "req_sec_avg_median": med_req_sec,
            "transfer_per_sec_bytes_median": med_transfer,
            "requests_total_valid": sum_attr(valid, "requests") if valid else 0,
            "implied_avg_latency_us": implied_avg,
            "implied_avg_latency_ms": implied_avg / 1000.0,
            "p99_to_implied_ratio": p99_ratio,
            "latency_avg_to_implied_ratio": latency_avg_ratio,
            "latency_sanity_flags": sanity_notes,
            "socket_connect_errors": socket_connect,
            "socket_read_errors": socket_read,
            "socket_write_errors": socket_write,
            "socket_timeout_errors": socket_timeout,
            "socket_errors": socket_errors,
            "non2xx": non2xx,
            "active_probe_supported": active_probe_supported,
            "configured_concurrency": c,
            "accepted_total_delta": accepted_delta,
            "completed_total_delta": completed_delta,
            "open_connections_max": open_connections_max,
            "observed_open_connections_max": open_connections_max,
            "observed_inflight_max": observed_inflight_max,
            "inflight_max": observed_inflight_max,
            "queue_depth_current": queue_depth_current,
            "observed_queue_depth_max": observed_queue_depth_max,
            "queue_depth_max": observed_queue_depth_max,
            "worker_queue_depth_max": worker_queue_depth_max,
            "budget_capacity": budget_capacity,
            "budget_rejections_total": budget_rejections,
            "backpressure_total": backpressure_total,
            "soft_nofile": row_source.soft_nofile,
            "hard_nofile": row_source.hard_nofile,
            "somaxconn": row_source.somaxconn,
            "max_concurrency_requested": row_source.max_concurrency_requested,
            "fd_limit_ok": row_source.fd_limit_ok,
            "backlog_ok": row_source.backlog_ok,
            "ephemeral_ports_ok": row_source.ephemeral_ports_ok,
            "environment_suspicious": row_source.environment_suspicious,
            "environment_quarantined": environment_quarantined,
            "environment_invalid_reason": row_source.environment_invalid_reason,
            "server_fd_count_max": server_fd_count_max,
            "loadgen_fd_count_max": loadgen_fd_count_max,
            "fd_usage_high": fd_usage_high,
            "fd_usage_critical": fd_usage_critical,
            "configured_concurrency_not_observed": pressure_not_observed,
            "invalid_hybrid_proof": hybrid_proof_invalid,
            "loadgen_parser_error": row_source.parse_error,
            "lua_pcalls_per_request": med_lua_ratio,
            "latency_quarantined": latency_quarantined,
            "latency_quarantine_reasons": sanity_notes,
            "claim_grade": claim_grade,
            "claim_grade_reasons": claim_reasons,
            "compare": False,
            "proof_only": True,
            "validation": validation,
            "notes": [r.reason for r in discarded if r.reason] + sanity_notes + environment_reasons + audit_reasons,
        })

if suspicious:
    print("\n## Discarded / Suspicious Reps")
    print("| Loadgen | Variant | Scenario | C | Rep | RPS | p50 µs | p99 µs | Requests | Lua pcalls | Reason |")
    print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|")

    for r in suspicious:
        print(
            f"| {r.loadgen} | {r.label} | {r.scenario} | {r.concurrency} | {r.rep} | "
            f"{r.rps:,.0f} | {r.p50_us:.0f} | {r.p99_us:.0f} | "
            f"{r.requests} | {r.lua_pcalls_delta} | {r.reason} |"
        )
else:
    print("\n## Discarded / Suspicious Reps")
    print("")
    print("None.")

print("\n## Correctness Checks")
print("fixture ok: enforced for every Meteorite variant before load generation")
print("route/body preflight ok: enforced for every configured scenario")
if mode in ("--mode=lua-bridge", "--mode=lua-bridge-smoke"):
    print("dynamic Lua proof ok: echo, state counter, and 1s Lua sleep route preflighted")
print("pcall/request ratio ok: enforced per measured rep")

print("\n## Claim Class Summary")
print("| Loadgen | Claim Class | Valid reps | Median Lua pcalls/request | Median RPS |")
print("|---|---|---:|---:|---:|")
for claim_class in sorted({r.claim_class for r in all_runs}):
    valid_class = [r for r in all_runs if r.claim_class == claim_class and r.valid]
    if not valid_class:
        print(f"| {selected_loadgen} | {claim_class} | 0 | 0.00 | 0 |")
        continue
    print(
        f"| {selected_loadgen} | {claim_class} | {len(valid_class)} | "
        f"{statistics.median([r.lua_pcalls_per_request for r in valid_class]):.2f} | "
        f"{statistics.median([r.rps for r in valid_class]):,.0f} |"
    )

print("\n## Execution Tier Summary")
print("| Loadgen | Tier | Valid reps | Median Lua pcalls/request | Median RPS |")
print("|---|---|---:|---:|---:|")
for tier in sorted({r.tier for r in all_runs}):
    valid_tier = [r for r in all_runs if r.tier == tier and r.valid]
    if not valid_tier:
        print(f"| {selected_loadgen} | {tier} | 0 | 0.00 | 0 |")
        continue
    print(
        f"| {selected_loadgen} | {tier} | {len(valid_tier)} | "
        f"{statistics.median([r.lua_pcalls_per_request for r in valid_tier]):.2f} | "
        f"{statistics.median([r.rps for r in valid_tier]):,.0f} |"
    )

claim_audit_rows = []
for row in summary_rows:
    reasons = row.get("claim_grade_reasons") or row.get("notes") or []
    if isinstance(reasons, str):
        reasons = [reasons]
    claim_audit_rows.append({
        "loadgen": row.get("loadgen", selected_loadgen),
        "variant": row.get("variant", "unknown"),
        "scenario": row.get("scenario", "unknown"),
        "meteorite_build_mode": row.get("meteorite_build_mode", meteorite_build_mode),
        "claim_class": row.get("claim_class", "unknown"),
        "tier": row.get("tier", "unknown"),
        "validation": row.get("validation", ""),
        "claim_grade": row.get("claim_grade", False),
        "proof_only": row.get("proof_only", False),
        "reasons": reasons,
    })

claim_audit_lines = [
    "# Benchmark Claim Audit",
    "",
    f"Mode: `{mode_name}`",
    f"Loadgen: `{selected_loadgen}`",
    f"Meteorite build mode: `{meteorite_build_mode}`",
    "",
    "Claim classes use `static`, `hybrid(lua-runtime)`, `framework-parity`, or `proof-only`; the report avoids the ambiguous `native` label for benchmark claims.",
    "",
    "| Loadgen | Variant | Scenario | Meteorite Build Mode | Claim Class | Tier | Validation | Claim Grade | Proof Only | Reasons |",
    "|---|---|---|---|---|---|---|---:|---:|---|",
]
for row in sorted(claim_audit_rows, key=lambda r: (r["scenario"], r["variant"], r["loadgen"])):
    reasons = ", ".join(str(reason) for reason in row["reasons"] if str(reason)) or "ok"
    claim_audit_lines.append(
        f"| {row['loadgen']} | {row['variant']} | {row['scenario']} | {row['meteorite_build_mode']} | {row['claim_class']} | {row['tier']} | {row['validation']} | {row['claim_grade']} | {row['proof_only']} | {reasons} |"
    )
(out / "claim-audit.md").write_text("\n".join(claim_audit_lines) + "\n")

(out / "summary.json").write_text(json.dumps({
    "fixture": "bench-service",
    "mode": mode_name,
    "loadgen": selected_loadgen,
    "latency_correction": selected_latency_correction,
    "meteorite_build_mode": meteorite_build_mode,
    "latency_unit": "microseconds",
    "environment": system_env,
    "claim_audit": claim_audit_rows,
    "results": summary_rows,
}, indent=2, sort_keys=True) + "\n")
