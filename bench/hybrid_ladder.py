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


def parse_oha(path):
    obj = load_json(path)
    summary = obj.get('summary', {}) if isinstance(obj, dict) else {}
    rps = find_metric(summary, ['requestsPerSec', 'requests_per_sec', 'requestRate', 'throughput'])
    if rps is None:
        rps = find_metric(obj, ['requestsPerSec', 'requests_per_sec', 'requestRate', 'throughput'])
    return as_num(rps)


def peak(result_dir, scenario):
    best = None
    for path in Path(result_dir).glob(f'{scenario}-oha-c*.json'):
        if '-q' in path.name:
            continue
        val = parse_oha(path)
        if val is not None and (best is None or val > best):
            best = val
    return best


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
    print('| Rung | Route | Peak req/s | Handler kind | Requires Lua | Lua state strategy | Backend strategy | Workers |')
    print('|---|---|---:|---|---:|---|---|---:|')
    for label, route, rps, info in rows:
        requires_lua = 'yes' if 'inline_lua' in label else ('no' if label.startswith('Meteorite') else 'n/a')
        handler_kind = 'inline_lua' if 'inline_lua' in label else ('static_zig' if label.startswith('Meteorite') else 'hono')
        print(f"| {label} | `{route}` | {fmt(rps)} | {handler_kind} | {requires_lua} | {info.get('lua_state_strategy','n/a')} | {info.get('connection_strategy', info.get('backend','n/a'))} | {info.get('fast_http_workers','n/a')} |")
    print()
    trivial = peak(hybrid_dir, 'hybrid-inline-bench') or 0
    text = peak(hybrid_dir, 'hybrid-inline-text-literal') or 0
    params = peak(hybrid_dir, 'hybrid-inline-params') or 0
    echo = peak(hybrid_dir, 'hybrid-inline-echo') or 0
    static = peak(static_dir, 'plain-static') or 0
    hz = peak(hybrid_dir, 'hybrid-zig') or 0
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
    print('- If static_zig remains high but all inline Lua rungs fall together, attribute to Lua call/bridge/state strategy rather than router/backend.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
