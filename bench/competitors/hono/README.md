# Hono competitor for Meteorite benchmarks

Run with Bun:

```bash
cd bench/competitors/hono
bun install
bun run server.ts
```

Run with Node:

```bash
cd bench/competitors/hono
npm install --ignore-scripts
node --enable-source-maps server-node.mjs
```

Default port is 8081; set `PORT` env to override.

The benchmark harness intentionally tracks only this source and its exact
dependency declarations. Do not commit `node_modules/`; regenerate it locally
before running comparisons.
