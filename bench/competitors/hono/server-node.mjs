import { Hono } from 'hono'
import { serve } from '@hono/node-server'

const app = new Hono()
const devicePattern = /^[a-z0-9_-]{1,64}$/
const filePattern = /^[a-z0-9_.-]{1,80}$/

app.get('/__bench/meta', (c) => c.json({
  framework: 'hono',
  runtime: 'node',
  backend: 'node-http',
  meteorite_mode: 'n/a',
  zig_optimize: 'n/a',
  target: 'n/a',
  lua_runtime: 'n/a',
  hybrid_profile: 'n/a',
}))
app.get('/__bench/plain', (c) => c.text('ok'))
app.get('/health', (c) => c.text('ok'))
app.get('/users/:id', (c) => {
  const id = Number(c.req.param('id'))
  return (!Number.isSafeInteger(id) || id < 0) ? c.text('bad id', 400) : c.text(String(id))
})
app.get('/devices/:device_id', (c) => {
  const id = c.req.param('device_id')
  return devicePattern.test(id) ? c.text(id) : c.text('bad device id', 400)
})
app.get('/files/:name', (c) => {
  const name = c.req.param('name')
  return filePattern.test(name) ? c.text(name) : c.text('bad file name', 400)
})
app.post('/echo', async (c) => c.text(await c.req.text()))
app.get('/hybrid-inline', (c) => c.text('ok'))

const portArg = process.argv.find((a) => a.startsWith('--port='))
const port = portArg ? Number(portArg.slice('--port='.length)) : 8081
serve({ fetch: app.fetch, port, hostname: '127.0.0.1' }, (info) => {
  console.log(`Hono Node listening on http://${info.address}:${info.port}`)
})
