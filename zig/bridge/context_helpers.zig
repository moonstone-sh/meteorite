pub const json_body_helper =
    \\return function(ctx)
    \\  local ok, cjson = pcall(require, "cjson")
    \\  if not ok then return nil, "json body parser unavailable" end
    \\  local decoded_ok, value = pcall(cjson.decode, ctx:body())
    \\  if not decoded_ok then return nil, "invalid json body" end
    \\  return value, nil
    \\end
;

pub const form_body_helper =
    \\local function decode_component(value)
    \\  local out = {}
    \\  local i = 1
    \\  while i <= #value do
    \\    local ch = value:sub(i, i)
    \\    if ch == "+" then
    \\      out[#out + 1] = " "
    \\      i = i + 1
    \\    elseif ch == "%" then
    \\      local hex = value:sub(i + 1, i + 2)
    \\      if not hex:match("^%x%x$") then return nil end
    \\      local byte = tonumber(hex, 16)
    \\      if byte == 0 or byte == 10 or byte == 13 then return nil end
    \\      out[#out + 1] = string.char(byte)
    \\      i = i + 3
    \\    else
    \\      local byte = ch:byte()
    \\      if byte == 0 or byte == 10 or byte == 13 then return nil end
    \\      out[#out + 1] = ch
    \\      i = i + 1
    \\    end
    \\  end
    \\  return table.concat(out)
    \\end
    \\return function(ctx)
    \\  local content_type = ctx:header("content-type") or ""
    \\  if not content_type:lower():match("^application/x%-www%-form%-urlencoded[%s;]?") then
    \\    return nil, "unsupported form content type"
    \\  end
    \\  local result = {}
    \\  local body = ctx:body()
    \\  if body == "" then return result, nil end
    \\  for pair in (body .. "&"):gmatch("([^&]*)&") do
    \\    local eq = pair:find("=", 1, true)
    \\    local raw_name = eq and pair:sub(1, eq - 1) or pair
    \\    local raw_value = eq and pair:sub(eq + 1) or ""
    \\    local name = decode_component(raw_name)
    \\    local value = decode_component(raw_value)
    \\    if not name or not value or name == "" then return nil, "invalid form body" end
    \\    if result[name] == nil then result[name] = value end
    \\  end
    \\  return result, nil
    \\end
;

pub const secure_headers_helper =
    \\return function(ctx, opts)
    \\  opts = opts or {}
    \\  local headers = {
    \\    ["X-Content-Type-Options"] = opts.nosniff == false and nil or "nosniff",
    \\    ["X-Frame-Options"] = opts.frame_options == false and nil or (opts.frame_options or "DENY"),
    \\    ["Referrer-Policy"] = opts.referrer_policy == false and nil or (opts.referrer_policy or "no-referrer"),
    \\    ["Cross-Origin-Opener-Policy"] = opts.coop == false and nil or (opts.coop or "same-origin"),
    \\  }
    \\  if opts.csp then headers["Content-Security-Policy"] = opts.csp end
    \\  if opts.permissions_policy then headers["Permissions-Policy"] = opts.permissions_policy end
    \\  if opts.hsts then
    \\    local hsts = opts.hsts
    \\    if hsts == true then hsts = { max_age = 31536000 } end
    \\    local value = "max-age=" .. tostring(hsts.max_age or hsts.maxAge or 31536000)
    \\    if hsts.include_subdomains or hsts.includeSubDomains then value = value .. "; includeSubDomains" end
    \\    if hsts.preload then value = value .. "; preload" end
    \\    headers["Strict-Transport-Security"] = value
    \\  end
    \\  if type(opts.extra) == "table" then
    \\    for key, value in pairs(opts.extra) do headers[key] = value end
    \\  end
    \\  return headers
    \\end
;

pub const cors_headers_helper =
    \\local function contains(list, value)
    \\  if type(list) ~= "table" then return false end
    \\  for _, item in ipairs(list) do if item == value then return true end end
    \\  return false
    \\end
    \\local function join(list)
    \\  if type(list) == "string" then return list end
    \\  if type(list) ~= "table" then return nil end
    \\  return table.concat(list, ", ")
    \\end
    \\return function(ctx, opts)
    \\  opts = opts or {}
    \\  local request_origin = ctx:header("origin") or ctx:header("Origin")
    \\  local origin = nil
    \\  if opts.origin == "*" or opts.origins == "*" then
    \\    origin = "*"
    \\  elseif type(opts.origin) == "string" then
    \\    origin = opts.origin == request_origin and request_origin or nil
    \\  elseif type(opts.origins) == "table" then
    \\    origin = contains(opts.origins, request_origin) and request_origin or nil
    \\  elseif opts.origin == nil and opts.origins == nil then
    \\    origin = request_origin
    \\  end
    \\  if opts.credentials and origin == "*" and request_origin then origin = request_origin end
    \\  if not origin then return {} end
    \\  local headers = { ["Access-Control-Allow-Origin"] = origin, ["Vary"] = "Origin" }
    \\  if opts.credentials then headers["Access-Control-Allow-Credentials"] = "true" end
    \\  local methods = join(opts.methods)
    \\  if methods then headers["Access-Control-Allow-Methods"] = methods end
    \\  local allowed_headers = join(opts.headers)
    \\  if allowed_headers then headers["Access-Control-Allow-Headers"] = allowed_headers end
    \\  if opts.max_age or opts.maxAge then headers["Access-Control-Max-Age"] = tostring(opts.max_age or opts.maxAge) end
    \\  local expose = join(opts.expose_headers or opts.exposeHeaders)
    \\  if expose then headers["Access-Control-Expose-Headers"] = expose end
    \\  return headers
    \\end
;

pub const server_timing_helper =
    \\local function token(value)
    \\  value = tostring(value or ""):gsub("[^A-Za-z0-9!#$%%&'*+%.^_`|~-]", "_")
    \\  if value == "" then value = "stage" end
    \\  return value:sub(1, 64)
    \\end
    \\local function desc(value)
    \\  value = tostring(value or ""):gsub("[%z\r\n]", " "):gsub('"', "'")
    \\  return value:sub(1, 128)
    \\end
    \\local function dur(value)
    \\  value = tonumber(value or 0) or 0
    \\  if value < 0 then value = 0 end
    \\  return string.format("%.3f", value)
    \\end
    \\local function append(parts, name, metric)
    \\  if type(metric) == "number" then metric = { dur = metric } end
    \\  if type(metric) ~= "table" then return end
    \\  local item = token(metric.name or name)
    \\  local duration = metric.dur or metric.duration_ms or metric.durationMs or metric.duration
    \\  if duration ~= nil then item = item .. ";dur=" .. dur(duration) end
    \\  if metric.desc or metric.description then item = item .. ";desc=\"" .. desc(metric.desc or metric.description) .. "\"" end
    \\  parts[#parts + 1] = item
    \\end
    \\local function headers(_, metrics)
    \\  local parts = {}
    \\  if type(metrics) == "table" then
    \\    for _, metric in ipairs(metrics) do append(parts, metric.name, metric) end
    \\    for name, metric in pairs(metrics) do if type(name) ~= "number" then append(parts, name, metric) end end
    \\  end
    \\  if #parts == 0 then return {} end
    \\  return { ["Server-Timing"] = table.concat(parts, ", ") }
    \\end
    \\local function stage(_, metrics, name, fn, opts)
    \\  if type(metrics) ~= "table" then error("timing_stage metrics must be a table") end
    \\  if type(fn) ~= "function" then error("timing_stage requires a function") end
    \\  local started = os.clock()
    \\  local result = fn()
    \\  local elapsed = (os.clock() - started) * 1000
    \\  opts = type(opts) == "table" and opts or {}
    \\  metrics[#metrics + 1] = { name = token(name), dur = elapsed, desc = opts.desc or opts.description }
    \\  return result
    \\end
    \\return { headers = headers, stage = stage }
;

pub const constant_time_equal_helper =
    \\return function(_, left, right)
    \\  left = tostring(left or "")
    \\  right = tostring(right or "")
    \\  local max_len = math.max(#left, #right)
    \\  local diff = (#left == #right) and 0 or 1
    \\  for i = 1, max_len do
    \\    local a = i <= #left and left:byte(i) or 0
    \\    local b = i <= #right and right:byte(i) or 0
    \\    if a ~= b then diff = 1 end
    \\  end
    \\  return diff == 0
    \\end
;

pub const basic_auth_helper =
    \\local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    \\local decode = {}
    \\for i = 1, #alphabet do decode[alphabet:sub(i, i)] = i - 1 end
    \\local function b64(value)
    \\  if type(value) ~= "string" or #value == 0 or #value % 4 ~= 0 or value:find("[^A-Za-z0-9%+/=]") then return nil end
    \\  local out = {}
    \\  for i = 1, #value, 4 do
    \\    local c1, c2, c3, c4 = value:sub(i, i), value:sub(i + 1, i + 1), value:sub(i + 2, i + 2), value:sub(i + 3, i + 3)
    \\    local n1, n2 = decode[c1], decode[c2]
    \\    local n3, n4 = c3 == "=" and 0 or decode[c3], c4 == "=" and 0 or decode[c4]
    \\    if not n1 or not n2 or not n3 or not n4 then return nil end
    \\    out[#out + 1] = string.char(n1 * 4 + math.floor(n2 / 16))
    \\    if c3 ~= "=" then out[#out + 1] = string.char((n2 % 16) * 16 + math.floor(n3 / 4)) end
    \\    if c4 ~= "=" then out[#out + 1] = string.char((n3 % 4) * 64 + n4) end
    \\  end
    \\  return table.concat(out)
    \\end
    \\return function(ctx)
    \\  local authorization = ctx:header("authorization") or ctx:header("Authorization")
    \\  if type(authorization) ~= "string" then return nil, nil end
    \\  local encoded = authorization:match("^[Bb][Aa][Ss][Ii][Cc]%s+(.+)$")
    \\  if not encoded then return nil, nil end
    \\  local decoded = b64(encoded)
    \\  if not decoded or decoded:find("[%z\r\n]") then return nil, nil end
    \\  local colon = decoded:find(":", 1, true)
    \\  if not colon then return nil, nil end
    \\  return decoded:sub(1, colon - 1), decoded:sub(colon + 1)
    \\end
;

pub const bearer_token_helper =
    \\return function(ctx)
    \\  local authorization = ctx:header("authorization") or ctx:header("Authorization")
    \\  if type(authorization) ~= "string" then return nil end
    \\  local token = authorization:match("^[Bb][Ee][Aa][Rr][Ee][Rr]%s+([^%s,]+)%s*$")
    \\  if type(token) ~= "string" or #token > 8192 or token:find("[%z\r\n]") then return nil end
    \\  return token
    \\end
;

pub const safe_header_helper =
    \\local sensitive = {
    \\  authorization = true,
    \\  cookie = true,
    \\  ["set-cookie"] = true,
    \\  ["proxy-authorization"] = true,
    \\  ["x-api-key"] = true,
    \\  ["x-auth-token"] = true,
    \\  ["x-csrf-token"] = true,
    \\}
    \\local function normalized(name) return tostring(name or ""):lower() end
    \\local function safe_one(ctx, name)
    \\  if sensitive[normalized(name)] then return "[redacted]" end
    \\  return ctx:header(name)
    \\end
    \\local function safe_many(ctx, names)
    \\  local out = {}
    \\  if type(names) ~= "table" then return out end
    \\  for _, name in ipairs(names) do
    \\    local value = safe_one(ctx, name)
    \\    if value ~= nil then out[name] = value end
    \\  end
    \\  return out
    \\end
    \\return { one = safe_one, many = safe_many }
;

pub const log_helper =
    \\local function clean(value)
    \\  value = tostring(value or "")
    \\  value = value:gsub("[%z\r\n]", " ")
    \\  if #value > 4096 then value = value:sub(1, 4096) end
    \\  return value
    \\end
    \\local function quote_json(value)
    \\  value = clean(value)
    \\  value = value:gsub('\\\\', '\\\\\\\\'):gsub('"', '\\\\"'):gsub('\t', '\\\\t')
    \\  return '"' .. value .. '"'
    \\end
    \\local function encode_json(value)
    \\  local kind = type(value)
    \\  if kind == "nil" then return "null" end
    \\  if kind == "boolean" then return value and "true" or "false" end
    \\  if kind == "number" then return tostring(value) end
    \\  if kind == "string" then return quote_json(value) end
    \\  if kind == "table" then
    \\    local keys, parts = {}, {}
    \\    for key, _ in pairs(value) do keys[#keys + 1] = key end
    \\    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    \\    for _, key in ipairs(keys) do parts[#parts + 1] = quote_json(key) .. ":" .. encode_json(value[key]) end
    \\    return "{" .. table.concat(parts, ",") .. "}"
    \\  end
    \\  return quote_json("[" .. kind .. "]")
    \\end
    \\local function plain_value(value)
    \\  value = clean(value)
    \\  if value:find("%s") or value == "" then return '"' .. value:gsub('"', "'") .. '"' end
    \\  return value
    \\end
    \\return function(ctx, level, message, fields, opts)
    \\  if type(level) == "table" then fields, opts, level, message = level, message, "info", "request" end
    \\  level = clean(level or "info")
    \\  message = clean(message or "request")
    \\  fields = type(fields) == "table" and fields or {}
    \\  opts = type(opts) == "table" and opts or {}
    \\  local event = { level = level, message = message, request_id = ctx:request_id() }
    \\  for key, value in pairs(fields) do event[clean(key)] = value end
    \\  if opts.format == "plain" then
    \\    local keys, parts = {}, { "level=" .. plain_value(event.level), "message=" .. plain_value(event.message), "request_id=" .. plain_value(event.request_id) }
    \\    for key, _ in pairs(event) do if key ~= "level" and key ~= "message" and key ~= "request_id" then keys[#keys + 1] = key end end
    \\    table.sort(keys)
    \\    for _, key in ipairs(keys) do parts[#parts + 1] = clean(key) .. "=" .. plain_value(event[key]) end
    \\    io.stderr:write(table.concat(parts, " ") .. "\n")
    \\  else
    \\    io.stderr:write(encode_json(event) .. "\n")
    \\  end
    \\  return event
    \\end
;

