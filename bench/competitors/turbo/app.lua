local turbo = require("turbo")
local cjson = require("cjson")
local etlua = require("etlua")
local luasql = require("luasql.sqlite3")

local env = luasql.sqlite3()
local conn = env:connect(":memory:")

conn:execute([[
    CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT, value INTEGER);
]])

for i = 1, 100 do
    conn:execute(string.format("INSERT INTO items (id, name, value) VALUES ('item-%03d', 'Name %d', %d)", i, i, i * 10))
end

local list_template_str = [[
<% for i, item in ipairs(items) do %>
<%= item.id %>:<%= item.name %>
<% end %>
]]
local list_template = etlua.compile(list_template_str)

local EncodeSmallHandler = class("EncodeSmallHandler", turbo.web.RequestHandler)
function EncodeSmallHandler:get()
    local data = {ok=true, name="meteorite", n=123}
    local str = cjson.encode(data)
    local decoded = cjson.decode(str)
    local res = string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok))
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local Decode1KBHandler = class("Decode1KBHandler", turbo.web.RequestHandler)
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

local Roundtrip1KBHandler = class("Roundtrip1KBHandler", turbo.web.RequestHandler)
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

local TemplateHelloHandler = class("TemplateHelloHandler", turbo.web.RequestHandler)
function TemplateHelloHandler:get()
    local template = etlua.compile("Hello <%= name %>!")
    local res = template({name="Meteorite"})
    self:set_header("Content-Type", "text/plain")
    self:write("template:hello:" .. res)
end

local TemplateList100Handler = class("TemplateList100Handler", turbo.web.RequestHandler)
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

local SqliteSelectOneHandler = class("SqliteSelectOneHandler", turbo.web.RequestHandler)
function SqliteSelectOneHandler:get()
    local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-042'")
    local row = cur:fetch({}, "a")
    cur:close()
    local res = string.format("sqlite:select-one:%s:%d", row.id, row.value)
    self:set_header("Content-Type", "text/plain")
    self:write(res)
end

local SqliteSelect100Handler = class("SqliteSelect100Handler", turbo.web.RequestHandler)
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

local SqliteInsertSmallHandler = class("SqliteInsertSmallHandler", turbo.web.RequestHandler)
function SqliteInsertSmallHandler:post()
    local res = conn:execute("INSERT INTO items (id, name, value) VALUES ('new-item', 'New Item', 999)")
    local res_str = string.format("sqlite:insert-small:%d", res)
    self:set_header("Content-Type", "text/plain")
    self:write(res_str)
end

local PipelineCorsHandler = class("PipelineCorsHandler", turbo.web.RequestHandler)
function PipelineCorsHandler:get()
    self:set_header("Access-Control-Allow-Origin", "*")
    self:set_header("Content-Type", "text/plain")
    self:write("pipeline:cors:ok")
end

local PipelineCorsJsonTemplateHandler = class("PipelineCorsJsonTemplateHandler", turbo.web.RequestHandler)
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

local FullSqliteJsonTemplateHandler = class("FullSqliteJsonTemplateHandler", turbo.web.RequestHandler)
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

local app = turbo.web.Application:new({
    {"^/__app/json/encode%-small$", EncodeSmallHandler},
    {"^/__app/json/decode%-1kb$", Decode1KBHandler},
    {"^/__app/json/roundtrip%-1kb$", Roundtrip1KBHandler},
    {"^/__app/template/hello$", TemplateHelloHandler},
    {"^/__app/template/list%-100$", TemplateList100Handler},
    {"^/__app/sqlite/select%-one$", SqliteSelectOneHandler},
    {"^/__app/sqlite/select%-100$", SqliteSelect100Handler},
    {"^/__app/sqlite/insert%-small$", SqliteInsertSmallHandler},
    {"^/__app/pipeline/cors$", PipelineCorsHandler},
    {"^/__app/pipeline/cors%-json%-template$", PipelineCorsJsonTemplateHandler},
    {"^/__app/full/sqlite%-json%-template$", FullSqliteJsonTemplateHandler}
})

local port = tonumber(os.getenv("PORT")) or 8080
app:listen(port)
turbo.ioloop.instance():start()
