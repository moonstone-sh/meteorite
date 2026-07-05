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
  conn:execute(string.format("INSERT INTO items (id, name, val) VALUES ('item-%03d', 'Item %d', %d)", i, i, i * 10))
end

app:get("/__app/json/encode-small", function(self)
  local data = {ok=true, name="meteorite", n=123}
  local encoded = cjson.encode(data)
  local decoded = cjson.decode(encoded)
  return { content_type = "text/plain", layout = false, "json:encode-small:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. tostring(decoded.ok) }
end)

app:post("/__app/json/decode-1kb", function(self)
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ""
  local decoded = cjson.decode(body)
  local payload_start = string.sub(decoded.payload or "", 1, 8)
  return { content_type = "text/plain", layout = false, "json:decode-1kb:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. payload_start }
end)

app:post("/__app/json/roundtrip-1kb", function(self)
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ""
  local decoded = cjson.decode(body)
  decoded.modified = true
  local reencoded = cjson.encode(decoded)
  return { content_type = "text/plain", layout = false, "json:roundtrip-1kb:" .. tostring(decoded.name) .. ":" .. tostring(decoded.n) .. ":" .. tostring(#reencoded) }
end)

app:get("/__app/template/hello", function(self)
  local template = etlua.compile("Hello <%= name %>!")
  local rendered = template({name="Meteorite"})
  return { content_type = "text/plain", layout = false, "template:hello:" .. rendered }
end)

app:get("/__app/template/list-100", function(self)
  local template = etlua.compile("<% for i, item in ipairs(items) do %><%= item.id %>:<%= item.name %><% end %>")
  local items = {}
  for i=1, 100 do
    table.insert(items, {id = string.format("id-%d", i), name = string.format("name-%d", i)})
  end
  local rendered = template({items=items})
  return { content_type = "text/plain", layout = false, "template:list-100:" .. tostring(#items) .. ":" .. items[1].id .. ":" .. items[1].name }
end)

app:get("/__app/sqlite/select-one", function(self)
  local cur = conn:execute("SELECT id, val FROM items WHERE id = 'item-042'")
  local row = cur:fetch({}, "a")
  cur:close()
  return { content_type = "text/plain", layout = false, "sqlite:select-one:" .. row.id .. ":" .. tostring(row.val) }
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
  return { content_type = "text/plain", layout = false, "sqlite:select-100:" .. tostring(count) }
end)

app:post("/__app/sqlite/insert-small", function(self)
  local res = conn:execute("INSERT INTO items (id, name, val) VALUES ('item-new-" .. tostring(ngx.now()) .. "-" .. math.random(1000) .. "', 'New Item', 100)")
  return { content_type = "text/plain", layout = false, "sqlite:insert-small:" .. tostring(res) }
end)

app:get("/__app/pipeline/cors", function(self)
  self.res.headers["Access-Control-Allow-Origin"] = "*"
  return { content_type = "text/plain", layout = false, "pipeline:cors:ok" }
end)

app:get("/__app/pipeline/cors-json-template", function(self)
  self.res.headers["Access-Control-Allow-Origin"] = "*"
  local decoded = cjson.decode('{"name":"cors","n":1}')
  local template = etlua.compile("Hello <%= name %>")
  local rendered = template({name=decoded.name})
  return { content_type = "text/plain", layout = false, "pipeline:cors-json-template:cors-json-template" }
end)

app:get("/__app/full/sqlite-json-template", function(self)
  local cur = conn:execute("SELECT id, val FROM items WHERE id = 'item-007'")
  local row = cur:fetch({}, "a")
  cur:close()
  local encoded = cjson.encode(row)
  local template = etlua.compile("Data: <%- data %>")
  local rendered = template({data=encoded})
  return { content_type = "text/plain", layout = false, "full:sqlite-json-template:" .. row.id .. ":" .. tostring(row.val) }
end)

return app
