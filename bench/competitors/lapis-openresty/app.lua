local lapis = require("lapis")
local cjson = require("cjson")
local etlua = require("etlua")
local luasql = require("luasql.sqlite3")

local app = lapis.Application()

-- Global DB Initialization
local env = luasql.sqlite3()
local conn = env:connect(":memory:")
conn:execute[[
  CREATE TABLE items (
    id TEXT PRIMARY KEY,
    name TEXT,
    val INTEGER
  )
]]
conn:execute[[
  INSERT INTO items (id, name, val) VALUES ('item-042', 'Item 42', 420)
]]
conn:execute[[
  INSERT INTO items (id, name, val) VALUES ('item-007', 'Item 7', 70)
]]
for i = 1, 100 do
  conn:execute(string.format("INSERT OR IGNORE INTO items (id, name, val) VALUES ('item-%03d', 'Item %d', %d)", i, i, i * 10))
end

-- CPU busy-spin via os.clock()
local function spin_us(us)
  local target = us / 1e6
  local t0 = os.clock()
  while os.clock() - t0 < target do end
end

local cpu_work = {
  ["50us"]  = {us = 50,   label = "50us",  checksum = "50"},
  ["100us"] = {us = 100,  label = "100us", checksum = "100"},
  ["250us"] = {us = 250,  label = "250us", checksum = "250"},
  ["500us"] = {us = 500,  label = "500us", checksum = "500"},
  ["1ms"]   = {us = 1000, label = "1ms",   checksum = "1000"},
  ["2ms"]   = {us = 2000, label = "2ms",   checksum = "2000"},
  ["5ms"]   = {us = 5000, label = "5ms",   checksum = "5000"},
}

local sleep_work = {
  ["1ms"]  = {label = "1ms",  secs = 0.001},
  ["5ms"]  = {label = "5ms",  secs = 0.005},
  ["10ms"] = {label = "10ms", secs = 0.010},
}

local bench_counters = {requests = 0}
local bench_stats    = {requests = 0, errors = 0}

local function plain(body)
  return { content_type = "text/plain", layout = false, body }
end

local function json_resp(t)
  return { content_type = "application/json", layout = false, cjson.encode(t) }
end

-- ─── Request counter middleware ──────────────────────────────────

app:before_filter(function(self)
  bench_counters.requests = bench_counters.requests + 1
  bench_stats.requests    = bench_stats.requests + 1
end)

-- ─── Synthetic bench endpoints ───────────────────────────────────

app:get("/health", function(self)
  return plain("ok")
end)

app:get("/__bench/plain",        function(self) return plain("ok") end)
app:get("/__bench/plain-static", function(self) return plain("ok") end)
app:get("/__bench/zig-static",   function(self) return plain("ok") end)
app:get("/__bench/hybrid-zig",   function(self) return plain("ok") end)
app:get("/__bench/raw",          function(self) return plain("ok") end)

app:get("/__bench/meta", function(self)
  return json_resp({
    framework = "lapis-openresty",
    runtime   = "luajit2.1",
    backend   = "openresty-nginx",
  })
end)

app:get("/__bench/counters", function(self)
  return json_resp(bench_counters)
end)

app:get("/__bench/stats", function(self)
  return json_resp(bench_stats)
end)

app:post("/__bench/stats/reset", function(self)
  bench_stats = {requests = 0, errors = 0}
  return json_resp({reset = true})
end)

app:get("/__bench/fixture-info", function(self)
  return json_resp({
    fixture = "bench-service",
    entry   = "fixtures/apps/bench-service/src/main.lua",
    variant = "lapis-openresty",
    routes  = {
      ["plain"]             = "ok",
      ["zig-static"]        = "ok",
      ["lua-return-string"] = "ok",
      ["lua-text-direct"]   = "ok",
      ["lua-direct-param"]  = "ok",
    },
  })
end)

-- ─── Work: CPU spin ──────────────────────────────────────────────

for key, w in pairs(cpu_work) do
  local _w = w
  app:get("/__bench/work/cpu/" .. key, function(self)
    spin_us(_w.us)
    return plain("work:cpu:" .. _w.label .. ":" .. _w.checksum)
  end)
end

