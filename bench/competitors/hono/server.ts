import { Hono } from 'hono'

const app = new Hono()
const devicePattern = /^[a-z0-9_-]{1,64}$/
const filePattern = /^[a-z0-9_.-]{1,80}$/

app.get('/__bench/meta', (c) => c.json({ framework: 'hono', runtime: 'bun', backend: 'bun-serve' }))
app.get('/__bench/plain', (c) => c.text('ok'))
app.get('/__bench/plain-static', (c) => c.text('ok'))
app.get('/__bench/hybrid-zig', (c) => c.text('ok'))
app.get('/__bench/hybrid-inline', (c) => c.text('ok'))
app.get('/__bench/hybrid-inline-text-literal', (c) => c.text('ok'))
app.get('/__bench/hybrid-inline-params/:id', (c) => c.text(c.req.param('id')))
app.post('/__bench/hybrid-inline-echo', async (c) => c.text(await c.req.text()))
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
Bun.serve({ port, fetch: app.fetch, hostname: '127.0.0.1' })
console.log(`Hono Bun listening on http://127.0.0.1:${port}`)
