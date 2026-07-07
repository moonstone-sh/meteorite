local pegasus = require('pegasus')
local cjson = require('cjson')
local etlua = require('etlua')
local luasql = require('luasql.sqlite3')

-- Initialize SQLite ONCE
local env = luasql.sqlite3()
local conn = env:connect(':memory:')
conn:execute("CREATE TABLE items (id TEXT, name TEXT, value INTEGER)")
for i = 1, 100 do
  conn:execute(string.format("INSERT INTO items VALUES ('item-%03d', 'Name %d', %d)", i, i, i * 10))
end
-- Ensure specific lookup rows exist (not duplicated by the loop above)
conn:execute("INSERT OR IGNORE INTO items VALUES ('item-042', 'Name 42', 420)")
conn:execute("INSERT OR IGNORE INTO items VALUES ('item-007', 'Name 7', 70)")

-- CPU busy-spin using os.clock()
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
  ["1ms"]  = "1ms",
  ["5ms"]  = "5ms",
  ["10ms"] = "10ms",
}

local sleep_seconds = {
  ["1ms"]  = 0.001,
  ["5ms"]  = 0.005,
  ["10ms"] = 0.010,
}

local bench_counters = {requests = 0}
local bench_stats    = {requests = 0, errors = 0}

local server = pegasus:new({
  port    = os.getenv("PORT") or 8080,
  timeout = 10
})

