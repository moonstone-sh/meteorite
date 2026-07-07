local turbo = require("turbo")
local cjson = require("cjson")
local etlua = require("etlua")
local luasql = require("luasql.sqlite3")

local env = luasql.sqlite3()
local conn = env:connect(":memory:")

conn:execute([[
    CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT, value INTEGER);
]])

conn:execute("INSERT INTO items (id, name, value) VALUES ('item-042', 'Name 042', 420)")
conn:execute("INSERT INTO items (id, name, value) VALUES ('item-007', 'Name 007', 70)")
for i = 1, 100 do
    conn:execute(string.format("INSERT OR IGNORE INTO items (id, name, value) VALUES ('item-%03d', 'Name %d', %d)", i, i, i * 10))
end

local list_template_str = [[
<% for i, item in ipairs(items) do %>
<%= item.id %>:<%= item.name %>
<% end %>
]]
local list_template = etlua.compile(list_template_str)

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

-- ─── Helper base handler with counter middleware ──────────────────

local BaseHandler = class("BaseHandler", turbo.web.RequestHandler)
function BaseHandler:on_create(kwargs)
    bench_counters.requests = bench_counters.requests + 1
    bench_stats.requests    = bench_stats.requests + 1
end

-- ─── Health / plain endpoints ─────────────────────────────────────

local HealthHandler = class("HealthHandler", BaseHandler)
function HealthHandler:get()
    self:set_header("Content-Type", "text/plain")
    self:write("ok")
end

local PlainHandler = class("PlainHandler", BaseHandler)
function PlainHandler:get()
    self:set_header("Content-Type", "text/plain")
    self:write("ok")
end

-- ─── Meta ────────────────────────────────────────────────────────

local MetaHandler = class("MetaHandler", BaseHandler)
function MetaHandler:get()
    self:set_header("Content-Type", "application/json")
    self:write(cjson.encode({
        framework = "turbo",
        runtime   = "luajit2.1",
        backend   = "turbo",
    }))
end

-- ─── Counters / Stats ────────────────────────────────────────────

local CountersHandler = class("CountersHandler", BaseHandler)
function CountersHandler:get()
    self:set_header("Content-Type", "application/json")
    self:write(cjson.encode(bench_counters))
end

local StatsHandler = class("StatsHandler", BaseHandler)
function StatsHandler:get()
    self:set_header("Content-Type", "application/json")
    self:write(cjson.encode(bench_stats))
end

local StatsResetHandler = class("StatsResetHandler", BaseHandler)
function StatsResetHandler:post()
    bench_stats = {requests = 0, errors = 0}
    self:set_header("Content-Type", "application/json")
    self:write(cjson.encode({reset = true}))
end

-- ─── Fixture info ─────────────────────────────────────────────────

local FixtureInfoHandler = class("FixtureInfoHandler", BaseHandler)
function FixtureInfoHandler:get()
    self:set_header("Content-Type", "application/json")
    self:write(cjson.encode({
        fixture = "bench-service",
        entry   = "fixtures/apps/bench-service/src/main.lua",
        variant = "turbo",
        routes  = {
            ["plain"]             = "ok",
            ["zig-static"]        = "ok",
            ["lua-return-string"] = "ok",
            ["lua-text-direct"]   = "ok",
            ["lua-direct-param"]  = "ok",
        },
    }))
end

-- ─── Work: CPU spin ───────────────────────────────────────────────
-- One handler class per bucket; routing table maps each path.

local WorkCpu50usHandler = class("WorkCpu50usHandler", BaseHandler)
function WorkCpu50usHandler:get() spin_us(50);   self:set_header("Content-Type","text/plain"); self:write("work:cpu:50us:50")   end

local WorkCpu100usHandler = class("WorkCpu100usHandler", BaseHandler)
function WorkCpu100usHandler:get() spin_us(100);  self:set_header("Content-Type","text/plain"); self:write("work:cpu:100us:100") end

local WorkCpu250usHandler = class("WorkCpu250usHandler", BaseHandler)
function WorkCpu250usHandler:get() spin_us(250);  self:set_header("Content-Type","text/plain"); self:write("work:cpu:250us:250") end

local WorkCpu500usHandler = class("WorkCpu500usHandler", BaseHandler)
function WorkCpu500usHandler:get() spin_us(500);  self:set_header("Content-Type","text/plain"); self:write("work:cpu:500us:500") end

local WorkCpu1msHandler = class("WorkCpu1msHandler", BaseHandler)
function WorkCpu1msHandler:get() spin_us(1000); self:set_header("Content-Type","text/plain"); self:write("work:cpu:1ms:1000")  end

