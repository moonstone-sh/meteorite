local m = require("meteorite")

local app = m.app({ name = "web-standards", host = "127.0.0.1", port = 8080 })
local fixture_root = "fixtures/apps/web-standards"

local require_middleware_auth = m.plugin({
	kind = "middleware-auth",
	id = "web_standards_require_auth",
	execute = function(ctx)
		if not ctx:header("x-meteorite-auth") then
			return ctx:text(401, "middleware:unauthorized", {
				headers = { ["X-Meteorite-Middleware"] = "short-circuit" },
			})
		end
	end,
})

local set_middleware_scope = m.plugin({
	kind = "middleware-state",
	id = "web_standards_set_scope",
	execute = function(ctx)
		ctx:set("middleware_scope", ctx.scope.middleware or "missing")
	end,
})

local failing_middleware = m.plugin({
	kind = "middleware-error",
	id = "web_standards_failing_middleware",
	execute = function()
		error("middleware boom")
	end,
})

app:get("/health", function()
	return "ok"
end)

app:get(
	"/static/hello.txt",
	m.file(fixture_root .. "/public/hello.txt", {
		content_type = "text/plain; charset=utf-8",
		cache = "public, max-age=60",
	})
)

app:get(
	"/static/html",
	m.file(fixture_root .. "/public/index.html", {
		content_type = "text/html; charset=utf-8",
		cache = "no-cache",
		only = { accept = "text/html" },
	})
)

app:get(
	"/static/assets/:path*",
	m.dir(fixture_root .. "/public/assets", {
		param = "path",
		cache = "public, max-age=31536000, immutable",
		compressed = { gzip = true },
		types = { js = "application/javascript" },
	})
)

app:get("/headers/table", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "table-headers",
		headers = {
			["X-Meteorite-Test"] = "table",
			["Access-Control-Allow-Origin"] = "*",
		},
	}
end)

app:get("/headers/text-helper", function(ctx)
	return ctx:text(200, "text-helper", { headers = { ["X-Meteorite-Test"] = "text-helper" } })
end)

app:get("/headers/json-helper", function(ctx)
	return ctx:json({ ok = true }, { headers = { ["X-Meteorite-Test"] = "json-helper" } })
end)

app:get("/headers/bytes-helper", function(ctx)
	return ctx:bytes(200, "text/custom", "bytes-helper", { headers = { ["X-Meteorite-Test"] = "bytes-helper" } })
end)

app:get("/headers/request-lua", function(ctx)
	return table.concat({
		"lower=" .. tostring(ctx:header("x-meteorite-request") or "missing"),
		"upper=" .. tostring(ctx:header("X-METEORITE-REQUEST") or "missing"),
	}, ";")
end)

app:get("/headers/request-zig", "handlers.request_header_echo")

app:get("/headers/zig-text", "handlers.response_zig_text_headers")

app:get("/headers/zig-json", "handlers.response_zig_json_headers")

app:get("/headers/zig-bytes", "handlers.response_zig_bytes_headers")

app:get("/headers/zig-empty", "handlers.response_zig_empty_headers")

app:get("/redirect/zig", "handlers.response_zig_redirect")

app:get("/security/headers", function(ctx)
	return ctx:text(200, "security:headers", { headers = ctx:secure_headers() })
end)

app:get("/security/headers/custom", function(ctx)
	return ctx:text(200, "security:custom", {
		headers = ctx:secure_headers({
			csp = "default-src 'self'",
			hsts = { max_age = 31536000, include_subdomains = true },
			permissions_policy = "geolocation=()",
		}),
	})
end)

app:get("/security/request-id", function(ctx)
	local id = ctx:request_id()
	return ctx:text(200, "request-id:" .. id, { headers = { ["X-Request-ID"] = id } })
end)

app:get("/security/request-id-zig", "handlers.response_zig_request_id")

