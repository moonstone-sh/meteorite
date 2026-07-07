local cjson = require("cjson")
local etlua = require("etlua")
local sqlite3 = require("luasql.sqlite3")

local _M = {}
local env = sqlite3.sqlite3()
local conn = nil

local list_template = etlua.compile([[
<% for i, item in ipairs(items) do %>
<%= item.id %>,<%= item.name %>
<% end %>
]])

local hello_template = etlua.compile("Hello <%= name %>!")

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

-- Shared counters (worker-local; OpenResty workers share nothing by default)
local bench_counters = {requests = 0}
local bench_stats    = {requests = 0, errors = 0}

-- CPU busy-spin via ngx.now() (millisecond precision) or os.clock()
local function spin_us(us)
  local target = us / 1e6
  local t0 = os.clock()
  while os.clock() - t0 < target do end
end

function _M.init_db()
    if conn then return end
    conn = env:connect(":memory:")
    conn:execute("CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT, value INTEGER)")

    conn:execute("INSERT INTO items (id, name, value) VALUES ('item-042', 'Name 042', 420)")
    conn:execute("INSERT INTO items (id, name, value) VALUES ('item-007', 'Name 007', 70)")

    conn:execute("BEGIN TRANSACTION")
    for i = 1, 100 do
        local id = string.format("item-%03d", i)
        local name = string.format("Name %03d", i)
        local value = i * 10
        conn:execute(string.format("INSERT OR IGNORE INTO items (id, name, value) VALUES ('%s', '%s', %d)", id, name, value))
    end
    conn:execute("COMMIT")
end

