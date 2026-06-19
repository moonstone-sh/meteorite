#!/usr/bin/env python3
import json, re, sys
from pathlib import Path


def load_json(path):
    try:
        return json.load(open(path, encoding='utf-8'))
    except Exception:
        return {}


def find_metric(obj, names):
    if isinstance(obj, dict):
        for n in names:
            if n in obj:
                return obj[n]
        for v in obj.values():
            r = find_metric(v, names)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_metric(v, names)
            if r is not None:
                return r
    return None


def as_num(v):
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        m = re.search(r"-?\d+(?:\.\d+)?", v.replace(',', ''))
        if m:
            return float(m.group(0))
    return None


def fmt(v):
    v = as_num(v)
    return 'n/a' if v is None else f'{v:,.0f}'


def latency_value(obj, percentile):
    value = find_metric(obj, [percentile, percentile.upper()])
    if value is not None:
        return value
    percentiles = find_metric(obj, ["latencyPercentiles", "latency_percentiles", "percentiles"])
    if isinstance(percentiles, dict):
        for key in [percentile, percentile.upper(), percentile[1:], str(float(percentile[1:]))]:
            if key in percentiles:
                return percentiles[key]
    return None


def fmt_latency(value):
    number = as_num(value)
    if number is None:
        return "n/a"
    if number < 10:
        number *= 1000
    return f"{number:.3f} ms"


def parse_oha(path):
    obj = load_json(path)
    summary = obj.get('summary', {}) if isinstance(obj, dict) else {}
    rps = find_metric(summary, ['requestsPerSec', 'requests_per_sec', 'requestRate', 'throughput'])
    if rps is None:
        rps = find_metric(obj, ['requestsPerSec', 'requests_per_sec', 'requestRate', 'throughput'])
    match = re.match(r"(.+)-oha-c(\d+)(?:-q\d+)?\.json$", path.name)
    concurrency = match.group(2) if match else "n/a"
    return {
        'rps': as_num(rps),
        'p50': latency_value(obj, 'p50'),
        'p95': latency_value(obj, 'p95'),
        'p99': latency_value(obj, 'p99'),
        'max': find_metric(obj, ['max', 'slowest', 'maxLatency', 'max_latency']),
        'concurrency': concurrency,
    }


def peak(result_dir, scenario):
    best = None
    best_path = None
    for path in Path(result_dir).glob(f'{scenario}-oha-c*.json'):
        if '-q' in path.name:
            continue
        parsed = parse_oha(path)
        if parsed['rps'] is not None and (best is None or parsed['rps'] > best['rps']):
            best = parsed
            best_path = path
    return best if best else {'rps': None, 'p50': None, 'p95': None, 'p99': None, 'max': None, 'concurrency': None}


def meta(result_dir):
    return load_json(Path(result_dir) / 'build-info.json')