server:start(function(req, rep)
  local path   = req:path()
  local method = req:method()

  bench_counters.requests = bench_counters.requests + 1
  bench_stats.requests    = bench_stats.requests + 1

  -- ─── Synthetic bench endpoints ──────────────────────────────────

  if path == "/health" then
    rep:addHeader('Content-Type', 'text/plain')
    rep:write("ok")

  elseif path == "/__bench/plain" or path == "/__bench/plain-static"
      or path == "/__bench/zig-static" or path == "/__bench/hybrid-zig"
      or path == "/__bench/raw" then
    rep:addHeader('Content-Type', 'text/plain')
    rep:write("ok")

  elseif path == "/__bench/meta" then
    rep:addHeader('Content-Type', 'application/json')
    rep:write(cjson.encode({
      framework = "pegasus",
      runtime   = "luajit2.1",
      backend   = "pegasus",
    }))

  elseif path == "/__bench/counters" then
    rep:addHeader('Content-Type', 'application/json')
    rep:write(cjson.encode(bench_counters))

  elseif path == "/__bench/stats" then
    rep:addHeader('Content-Type', 'application/json')
    rep:write(cjson.encode(bench_stats))

  elseif path == "/__bench/stats/reset" and method == "POST" then
    bench_stats = {requests = 0, errors = 0}
    rep:addHeader('Content-Type', 'application/json')
    rep:write(cjson.encode({reset = true}))

  elseif path == "/__bench/fixture-info" then
    rep:addHeader('Content-Type', 'application/json')
    rep:write(cjson.encode({
      fixture = "bench-service",
      entry   = "fixtures/apps/bench-service/src/main.lua",
      variant = "pegasus",
      routes  = {
        ["plain"]           = "ok",
        ["zig-static"]      = "ok",
        ["lua-return-string"] = "ok",
        ["lua-text-direct"] = "ok",
        ["lua-direct-param"] = "ok",
      },
    }))

  -- ─── Work: CPU spin ─────────────────────────────────────────────

  elseif path:sub(1, 18) == "/__bench/work/cpu/" then
    local key = path:sub(19)
    local w = cpu_work[key]
    if w then
      spin_us(w.us)
      rep:addHeader('Content-Type', 'text/plain')
      rep:write("work:cpu:" .. w.label .. ":" .. w.checksum)
    else
      rep:statusCode(404, "Not Found")
      rep:write("404 Not Found")
    end

  -- ─── Work: sleep ────────────────────────────────────────────────

  elseif path:sub(1, 20) == "/__bench/work/sleep/" then
    local key = path:sub(21)
    local lbl = sleep_work[key]
    if lbl then
      os.execute(string.format("sleep %s", sleep_seconds[key]))
      rep:addHeader('Content-Type', 'text/plain')
      rep:write("sleep:" .. lbl)
    else
      rep:statusCode(404, "Not Found")
      rep:write("404 Not Found")
    end

  -- ─── Public routes ───────────────────────────────────────────────

  elseif path:sub(1, 7) == "/users/" and method == "GET" then
    local id = path:sub(8)
    -- basic u64 validation
    if id:match("^%d+$") then
      rep:addHeader('Content-Type', 'application/json')
      rep:write(id)
    else
      rep:statusCode(400, "Bad Request")
      rep:write("bad id")
    end

  elseif path == "/echo" and method == "POST" then
    local headers = req:headers()
    local cl = tonumber(headers['content-length'] or headers['Content-Length']) or 0
    local body = req:receiveBody(cl > 0 and cl or nil) or ""
    rep:addHeader('Content-Type', 'text/plain; charset=utf-8')
    rep:write(body)

  -- ─── App work-suite endpoints ────────────────────────────────────

  elseif path == "/__app/json/encode-small" then
    local obj = {ok = true, name = "meteorite", n = 123}
    local encoded = cjson.encode(obj)
    local decoded = cjson.decode(encoded)
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok)))

  elseif path == "/__app/json/decode-1kb" and method == "POST" then
    local headers = req:headers()
    local cl = tonumber(headers['content-length'] or headers['Content-Length']) or 0
    local body = req:receiveBody(cl > 0 and cl or nil) or ""
    local decoded = cjson.decode(body)
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("json:decode-1kb:%s:%d:%s", decoded.name, decoded.n, string.sub(decoded.payload or "", 1, 8)))

  elseif path == "/__app/json/roundtrip-1kb" and method == "POST" then
    local headers = req:headers()
    local cl = tonumber(headers['content-length'] or headers['Content-Length']) or 0
    local body = req:receiveBody(cl > 0 and cl or nil) or ""
    local decoded = cjson.decode(body)
    decoded.modified = true
    local reencoded = cjson.encode(decoded)
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("json:roundtrip-1kb:%s:%d:%d", decoded.name, decoded.n, #reencoded))

  elseif path == "/__app/template/hello" then
    local template = etlua.compile("Hello <%= name %>!")
    local rendered = template({name = "Meteorite"})
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("template:hello:%s", rendered))

  elseif path == "/__app/template/list-100" then
    local items = {}
    for i = 1, 100 do
      table.insert(items, {id = string.format("item-%03d", i), name = string.format("Name %d", i)})
    end
    local template = etlua.compile("<% for i, item in ipairs(items) do %><% if i == 1 then %>template:list-100:<%= #items %>:<%= item.id %>:<%= item.name %><% end %><% end %>")
    local rendered = template({items = items})
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(rendered)

  elseif path == "/__app/sqlite/select-one" then
    local cursor = conn:execute("SELECT id, value FROM items WHERE id = 'item-042'")
    local row = cursor:fetch({}, "a")
    cursor:close()
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("sqlite:select-one:%s:%d", row.id, row.value))

  elseif path == "/__app/sqlite/select-100" then
    local cursor = conn:execute("SELECT id, value FROM items LIMIT 100")
    local count = 0
    local row = cursor:fetch({}, "a")
    while row do
      count = count + 1
      row = cursor:fetch({}, "a")
    end
    cursor:close()
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("sqlite:select-100:%d", count))

  elseif path == "/__app/sqlite/insert-small" and method == "POST" then
    conn:execute("INSERT INTO items VALUES ('item-999', 'Name 999', 999)")
    rep:addHeader('Content-Type', 'text/plain')
    rep:write("sqlite:insert-small:1")

  elseif path == "/__app/pipeline/cors" then
    rep:addHeader('Access-Control-Allow-Origin', '*')
    rep:addHeader('Content-Type', 'text/plain')
    rep:write("pipeline:cors:ok")

  elseif path == "/__app/pipeline/cors-json-template" then
    rep:addHeader('Access-Control-Allow-Origin', '*')
    rep:addHeader('Content-Type', 'text/plain')
    local obj = {name = "cors"}
    local encoded = cjson.encode(obj)
    local decoded = cjson.decode(encoded)
    local template = etlua.compile("<%= name %>-json-template")
    local rendered = template(decoded)
    rep:write(string.format("pipeline:cors-json-template:%s", rendered))

  elseif path == "/__app/full/sqlite-json-template" then
    local cursor = conn:execute("SELECT id, value FROM items WHERE id = 'item-007'")
    local row = cursor:fetch({}, "a")
    cursor:close()
    local encoded = cjson.encode(row)
    local decoded = cjson.decode(encoded)
    local template = etlua.compile("<%= id %>:<%= value %>")
    local rendered = template(decoded)
    rep:addHeader('Content-Type', 'text/plain')
    rep:write(string.format("full:sqlite-json-template:%s", rendered))

  else
    rep:statusCode(404, "Not Found")
    rep:write("404 Not Found")
  end
end)