local WorkCpu2msHandler = class("WorkCpu2msHandler", BaseHandler)
function WorkCpu2msHandler:get() spin_us(2000); self:set_header("Content-Type","text/plain"); self:write("work:cpu:2ms:2000")  end

local WorkCpu5msHandler = class("WorkCpu5msHandler", BaseHandler)
function WorkCpu5msHandler:get() spin_us(5000); self:set_header("Content-Type","text/plain"); self:write("work:cpu:5ms:5000")  end

-- ─── Work: sleep (using os.execute for portability) ───────────────

local WorkSleep1msHandler = class("WorkSleep1msHandler", BaseHandler)
function WorkSleep1msHandler:get()
    os.execute("sleep 0.001")
    self:set_header("Content-Type","text/plain"); self:write("sleep:1ms")
end

local WorkSleep5msHandler = class("WorkSleep5msHandler", BaseHandler)
function WorkSleep5msHandler:get()
    os.execute("sleep 0.005")
    self:set_header("Content-Type","text/plain"); self:write("sleep:5ms")
end

local WorkSleep10msHandler = class("WorkSleep10msHandler", BaseHandler)
function WorkSleep10msHandler:get()
    os.execute("sleep 0.01")
    self:set_header("Content-Type","text/plain"); self:write("sleep:10ms")
end

-- ─── Public routes ────────────────────────────────────────────────

local UsersHandler = class("UsersHandler", BaseHandler)
function UsersHandler:get(id)
    if id and id:match("^%d+$") then
        self:set_header("Content-Type", "application/json")
        self:write(id)
    else
        self:set_status(400)
        self:set_header("Content-Type", "text/plain")
        self:write("bad id")
    end
end

local EchoHandler = class("EchoHandler", BaseHandler)
function EchoHandler:post()
    local body = self.request.body
    if not body then
        self:set_status(400)
        return
    end
    self:set_header("Content-Type", "text/plain; charset=utf-8")
    self:write(body)
end

-- ─── App work-suite endpoints ─────────────────────────────────────