def main(args):
    if len(args) != 3:
        print('usage: hybrid_ladder.py STATIC_DIR HYBRID_DIR HONO_DIR', file=sys.stderr)
        return 2
    static_dir, hybrid_dir, hono_dir = args
    m_static = meta(static_dir)
    m_hybrid = meta(hybrid_dir)
    rows = [
        ('Meteorite release-static static_zig', '/__bench/plain-static', peak(static_dir, 'plain-static'), m_static),
        ('Meteorite release-hybrid static_zig', '/__bench/hybrid-zig', peak(hybrid_dir, 'hybrid-zig'), m_hybrid),
        ('Meteorite release-hybrid inline_lua trivial', '/__bench/hybrid-inline', peak(hybrid_dir, 'hybrid-inline-bench'), m_hybrid),
        ('Meteorite release-hybrid inline_lua c:text', '/__bench/hybrid-inline-text-literal', peak(hybrid_dir, 'hybrid-inline-text-literal'), m_hybrid),
        ('Meteorite release-hybrid inline_lua params', '/__bench/hybrid-inline-params/123', peak(hybrid_dir, 'hybrid-inline-params'), m_hybrid),
        ('Meteorite release-hybrid inline_lua echo', 'POST /__bench/hybrid-inline-echo', peak(hybrid_dir, 'hybrid-inline-echo'), m_hybrid),
        ('Hono Bun plain/static equivalent', '/__bench/plain-static', peak(hono_dir, 'plain-static'), meta(hono_dir)),
        ('Hono Bun inline equivalent', '/__bench/hybrid-inline', peak(hono_dir, 'hybrid-inline-bench'), meta(hono_dir)),
        ('Hono Bun params equivalent', '/__bench/hybrid-inline-params/123', peak(hono_dir, 'hybrid-inline-params'), meta(hono_dir)),
        ('Hono Bun echo equivalent', 'POST /__bench/hybrid-inline-echo', peak(hono_dir, 'hybrid-inline-echo'), meta(hono_dir)),
    ]
    print('# Hybrid Ladder')
    print()
    print('| Rung | Route | Peak req/s | p50 (ms) | p95 (ms) | p99 (ms) | Handler kind | Requires Lua | Lua state strategy | Backend strategy | Workers |')
    print('|---|---|---:|---:|---:|---:|---|---:|---|---|---:|')
    for label, route, data, info in rows:
        requires_lua = 'yes' if 'inline_lua' in label else ('no' if label.startswith('Meteorite') else 'n/a')
        handler_kind = 'inline_lua' if 'inline_lua' in label else ('static_zig' if label.startswith('Meteorite') else 'hono')
        print(f"| {label} | `{route}` | {fmt(data['rps'])} | {fmt_latency(data['p50'])} | {fmt_latency(data['p95'])} | {fmt_latency(data['p99'])} | {handler_kind} | {requires_lua} | {info.get('lua_state_strategy','n/a')} | {info.get('connection_strategy', info.get('backend','n/a'))} | {info.get('fast_http_workers','n/a')} |")
    print()
    trivial = peak(hybrid_dir, 'hybrid-inline-bench')['rps'] or 0
    text = peak(hybrid_dir, 'hybrid-inline-text-literal')['rps'] or 0
    params = peak(hybrid_dir, 'hybrid-inline-params')['rps'] or 0
    echo = peak(hybrid_dir, 'hybrid-inline-echo')['rps'] or 0
    static = peak(static_dir, 'plain-static')['rps'] or 0
    hz = peak(hybrid_dir, 'hybrid-zig')['rps'] or 0
    hono_trivial = peak(hono_dir, 'hybrid-inline-bench')
    hono_params = peak(hono_dir, 'hybrid-inline-params')
    hono_echo = peak(hono_dir, 'hybrid-inline-echo')
    print('## Attribution Hints')
    print()
    if static and hz:
        print(f'- Hybrid static_zig vs release-static: {hz/static*100:.1f}% of static baseline.')
    if trivial and text:
        print(f'- `ctx:text` bridge route vs return-string route: {text/trivial*100:.1f}%.')
    if trivial and params:
        print(f'- Params materialization route vs trivial inline Lua: {params/trivial*100:.1f}%.')
    if trivial and echo:
        print(f'- Echo/body route vs trivial inline Lua: {echo/trivial*100:.1f}%.')
    if trivial and hono_trivial['rps']:
        ratio = hono_trivial['rps'] / trivial
        print(f'- Hono Bun /__bench/hybrid-inline req/s is {ratio*100:.1f}% of Meteorite hybrid trivial; Hono p99 = {fmt_latency(hono_trivial["p99"])}, Meteorite p99 = {fmt_latency(peak(hybrid_dir, "hybrid-inline-bench")["p99"])}.')
    if params and hono_params['rps']:
        ratio = hono_params['rps'] / params
        print(f'- Hono Bun /__bench/hybrid-inline-params/123 req/s is {ratio*100:.1f}% of Meteorite hybrid params; Hono p99 = {fmt_latency(hono_params["p99"])}, Meteorite p99 = {fmt_latency(peak(hybrid_dir, "hybrid-inline-params")["p99"])}.')
    if echo and hono_echo['rps']:
        ratio = hono_echo['rps'] / echo
        print(f'- Hono Bun POST /__bench/hybrid-inline-echo req/s is {ratio*100:.1f}% of Meteorite hybrid echo; Hono p99 = {fmt_latency(hono_echo["p99"])}, Meteorite p99 = {fmt_latency(peak(hybrid_dir, "hybrid-inline-echo")["p99"])}.')
    print('- If static_zig remains high but all inline Lua rungs fall together, attribute to Lua call/bridge/state strategy rather than router/backend.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
