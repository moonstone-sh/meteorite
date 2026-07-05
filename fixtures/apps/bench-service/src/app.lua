local m = require("meteorite")

local app = m.app({ name = "bench-service", host = "127.0.0.1", port = 8080 })

app:capability("http", {
	db = {
		base_url = "http://localhost:8888",
		timeout_ms = 1500,
		max_response_bytes = 65536,
	},
})

app:capability("zig", {
	data_cruncher = "zig/helpers/data_cruncher.zig",
})

-- Benchmark routes (always static Zig handlers)
app:get("/__bench/plain", "handlers.plain")
app:get("/__bench/zig-static", "handlers.zig_static")
app:get("/__bench/plain-static", "handlers.plain_static")
app:get("/__bench/hybrid-zig", "handlers.hybrid_zig")
app:get("/__bench/meta", "handlers.bench_meta")
app:get("/__bench/raw", "handlers.bench_raw")
app:get("/__bench/counters", "handlers.bench_counters")
app:get("/__bench/stats", "handlers.bench_stats_handler")
app:post("/__bench/stats/reset", "handlers.bench_stats_reset")
app:get("/__bench/fixture-info", "handlers.bench_fixture_info")

app:get("/__bench/work/cpu/50us", "handlers.work_cpu_50us")
app:get("/__bench/work/cpu/100us", "handlers.work_cpu_100us")
app:get("/__bench/work/cpu/250us", "handlers.work_cpu_250us")
app:get("/__bench/work/cpu/500us", "handlers.work_cpu_500us")
app:get("/__bench/work/cpu/1ms", "handlers.work_cpu_1ms")
app:get("/__bench/work/cpu/2ms", "handlers.work_cpu_2ms")
app:get("/__bench/work/cpu/5ms", "handlers.work_cpu_5ms")
app:get("/__bench/work/sleep/1ms", "handlers.work_sleep_1ms")
app:get("/__bench/work/sleep/5ms", "handlers.work_sleep_5ms")
app:get("/__bench/work/sleep/10ms", "handlers.work_sleep_10ms")

app:get("/health", "handlers.health")
app:get("/users/:id", {
	params = { id = m.u64() },
}, "handlers.get_user")

app:put("/users/:id", {
	params = { id = m.u64() },
}, "handlers.put_user")

app:patch("/users/:id", {
	params = { id = m.u64() },
}, "handlers.patch_user")

app:delete("/users/:id", {
	params = { id = m.u64() },
}, "handlers.delete_user")

app:post("/echo", {
	body = {
		max = "8kb",
	},
	memory = { request_arena = "16kb" },
}, "handlers.echo")

local device_id = m.pattern("^[a-z0-9_-]{1,64}$", {
	max_dfa_states = 128,
	max_dfa_bytes = "8kb",
})

app:get("/devices/:device_id", {
	params = {
		device_id = m.string({ max = 64, pattern = device_id }),
	},
}, "handlers.get_device")

app:get("/files/:name", {
	params = {
		name = m.string({ max = 80, pattern = m.pattern("^[a-z0-9_.-]{1,80}$") }),
	},
}, "handlers.file")

app:get("/slugs/:slug", {
	params = { slug = m.slug({ max = 64 }) },
}, "handlers.slug")

app:get("/uuids/:id", {
	params = { id = m.uuid() },
}, "handlers.uuid")

app:get("/hex/:digest", {
	params = { digest = m.hex({ len = 32 }) },
}, "handlers.hex")

app:get("/emails/:email", {
	params = { email = m.email() },
}, "handlers.email")

app:get("/tokens/:token", {
	params = { token = m.token({ max = 64 }) },
}, "handlers.token")

app:get("/search", {
	query = {
		q = m.string({ max = 80 }),
		page = m.u64({ optional = true }),
		exact = m.bool({ optional = true }),
	},
}, "handlers.search")