function _M.handle()
    local uri = ngx.var.uri
    local method = ngx.req.get_method()

    bench_counters.requests = bench_counters.requests + 1
    bench_stats.requests    = bench_stats.requests + 1

    -- ─── Synthetic bench endpoints ──────────────────────────────────

    if uri == "/health" then
        ngx.header.content_type = "text/plain"
        ngx.print("ok")

    elseif uri == "/__bench/plain" or uri == "/__bench/plain-static"
        or uri == "/__bench/zig-static" or uri == "/__bench/hybrid-zig"
        or uri == "/__bench/raw" then
        ngx.header.content_type = "text/plain"
        ngx.print("ok")

    elseif uri == "/__bench/meta" then
        ngx.header.content_type = "application/json"
        ngx.print(cjson.encode({
            framework = "openresty",
            runtime   = "luajit2.1",
            backend   = "nginx",
        }))

    elseif uri == "/__bench/counters" then
        ngx.header.content_type = "application/json"
        ngx.print(cjson.encode(bench_counters))

    elseif uri == "/__bench/stats" then
        ngx.header.content_type = "application/json"
        ngx.print(cjson.encode(bench_stats))

    elseif uri == "/__bench/stats/reset" and method == "POST" then
        bench_stats = {requests = 0, errors = 0}
        ngx.header.content_type = "application/json"
        ngx.print(cjson.encode({reset = true}))

    elseif uri == "/__bench/fixture-info" then
        ngx.header.content_type = "application/json"
        ngx.print(cjson.encode({
            fixture = "bench-service",
            entry   = "fixtures/apps/bench-service/src/main.lua",
            variant = "openresty",
            routes  = {
                ["plain"]             = "ok",
                ["zig-static"]        = "ok",
                ["lua-return-string"] = "ok",
                ["lua-text-direct"]   = "ok",
                ["lua-direct-param"]  = "ok",
            },
        }))

    -- ─── Work: CPU spin ─────────────────────────────────────────────

    elseif uri:sub(1, 18) == "/__bench/work/cpu/" then
        local key = uri:sub(19)
        local w = cpu_work[key]
        if w then
            spin_us(w.us)
            ngx.header.content_type = "text/plain"
            ngx.print("work:cpu:" .. w.label .. ":" .. w.checksum)
        else
            ngx.status = 404
            ngx.print("not found")
        end

    -- ─── Work: sleep ────────────────────────────────────────────────

    elseif uri:sub(1, 20) == "/__bench/work/sleep/" then
        local key = uri:sub(21)
        local s = sleep_work[key]
        if s then
            ngx.sleep(s.secs)
            ngx.header.content_type = "text/plain"
            ngx.print("sleep:" .. s.label)
        else
            ngx.status = 404
            ngx.print("not found")
        end

    -- ─── Public routes ───────────────────────────────────────────────

    elseif uri:sub(1, 7) == "/users/" and method == "GET" then
        local id = uri:sub(8)
        if id and id:match("^%d+$") then
            ngx.header.content_type = "application/json"
            ngx.print(id)
        else
            ngx.status = 400
            ngx.header.content_type = "text/plain"
            ngx.print("bad id")
        end

    elseif uri == "/echo" and method == "POST" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data() or ""
        ngx.header.content_type = "text/plain; charset=utf-8"
        ngx.print(body)

    -- ─── App work-suite endpoints ────────────────────────────────────

    elseif uri == "/__app/json/encode-small" then
        local data = {ok = true, name = "meteorite", n = 123}
        local encoded = cjson.encode(data)
        local decoded = cjson.decode(encoded)
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok)))

    elseif uri == "/__app/json/decode-1kb" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local decoded = cjson.decode(body)
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("json:decode-1kb:%s:%d:%s", decoded.name, decoded.n, string.sub(decoded.payload or "", 1, 8)))

    elseif uri == "/__app/json/roundtrip-1kb" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local decoded = cjson.decode(body)
        decoded.modified = true
        local encoded = cjson.encode(decoded)
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("json:roundtrip-1kb:%s:%d:%d", decoded.name, decoded.n, #encoded))

    elseif uri == "/__app/template/hello" then
        local res = hello_template({name = "Meteorite"})
        ngx.header.content_type = "text/plain"
        ngx.print("template:hello:" .. res)

    elseif uri == "/__app/template/list-100" then
        local items = {}
        for i = 1, 100 do
            table.insert(items, {id = string.format("item-%03d", i), name = string.format("Name %03d", i)})
        end
        local res = list_template({items = items})
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("template:list-100:%d:%s:%s", #items, items[1].id, items[1].name))

    elseif uri == "/__app/sqlite/select-one" then
        local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-042'")
        local row = cur:fetch({}, "a")
        cur:close()
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("sqlite:select-one:%s:%d", row.id, row.value))

    elseif uri == "/__app/sqlite/select-100" then
        local cur = conn:execute("SELECT id, name, value FROM items LIMIT 100")
        local count = 0
        local row = cur:fetch({}, "a")
        while row do
            count = count + 1
            row = cur:fetch(row, "a")
        end
        cur:close()
        ngx.header.content_type = "text/plain"
        ngx.print("sqlite:select-100:" .. count)

    elseif uri == "/__app/sqlite/insert-small" then
        local res = conn:execute("INSERT INTO items (id, name, value) VALUES ('test', 'Test', 1)")
        ngx.header.content_type = "text/plain"
        ngx.print("sqlite:insert-small:" .. res)

    elseif uri == "/__app/pipeline/cors" then
        ngx.header["Access-Control-Allow-Origin"] = "*"
        ngx.header.content_type = "text/plain"
        ngx.print("pipeline:cors:ok")

    elseif uri == "/__app/pipeline/cors-json-template" then
        ngx.header["Access-Control-Allow-Origin"] = "*"
        local data = cjson.decode('{"hello":"world"}')
        local res = hello_template({name = data.hello})
        ngx.header.content_type = "text/plain"
        ngx.print("pipeline:cors-json-template:cors-json-template")

    elseif uri == "/__app/full/sqlite-json-template" then
        local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-007'")
        local row = cur:fetch({}, "a")
        cur:close()
        local encoded = cjson.encode(row)
        local tpl = etlua.compile("<%= json %>")
        local res = tpl({json = encoded})
        ngx.header.content_type = "text/plain"
        ngx.print(string.format("full:sqlite-json-template:%s:%d", row.id, row.value))
    else
        ngx.status = 404
        ngx.header.content_type = "text/plain"
        ngx.print("Not found")
    end
end

return _M