app:get("/security/cors", function(ctx)
	return ctx:text(
		200,
		"security:cors",
		{
			headers = ctx:cors_headers({
				origins = { "https://app.example", "https://admin.example" },
				methods = { "GET", "POST", "OPTIONS" },
				headers = { "Content-Type", "Authorization" },
				credentials = true,
				max_age = 600,
				expose_headers = { "X-Request-ID" },
			}),
		}
	)
end)

app:post("/security/cors", function(ctx)
	return ctx:text(
		200,
		"security:cors:post",
		{
			headers = ctx:cors_headers({
				origins = { "https://app.example", "https://admin.example" },
				methods = { "GET", "POST", "OPTIONS" },
				headers = { "Content-Type", "Authorization" },
				credentials = true,
				max_age = 600,
				expose_headers = { "X-Request-ID" },
			}),
		}
	)
end)

app:route("OPTIONS", "/security/cors", function(ctx)
	return ctx:bytes(
		204,
		"text/plain; charset=utf-8",
		"",
		{
			headers = ctx:cors_headers({
				origins = { "https://app.example", "https://admin.example" },
				methods = { "GET", "POST", "OPTIONS" },
				headers = { "Content-Type", "Authorization" },
				credentials = true,
				max_age = 600,
				expose_headers = { "X-Request-ID" },
			}),
		}
	)
end)

app:get("/security/auth/basic", function(ctx)
	local username, password = ctx:basic_auth()
	local ok = ctx:constant_time_equal(username or "", "meteorite") and ctx:constant_time_equal(password or "", "rocks")
	if not ok then
		return ctx:text(401, "auth:basic-denied", {
			headers = { ["WWW-Authenticate"] = 'Basic realm="meteorite"' },
		})
	end
	return ctx:text(200, "auth:basic-ok")
end)

app:get("/security/auth/bearer", function(ctx)
	local token = ctx:bearer_token()
	if not ctx:constant_time_equal(token or "", "meteorite-secret") then
		return ctx:text(401, "auth:bearer-denied", {
			headers = { ["WWW-Authenticate"] = 'Bearer realm="meteorite"' },
		})
	end
	return ctx:text(200, "auth:bearer-ok")
end)

app:get("/security/logging/safe-headers", function(ctx)
	local headers = ctx:safe_headers({ "Authorization", "Cookie", "X-Meteorite-Trace", "X-CSRF-Token" })
	return ctx:text(
		200,
		table.concat({
			"authorization=" .. tostring(headers.Authorization or "missing"),
			"cookie=" .. tostring(headers.Cookie or "missing"),
			"trace=" .. tostring(headers["X-Meteorite-Trace"] or "missing"),
			"csrf=" .. tostring(headers["X-CSRF-Token"] or "missing"),
		}, ";")
	)
end)

app:get("/observability/log", function(ctx)
	ctx:log("info", "web standards json", {
		method = "GET",
		trace = ctx:safe_header("X-Meteorite-Trace"),
		secret = ctx:safe_header("Authorization"),
	})
	ctx:log("info", "web standards plain", {
		method = "GET",
		trace = ctx:safe_header("X-Meteorite-Trace"),
		secret = ctx:safe_header("Authorization"),
	}, { format = "plain" })
	return ctx:text(200, "observability:log")
end)