-- ─── Work: sleep ─────────────────────────────────────────────────

for key, s in pairs(sleep_work) do
  local _s = s
  app:get("/__bench/work/sleep/" .. key, function(self)
    ngx.sleep(_s.secs)
    return plain("sleep:" .. _s.label)
  end)
end

-- ─── Public routes ───────────────────────────────────────────────

app:get("/users/:id", function(self)
  local id = self.params.id
  if id and id:match("^%d+$") then
    return { content_type = "application/json", layout = false, id }
  else
    self.status = 400
    return plain("bad id")
  end
end)

app:post("/echo", function(self)
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ""
  return { content_type = "text/plain; charset=utf-8", layout = false, body }
end)

-- ─── App work-suite endpoints ─────────────────────────────────────

app:get("/__app/json/encode-small", function(self)
  local data = {ok=true, name="meteorite", n=123}
  local encoded = cjson.encode(data)
  local decoded = cjson.decode(encoded)
  return plain("json:encode-small:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. tostring(decoded.ok))
end)

app:post("/__app/json/decode-1kb", function(self)
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ""
  local decoded = cjson.decode(body)
  local payload_start = string.sub(decoded.payload or "", 1, 8)
  return plain("json:decode-1kb:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. payload_start)
end)

app:post("/__app/json/roundtrip-1kb", function(self)
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ""
  local decoded = cjson.decode(body)
  decoded.modified = true
  local reencoded = cjson.encode(decoded)
  return plain("json:roundtrip-1kb:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. tostring(#reencoded))
end)

app:get("/__app/template/hello", function(self)
  local template = etlua.compile("Hello <%= name %>!")
  local rendered = template({name="Meteorite"})
  return plain("template:hello:" .. rendered)
end)

app:get("/__app/template/list-100", function(self)
  local template = etlua.compile("<% for i, item in ipairs(items) do %><%= item.id %>:<%= item.name %><% end %>")
  local items = {}
  for i=1, 100 do
    table.insert(items, {id = string.format("id-%d", i), name = string.format("name-%d", i)})
  end
  local rendered = template({items=items})
  return plain("template:list-100:" .. tostring(#items) .. ":" .. items[1].id .. ":" .. items[1].name)
end)

app:get("/__app/sqlite/select-one", function(self)
  local cur = conn:execute("SELECT id, val FROM items WHERE id = 'item-042'")
  local row = cur:fetch({}, "a")
  cur:close()
  return plain("sqlite:select-one:" .. row.id .. ":" .. tostring(row.val))
end)

app:get("/__app/sqlite/select-100", function(self)
  local cur = conn:execute("SELECT id, val FROM items LIMIT 100")
  local count = 0
  local row = cur:fetch({}, "a")
  while row do
    count = count + 1
    row = cur:fetch({}, "a")
  end
  cur:close()
  return plain("sqlite:select-100:" .. tostring(count))
end)

app:post("/__app/sqlite/insert-small", function(self)
  local res = conn:execute("INSERT INTO items (id, name, val) VALUES ('item-new-" .. tostring(ngx.now()) .. "-" .. math.random(1000) .. "', 'New Item', 100)")
  return plain("sqlite:insert-small:" .. tostring(res))
end)

app:get("/__app/pipeline/cors", function(self)
  self.res.headers["Access-Control-Allow-Origin"] = "*"
  return plain("pipeline:cors:ok")
end)

app:get("/__app/pipeline/cors-json-template", function(self)
  self.res.headers["Access-Control-Allow-Origin"] = "*"
  local decoded = cjson.decode('{"name":"cors","n":1}')
  local template = etlua.compile("Hello <%= name %>")
  local rendered = template({name=decoded.name})
  return plain("pipeline:cors-json-template:cors-json-template")
end)

app:get("/__app/full/sqlite-json-template", function(self)
  local cur = conn:execute("SELECT id, val FROM items WHERE id = 'item-007'")
  local row = cur:fetch({}, "a")
  cur:close()
  local encoded = cjson.encode(row)
  local template = etlua.compile("Data: <%- data %>")
  local rendered = template({data=encoded})
  return plain("full:sqlite-json-template:" .. row.id .. ":" .. tostring(row.val))
end)

return app