-- Hybrid-inline benchmark route: inline Lua in hybrid mode, Zig in static mode.
local mode = _G.METEORITE_BUILD_MODE or "release-static"
local is_hybrid = mode == "release-hybrid" or mode == "hybrid" or mode == "hybrid_dev"
if is_hybrid then
	local function app_cjson()
		return require("cjson")
	end

	local function app_render(template, data)
		local etlua = require("etlua")
		if etlua.render then
			return etlua.render(template, data)
		end
		local fn = assert(etlua.compile(template))
		return fn(data)
	end

	local app_sqlite_env = nil
	local app_sqlite_conn = nil
	local function app_sqlite()
		if app_sqlite_conn then
			return app_sqlite_conn
		end
		local luasql = require("luasql.sqlite3")
		app_sqlite_env = luasql.sqlite3()
		app_sqlite_conn = assert(app_sqlite_env:connect(":memory:"))
		assert(
			app_sqlite_conn:execute(
				"CREATE TABLE bench_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)"
			)
		)
		for i = 1, 100 do
			assert(
				app_sqlite_conn:execute(
					string.format(
						"INSERT INTO bench_items (id, name, value) VALUES (%d, 'item-%03d', %d)",
						i,
						i,
						i * 10
					)
				)
			)
		end
		return app_sqlite_conn
	end

	local function sqlite_fetch_one(sql)
		local cur = assert(app_sqlite():execute(sql))
		local row = cur:fetch({}, "a")
		cur:close()
		return row
	end

	local function sqlite_fetch_count(sql)
		local cur = assert(app_sqlite():execute(sql))
		local count = 0
		while cur:fetch({}, "a") do
			count = count + 1
		end
		cur:close()
		return count
	end

	app:get("/__bench/lua-empty", function() end)
	app:get("/__bench/lua-return-string", function()
		return "ok"
	end)
	app:get("/__bench/lua-text-direct", function()
		return text("ok")
	end)
	app:get("/__bench/lua-response-table", function()
		return { status = 200, content_type = "text/plain; charset=utf-8", body = "ok" }
	end)
	app:get("/__bench/lua-direct-param/:id", {
		params = { id = m.u64() },
	}, function(id)
		return id
	end)
	app:get("/__bench/lua-ctx-param/:id", {
		params = { id = m.u64() },
	}, function(ctx)
		return ctx:param("id")
	end)
	app:get("/__bench/lua-req-table/:id", {
		params = { id = m.u64() },
	}, function(req)
		return req.params.id
	end)
	app:post("/__bench/lua-body-1k", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		return ctx:body()
	end)
	app:get("/__bench/lua-json-small", function()
		return json({ ok = true })
	end)
	app:get("/__bench/lua-state-counter", function()
		__bench_counter = (__bench_counter or 0) + 1
		return tostring(__bench_counter)
	end)
	app:get("/__bench/lua-sleep-1s", function()
		os.execute("sleep 1")
		return "slept"
	end)
	app:get("/__bench/lua-echo-param/:id", {
		params = { id = m.string({ max = 64 }) },
	}, function(id)
		return id
	end)
	app:post("/__bench/lua-echo-body", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		return ctx:body()
	end)
	app:get("/__bench/lua-loop-0", function()
		local x = 0
		return tostring(x)
	end)
	app:get("/__bench/lua-loop-10", function()
		local x = 0
		for i = 1, 10 do
			x = x + i
		end
		return tostring(x)
	end)
	app:get("/__bench/lua-loop-100", function()
		local x = 0
		for i = 1, 100 do
			x = x + i
		end
		return tostring(x)
	end)
	app:get("/__bench/lua-loop-1000", function()
		local x = 0
		for i = 1, 1000 do
			x = x + i
		end
		return tostring(x)
	end)
	app:get("/__bench/lua-loop-10000", function()
		local x = 0
		for i = 1, 10000 do
			x = x + i
		end
		return tostring(x)
	end)
	app:get("/__bench/lua-loop-100000", function()
		local x = 0
		for i = 1, 100000 do
			x = x + i
		end
		return tostring(x)
	end)
	app:get("/hybrid-inline", function(ctx)
		return "ok"
	end)
	app:get("/__bench/hybrid-inline", function(ctx)
		return "ok"
	end)
	app:get("/__bench/hybrid-inline-text-literal", function(ctx)
		return ctx:text("ok")
	end)
	app:get("/__bench/hybrid-inline-params/:id", {
		params = { id = m.u64() },
	}, function(id)
		return tostring(id)
	end)
	app:post("/__bench/hybrid-inline-echo", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		return ctx:body()
	end)
	app:get("/__app/json/encode-small", function()
		local cjson = require("cjson")
		local encoded = cjson.encode({ ok = true, name = "meteorite", n = 123 })
		local decoded = cjson.decode(encoded)
		return string.format("json:encode-small:%s:%d:%s", decoded.name, decoded.n, tostring(decoded.ok))
	end)
	app:post("/__app/json/decode-1kb", {
		body = { max = "4kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		local decoded = require("cjson").decode(ctx:body())
		return string.format("json:decode-1kb:%s:%d:%s", decoded.name, decoded.n, decoded.payload:sub(1, 8))
	end)
	app:post("/__app/json/roundtrip-1kb", {
		body = { max = "4kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		local cjson = require("cjson")
		local decoded = cjson.decode(ctx:body())
		local encoded = cjson.encode(decoded)
		local again = cjson.decode(encoded)
		return string.format("json:roundtrip-1kb:%s:%d:%d", again.name, again.n, #again.payload)
	end)
	app:get("/__app/template/hello", function()
		local etlua = require("etlua")
		local rendered = etlua.render and etlua.render("Hello <%= name %>!", { name = "Meteorite" })
			or assert(etlua.compile("Hello <%= name %>!"))({ name = "Meteorite" })
		return "template:hello:" .. rendered
	end)
	app:get("/__app/template/list-100", function()
		local rows = {}
		for i = 1, 100 do
			rows[i] = { id = i, name = string.format("item-%03d", i) }
		end
		local etlua = require("etlua")
		local template = "<% for _, item in ipairs(rows) do %><%= item.id %>:<%= item.name %>\n<% end %>"
		local rendered = etlua.render and etlua.render(template, { rows = rows, ipairs = ipairs })
			or assert(etlua.compile(template))({ rows = rows, ipairs = ipairs })
		return string.format("template:list-100:%d:%s", #rendered, rendered:sub(1, 10))
	end)
	app:get("/__app/sqlite/select-one", function()
		local luasql = require("luasql.sqlite3")
		if not _G.__bench_app_sqlite_conn then
			_G.__bench_app_sqlite_env = luasql.sqlite3()
			_G.__bench_app_sqlite_conn = assert(_G.__bench_app_sqlite_env:connect(":memory:"))
			assert(
				_G.__bench_app_sqlite_conn:execute(
					"CREATE TABLE bench_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)"
				)
			)
			for i = 1, 100 do
				assert(
					_G.__bench_app_sqlite_conn:execute(
						string.format(
							"INSERT INTO bench_items (id, name, value) VALUES (%d, 'item-%03d', %d)",
							i,
							i,
							i * 10
						)
					)
				)
			end
		end
		local cur = assert(_G.__bench_app_sqlite_conn:execute("SELECT name, value FROM bench_items WHERE id = 42"))
		local row = cur:fetch({}, "a")
		cur:close()
		return string.format("sqlite:select-one:%s:%s", row.name, row.value)
	end)
	app:get("/__app/sqlite/select-100", function()
		local luasql = require("luasql.sqlite3")
		if not _G.__bench_app_sqlite_conn then
			_G.__bench_app_sqlite_env = luasql.sqlite3()
			_G.__bench_app_sqlite_conn = assert(_G.__bench_app_sqlite_env:connect(":memory:"))
			assert(
				_G.__bench_app_sqlite_conn:execute(
					"CREATE TABLE bench_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)"
				)
			)
			for i = 1, 100 do
				assert(
					_G.__bench_app_sqlite_conn:execute(
						string.format(
							"INSERT INTO bench_items (id, name, value) VALUES (%d, 'item-%03d', %d)",
							i,
							i,
							i * 10
						)
					)
				)
			end
		end
		local cur =
			assert(_G.__bench_app_sqlite_conn:execute("SELECT id, name, value FROM bench_items ORDER BY id LIMIT 100"))
		local count = 0
		while cur:fetch({}, "a") do
			count = count + 1
		end
		cur:close()
		return string.format("sqlite:select-100:%d", count)
	end)
	app:post("/__app/sqlite/insert-small", {
		body = { max = "4kb" },
		memory = { request_arena = "16kb" },
	}, function(ctx)
		local data = require("cjson").decode(ctx:body())
		local luasql = require("luasql.sqlite3")
		if not _G.__bench_app_sqlite_conn then
			_G.__bench_app_sqlite_env = luasql.sqlite3()
			_G.__bench_app_sqlite_conn = assert(_G.__bench_app_sqlite_env:connect(":memory:"))
			assert(
				_G.__bench_app_sqlite_conn:execute(
					"CREATE TABLE bench_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)"
				)
			)
			for i = 1, 100 do
				assert(
					_G.__bench_app_sqlite_conn:execute(
						string.format(
							"INSERT INTO bench_items (id, name, value) VALUES (%d, 'item-%03d', %d)",
							i,
							i,
							i * 10
						)
					)
				)
			end
		end
		local conn = _G.__bench_app_sqlite_conn
		assert(
			conn:execute(
				"INSERT INTO bench_items (id, name, value) VALUES (1001, 'insert-small', " .. tostring(data.n) .. ")"
			)
		)
		local cur = assert(conn:execute("SELECT COUNT(*) AS count FROM bench_items WHERE id = 1001"))
		local row = cur:fetch({}, "a")
		cur:close()
		assert(conn:execute("DELETE FROM bench_items WHERE id = 1001"))
		return "sqlite:insert-small:" .. tostring(row.count)
	end)
	app:get("/__app/pipeline/cors", function()
		return "pipeline:cors:ok"
	end)
	app:get("/__app/pipeline/cors-json-template", function()
		local cjson = require("cjson")
		local etlua = require("etlua")
		local rendered = etlua.render and etlua.render("<%= message %>", { message = "cors-json-template" })
			or assert(etlua.compile("<%= message %>"))({ message = "cors-json-template" })
		local decoded = cjson.decode(cjson.encode({ rendered = rendered }))
		return "pipeline:cors-json-template:" .. decoded.rendered
	end)
	app:get("/__app/full/sqlite-json-template", function()
		local luasql = require("luasql.sqlite3")
		if not _G.__bench_app_sqlite_conn then
			_G.__bench_app_sqlite_env = luasql.sqlite3()
			_G.__bench_app_sqlite_conn = assert(_G.__bench_app_sqlite_env:connect(":memory:"))
			assert(
				_G.__bench_app_sqlite_conn:execute(
					"CREATE TABLE bench_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)"
				)
			)
			for i = 1, 100 do
				assert(
					_G.__bench_app_sqlite_conn:execute(
						string.format(
							"INSERT INTO bench_items (id, name, value) VALUES (%d, 'item-%03d', %d)",
							i,
							i,
							i * 10
						)
					)
				)
			end
		end
		local cur = assert(_G.__bench_app_sqlite_conn:execute("SELECT name, value FROM bench_items WHERE id = 7"))
		local row = cur:fetch({}, "a")
		cur:close()
		local cjson = require("cjson")
		local decoded = cjson.decode(cjson.encode({ name = row.name, value = tonumber(row.value) }))
		decoded.value = math.floor(decoded.value)
		local etlua = require("etlua")
		local rendered = etlua.render and etlua.render("<%= name %>:<%= value %>", decoded)
			or assert(etlua.compile("<%= name %>:<%= value %>"))(decoded)
		return "full:sqlite-json-template:" .. rendered
	end)
	app:get("/__bench/lua-debug-state", function(ctx)
		local d = ctx:debug()
		return tostring(d.lua_state_id)
	end)
	app:get("/__bench/lua-global-counter", function(ctx)
		_G.__meteorite_global_counter = (_G.__meteorite_global_counter or 0) + 1
		local d = ctx:debug()
		return tostring(d.lua_state_id) .. ":" .. tostring(_G.__meteorite_global_counter)
	end)
	app:get("/__bench/lua-state-leak", function(ctx)
		local before = ctx:get("leak")
		ctx:set("leak", "set")
		return before == nil and "clean" or "leaked"
	end)
	app:get("/__bench/lua-shared-store", function(ctx)
		return tostring(ctx:shared_counter())
	end)
	app:get("/__bench/lua-worker-store", function(ctx)
		local d = ctx:debug()
		return tostring(d.lua_state_id) .. ":" .. tostring(ctx:worker_counter())
	end)
	app:get("/__bench/lua-require-cache", function(ctx)
		local probe = require("bench_lua_probe")
		local d = ctx:debug()
		return tostring(d.lua_state_id) .. ":" .. probe.hit()
	end)
else
	app:get("/__bench/lua-empty", "handlers.lua_empty")
	app:get("/__bench/lua-return-string", "handlers.bench_hybrid_inline")
	app:get("/__bench/lua-text-direct", "handlers.bench_hybrid_inline")
	app:get("/__bench/lua-response-table", "handlers.bench_hybrid_inline")
	app:get("/__bench/lua-direct-param/:id", {
		params = { id = m.u64() },
	}, "handlers.hybrid_inline_params")
	app:get("/__bench/lua-ctx-param/:id", {
		params = { id = m.u64() },
	}, "handlers.hybrid_inline_params")
	app:get("/__bench/lua-req-table/:id", {
		params = { id = m.u64() },
	}, "handlers.hybrid_inline_params")
	app:post("/__bench/lua-body-1k", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, "handlers.hybrid_inline_echo")
	app:get("/__bench/lua-json-small", "handlers.bench_json_small")
	app:get("/__bench/lua-state-counter", "handlers.bench_hybrid_inline")
	app:get("/__bench/lua-sleep-1s", "handlers.bench_sleep_unavailable")
	app:get("/__bench/lua-echo-param/:id", {
		params = { id = m.string({ max = 64 }) },
	}, "handlers.hybrid_inline_params")
	app:post("/__bench/lua-echo-body", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, "handlers.hybrid_inline_echo")
	app:get("/__bench/lua-loop-0", "handlers.bench_loop_0")
	app:get("/__bench/lua-loop-10", "handlers.bench_loop_10")
	app:get("/__bench/lua-loop-100", "handlers.bench_loop_100")
	app:get("/__bench/lua-loop-1000", "handlers.bench_loop_1000")
	app:get("/__bench/lua-loop-10000", "handlers.bench_loop_10000")
	app:get("/__bench/lua-loop-100000", "handlers.bench_loop_100000")
	app:get("/hybrid-inline", "handlers.hybrid_inline")
	app:get("/__bench/hybrid-inline", "handlers.bench_hybrid_inline")
	app:get("/__bench/hybrid-inline-text-literal", "handlers.bench_hybrid_inline_text_literal")
	app:get("/__bench/hybrid-inline-params/:id", {
		params = { id = m.u64() },
	}, "handlers.hybrid_inline_params")
	app:post("/__bench/hybrid-inline-echo", {
		body = { max = "8kb" },
		memory = { request_arena = "16kb" },
	}, "handlers.hybrid_inline_echo")
	app:get("/__bench/lua-debug-state", "handlers.bench_unavailable_state")
	app:get("/__bench/lua-global-counter", "handlers.bench_unavailable_global")
	app:get("/__bench/lua-state-leak", "handlers.bench_unavailable_leak")
	app:get("/__bench/lua-shared-store", "handlers.bench_unavailable_shared")
	app:get("/__bench/lua-worker-store", "handlers.bench_unavailable_worker")
	app:get("/__bench/lua-require-cache", "handlers.bench_unavailable_require")
end

return app
