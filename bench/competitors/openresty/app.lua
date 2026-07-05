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

function _M.init_db()
    if conn then return end
    conn = env:connect(":memory:")
    conn:execute("CREATE TABLE items (id TEXT, name TEXT, value INTEGER)")
    
    conn:execute("BEGIN TRANSACTION")
    for i = 1, 100 do
        local id = string.format("item-%03d", i)
        local name = string.format("Name %03d", i)
        local value = i * 10
        conn:execute(string.format("INSERT INTO items (id, name, value) VALUES ('%s', '%s', %d)", id, name, value))
    end
    conn:execute("COMMIT")
end

function _M.handle()
    local uri = ngx.var.uri
    local method = ngx.req.get_method()

    ngx.header.content_type = "text/plain"

    if uri == "/__app/json/encode-small" then
        local data = {ok = true, name = "meteorite", n = 123}
        local encoded = cjson.encode(data)
        local decoded = cjson.decode(encoded)
        ngx.print(string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok)))

    elseif uri == "/__app/json/decode-1kb" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local decoded = cjson.decode(body)
        ngx.print(string.format("json:decode-1kb:%s:%d:%s", decoded.name, decoded.n, string.sub(decoded.payload or "", 1, 8)))

    elseif uri == "/__app/json/roundtrip-1kb" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local decoded = cjson.decode(body)
        decoded.modified = true
        local encoded = cjson.encode(decoded)
        ngx.print(string.format("json:roundtrip-1kb:%s:%d:%d", decoded.name, decoded.n, #encoded))

    elseif uri == "/__app/template/hello" then
        local res = hello_template({name = "Meteorite"})
        ngx.print("template:hello:" .. res)

    elseif uri == "/__app/template/list-100" then
        local items = {}
        for i = 1, 100 do
            table.insert(items, {id = string.format("item-%03d", i), name = string.format("Name %03d", i)})
        end
        local res = list_template({items = items})
        ngx.print(string.format("template:list-100:%d:%s:%s", #items, items[1].id, items[1].name))

    elseif uri == "/__app/sqlite/select-one" then
        local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-042'")
        local row = cur:fetch({}, "a")
        cur:close()
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
        ngx.print("sqlite:select-100:" .. count)

    elseif uri == "/__app/sqlite/insert-small" then
        local res = conn:execute("INSERT INTO items (id, name, value) VALUES ('test', 'Test', 1)")
        ngx.print("sqlite:insert-small:" .. res)

    elseif uri == "/__app/pipeline/cors" then
        ngx.header["Access-Control-Allow-Origin"] = "*"
        ngx.print("pipeline:cors:ok")

    elseif uri == "/__app/pipeline/cors-json-template" then
        ngx.header["Access-Control-Allow-Origin"] = "*"
        local data = cjson.decode('{"hello":"world"}')
        local res = hello_template({name = data.hello})
        ngx.print("pipeline:cors-json-template:cors-json-template")

    elseif uri == "/__app/full/sqlite-json-template" then
        local cur = conn:execute("SELECT id, value FROM items WHERE id = 'item-007'")
        local row = cur:fetch({}, "a")
        cur:close()
        local encoded = cjson.encode(row)
        local tpl = etlua.compile("<%= json %>")
        local res = tpl({json = encoded})
        ngx.print(string.format("full:sqlite-json-template:%s:%d", row.id, row.value))
    else
        ngx.status = 404
        ngx.print("Not found")
    end
end

return _M