local EncodeSmallHandler = class("EncodeSmallHandler", BaseHandler)
function EncodeSmallHandler:get()
    local data = {ok=true, name="meteorite", n=123}
    local str = cjson.encode(data)
    local decoded = cjson.decode(str)
    local res = string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok))
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local Decode1KBHandler = class("Decode1KBHandler", BaseHandler)
function Decode1KBHandler:post()
    local body = self.request.body
    if not body then
        self:set_status(400)
        return
    end
    local decoded = cjson.decode(body)
    local res = string.format("json:decode-1kb:%s:%d:%s", decoded.name, decoded.n, string.sub(decoded.payload or "", 1, 8))
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local Roundtrip1KBHandler = class("Roundtrip1KBHandler", BaseHandler)
function Roundtrip1KBHandler:post()
    local body = self.request.body
    if not body then
        self:set_status(400)
        return
    end
    local decoded = cjson.decode(body)
    decoded.modified = true
    local encoded = cjson.encode(decoded)
    local res = string.format("json:roundtrip-1kb:%s:%d:%d", decoded.name, decoded.n, #encoded)
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local TemplateHelloHandler = class("TemplateHelloHandler", BaseHandler)
function TemplateHelloHandler:get()
    local template = etlua.compile("Hello <%= name %>!")
    local res = template({name="Meteorite"})
    self:set_header("Content-Type", "text/plain")
    self:write("template:hello:" .. res)
end

local TemplateList100Handler = class("TemplateList100Handler", BaseHandler)
function TemplateList100Handler:get()
    local items = {}
    for i = 1, 100 do
        table.insert(items, {id = string.format("item-%03d", i), name = "Name " .. i})
    end
    local rendered = list_template({items = items})
    local res = string.format("template:list-100:%d:%s:%s", #items, items[1].id, items[1].name)
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local SqliteSelectOneHandler = class("SqliteSelectOneHandler", BaseHandler)
function SqliteSelectOneHandler:get()
    local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-042'")
    local row = cur:fetch({}, "a")
    cur:close()
    local res = string.format("sqlite:select-one:%s:%d", row.id, row.value)
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local SqliteSelect100Handler = class("SqliteSelect100Handler", BaseHandler)
function SqliteSelect100Handler:get()
    local cur = conn:execute("SELECT id, value FROM items LIMIT 100")
    local count = 0
    while cur:fetch() do
        count = count + 1
    end
    cur:close()
    local res = string.format("sqlite:select-100:%d", count)
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local SqliteInsertSmallHandler = class("SqliteInsertSmallHandler", BaseHandler)
function SqliteInsertSmallHandler:post()
    local res = conn:execute("INSERT INTO items (id, name, value) VALUES ('new-item', 'New Item', 999)")
    local res_str = string.format("sqlite:insert-small:%d", res)
    self:set_header("Content-Type", "text/plain")
    self:write(res_str)
end

local PipelineCorsHandler = class("PipelineCorsHandler", BaseHandler)
function PipelineCorsHandler:get()
    self:set_header("Access-Control-Allow-Origin", "*")
    self:set_header("Content-Type", "text/plain")
    self:write("pipeline:cors:ok")
end

local PipelineCorsJsonTemplateHandler = class("PipelineCorsJsonTemplateHandler", BaseHandler)
function PipelineCorsJsonTemplateHandler:get()
    self:set_header("Access-Control-Allow-Origin", "*")
    local data = {ok=true, name="meteorite", n=123}
    local str = cjson.encode(data)
    local decoded = cjson.decode(str)
    local template = etlua.compile("Hello <%= name %>!")
    local rendered = template({name="Meteorite"})
    self:set_header("Content-Type", "text/plain")
    self:write("pipeline:cors-json-template:cors-json-template")
end

local FullSqliteJsonTemplateHandler = class("FullSqliteJsonTemplateHandler", BaseHandler)
function FullSqliteJsonTemplateHandler:get()
    local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-007'")
    local row = cur:fetch({}, "a")
    cur:close()

    local str = cjson.encode(row)
    local template = etlua.compile("<%= id %>:<%= value %>")
    local decoded = cjson.decode(str)
    local rendered = template(decoded)

    self:set_header("Content-Type", "text/plain")
    self:write("full:sqlite-json-template:" .. rendered)
end

-- ─── Application routing table ────────────────────────────────────

local app = turbo.web.Application:new({
    -- Health
    {"^/health$",                             HealthHandler},
    -- Synthetic bench
    {"^/__bench/plain$",                      PlainHandler},
    {"^/__bench/plain%-static$",              PlainHandler},
    {"^/__bench/zig%-static$",                PlainHandler},
    {"^/__bench/hybrid%-zig$",                PlainHandler},
    {"^/__bench/raw$",                        PlainHandler},
    {"^/__bench/meta$",                       MetaHandler},
    {"^/__bench/counters$",                   CountersHandler},
    {"^/__bench/stats$",                      StatsHandler},
    {"^/__bench/stats/reset$",                StatsResetHandler},
    {"^/__bench/fixture%-info$",              FixtureInfoHandler},
    -- Work: CPU
    {"^/__bench/work/cpu/50us$",              WorkCpu50usHandler},
    {"^/__bench/work/cpu/100us$",             WorkCpu100usHandler},
    {"^/__bench/work/cpu/250us$",             WorkCpu250usHandler},
    {"^/__bench/work/cpu/500us$",             WorkCpu500usHandler},
    {"^/__bench/work/cpu/1ms$",               WorkCpu1msHandler},
    {"^/__bench/work/cpu/2ms$",               WorkCpu2msHandler},
    {"^/__bench/work/cpu/5ms$",               WorkCpu5msHandler},
    -- Work: sleep
    {"^/__bench/work/sleep/1ms$",             WorkSleep1msHandler},
    {"^/__bench/work/sleep/5ms$",             WorkSleep5msHandler},
    {"^/__bench/work/sleep/10ms$",            WorkSleep10msHandler},
    -- Public routes
    {"^/users/(%d+)$",                        UsersHandler},
    {"^/echo$",                               EchoHandler},
    -- App work-suite
    {"^/__app/json/encode%-small$",           EncodeSmallHandler},
    {"^/__app/json/decode%-1kb$",             Decode1KBHandler},
    {"^/__app/json/roundtrip%-1kb$",          Roundtrip1KBHandler},
    {"^/__app/template/hello$",               TemplateHelloHandler},
    {"^/__app/template/list%-100$",           TemplateList100Handler},
    {"^/__app/sqlite/select%-one$",           SqliteSelectOneHandler},
    {"^/__app/sqlite/select%-100$",           SqliteSelect100Handler},
    {"^/__app/sqlite/insert%-small$",         SqliteInsertSmallHandler},
    {"^/__app/pipeline/cors$",                PipelineCorsHandler},
    {"^/__app/pipeline/cors%-json%-template$",PipelineCorsJsonTemplateHandler},
    {"^/__app/full/sqlite%-json%-template$",  FullSqliteJsonTemplateHandler},
})

local port = tonumber(os.getenv("PORT")) or 8080
app:listen(port)
turbo.ioloop.instance():start()