app:get("/observability/server-timing", function(ctx)
	local timings = {}
	local body = ctx:timing_stage(timings, "handler", function()
		return "observability:timing"
	end, { desc = "Lua handler" })
	timings[#timings + 1] = { name = "response", dur = 2.5, desc = "response write" }
	return ctx:text(200, body, { headers = ctx:server_timing(timings) })
end)

app:post("/validation/contracts/:id", {
	params = { id = m.u64() },
	query = { verbose = m.bool({ optional = true }) },
	headers = { ["x-meteorite-token"] = m.token() },
	cookies = { session = m.token() },
	json = { email = m.email({ optional = true }) },
	form = { csrf = m.token({ optional = true }) },
	responses = {
		[200] = { json = { ok = m.bool() } },
	},
}, function(ctx)
	return ctx:text(200, "validation:contracts")
end)

app:get("/errors/lua-handler", function()
	error("handler boom")
end)

app:get("/errors/zig-handler", "handlers.response_zig_error")

app:mount("/errors/plugin", {
	id = "plugin_error",
	plugins = { failing_middleware },
}, function(plugin_error)
	plugin_error:get("/boom", function()
		return "unreachable"
	end)
end)

app:mount("/middleware", {
	id = "middleware",
	context = { middleware = "scoped" },
	plugins = { require_middleware_auth, set_middleware_scope },
}, function(middleware)
	middleware:get("/scoped", function(ctx)
		return "middleware:" .. tostring(ctx:get("middleware_scope") or "missing")
	end)
end)

app:get({
	route = "/middleware/post-header",
	pipeline = function(ctx)
		ctx:handle({ id = "post_header_handle", strat = "zig", symbol = "response_post_header_base" })
		ctx:hook("post_handler", {
			id = "post_header_hook",
			strat = "zig",
			symbol = "response_post_header_hook",
			writes = { "response.headers" },
			may_short_circuit = false,
		})
	end,
})

app:get({
	route = "/middleware/pre-handler",
	pipeline = function(ctx)
		ctx:hook("pre_handler", {
			id = "pre_handler_state_hook",
			strat = "zig",
			symbol = "response_pre_handler_hook",
			writes = { "state.pre_handler" },
			may_short_circuit = false,
		})
		ctx:handle({ id = "pre_handler_handle", strat = "zig", symbol = "response_pre_handler_base" })
	end,
})

app:get("/headers/invalid/reserved", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "bad-reserved",
		headers = { ["Content-Length"] = "999" },
	}
end)

app:get("/headers/invalid/name-crlf", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "bad-name",
		headers = { ["X-Bad\r\nInjected"] = "value" },
	}
end)

app:get("/headers/invalid/value-crlf", function(ctx)
	return ctx:text(200, "bad-value", { headers = { ["X-Meteorite-Test"] = "safe\r\nInjected: bad" } })
end)

app:get("/headers/invalid/helper-reserved", function(ctx)
	return ctx:text(200, "bad-helper-reserved", { headers = { ["Content-Length"] = "999" } })
end)

app:get("/headers/invalid/table-value-crlf", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "bad-table-value",
		headers = { ["X-Meteorite-Test"] = "safe\r\nInjected: bad" },
	}
end)

app:get("/headers/invalid/zig-name-crlf", "handlers.response_zig_invalid_header_name")

app:get("/headers/invalid/zig-value-crlf", "handlers.response_zig_invalid_header_value")

app:get("/headers/invalid/zig-reserved", "handlers.response_zig_reserved_header")

app:get({
	route = "/headers/invalid/post-hook-value-crlf",
	pipeline = function(ctx)
		ctx:handle({
			id = "post_header_injection_handle",
			strat = "zig",
			symbol = "response_post_header_injection_base",
		})
		ctx:hook("post_handler", {
			id = "post_header_injection_hook",
			strat = "zig",
			symbol = "response_post_header_injection_hook",
			writes = { "response.headers" },
			may_short_circuit = false,
		})
	end,
})

app:get("/cors/simple", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "cors:simple",
		headers = { ["Access-Control-Allow-Origin"] = "*" },
	}
end)

app:head("/head/explicit", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "explicit-head-body",
		headers = { ["X-Meteorite-Test"] = "head-explicit" },
	}
end)

app:get("/head/implicit", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "implicit-head-body",
		headers = { ["X-Meteorite-Test"] = "head-implicit" },
	}
end)

app:post("/method/post-only", function()
	return "post-only"
end)

app:get("/method/multi", function()
	return "multi-get"
end)

app:post("/method/multi", function()
	return "multi-post"
end)

app:head("/method/multi", function()
	return "multi-head"
end)

app:head("/method/get-and-head", function()
	return "explicit-head"
end)

app:get("/method/get-and-head", function()
	return "explicit-get"
end)

app:post("/cors/preflight", function()
	return "cors:post"
end)

app:head("/cors/preflight", function()
	return "cors:head"
end)

app:get("/redirect/basic", function()
	return {
		status = 302,
		content_type = "text/plain; charset=utf-8",
		body = "redirect",
		headers = { Location = "/health" },
	}
end)

app:get("/cookies/read", function(ctx)
	return "cookie:" .. tostring(ctx:cookie("session") or "missing")
end)

app:get("/cookies/set", function()
	return {
		status = 200,
		content_type = "text/plain; charset=utf-8",
		body = "cookie:set",
		headers = { ["Set-Cookie"] = "session=abc123; Path=/; HttpOnly; SameSite=Lax" },
	}
end)

app:get("/cookies/helper-lua", function(ctx)
	return ctx:text(200, "cookie:helper-lua", {
		headers = { ["Set-Cookie"] = ctx:set_cookie("session", "luahelper") },
	})
end)

app:get("/cookies/helper-zig", "handlers.response_zig_set_cookie")

app:get("/query/typed", {
	query = {
		q = m.string({ max = 16 }),
		page = m.u64({ optional = true }),
		exact = m.bool({ optional = true }),
	},
}, function(ctx)
	return table.concat({
		"q=" .. tostring(ctx:query("q") or ""),
		"page=" .. tostring(ctx:query("page") or ""),
		"exact=" .. tostring(ctx:query("exact") or ""),
	}, ";")
end)

app:get("/query/repeated", function(ctx)
	return "tag=" .. tostring(ctx:query("tag") or "missing")
end)

app:get("/query/all", function(ctx)
	local tags = ctx:query_all("tag") or {}
	return "tags=" .. table.concat(tags, ",")
end)

app:get("/query/decoded", function(ctx)
	return "q=" .. tostring(ctx:query("q") or "missing")
end)

app:get("/params/lua/:id", {
	params = { id = m.u64() },
}, function(ctx)
	return "param-lua:" .. tostring(ctx:param("id")) .. ":" .. tostring(ctx:param("missing") or "missing")
end)

app:get("/params/zig/:id", {
	params = { id = m.u64() },
}, "handlers.param_zig")

app:post("/body/echo", {
	body = { max = "4b" },
	memory = { request_arena = "16kb" },
}, function(ctx)
	return "body:" .. ctx:body()
end)

app:post("/body/repeat-read", {
	body = { max = "16b" },
	memory = { request_arena = "16kb" },
}, function(ctx)
	local first = ctx:body()
	local second = ctx:body()
	return "repeat:" .. first .. ":" .. second
end)

app:post("/body/repeat-read-zig", {
	body = { max = "16b" },
	memory = { request_arena = "16kb" },
}, "handlers.body_repeat_zig")

app:post("/body/json", {
	body = { max = "1kb" },
	memory = { request_arena = "16kb" },
}, function(ctx)
	local data, err = ctx:json_body()
	if not data then
		return ctx:text(400, err or "invalid json body")
	end
	return "json:" .. tostring(data.name) .. ":" .. tostring(math.floor(data.n or 0)) .. ":" .. tostring(data.ok)
end)

app:post("/body/form", {
	body = { max = "1kb" },
	memory = { request_arena = "16kb" },
}, function(ctx)
	local form, err = ctx:form_body()
	if not form then
		return ctx:text(400, err or "invalid form body")
	end
	return "form:" .. tostring(form.name or "") .. ":" .. tostring(form.city or "") .. ":" .. tostring(form.empty or "")
end)

app:delete("/body/no-body", function()
	return "delete:no-body"
end)

return app
