local json = require("utils.json")

local hybrid = {}
local app_stores = setmetatable({}, { __mode = "k" })

local function app_store(app)
  local store = app_stores[app]
  if not store then
    store = { capabilities = {} }
    app_stores[app] = store
  end
  return store
end

local function split_path(path)
  if path == "/" then return {} end
  local out = {}
  for part in tostring(path):gmatch("[^/]+") do out[#out + 1] = part end
  return out
end

local function split_target(target)
  local path, query = tostring(target):match("^([^?]*)%??(.*)$")
  if path == "" then path = "/" end
  return path, query or ""
end

local function parse_query(raw)
  local out = {}
  for part in tostring(raw):gmatch("[^&]+") do
    local key, value = part:match("^([^=]*)=(.*)$")
    if not key then key, value = part, "" end
    if key ~= "" and out[key] == nil then out[key] = value end
  end
  return out
end

local function validation_response(domain, field, reason)
  return {
    status = 400,
    content_type = "text/plain",
    body = "validation error",
    headers = {
      ["X-Meteorite-Validation-Domain"] = domain,
      ["X-Meteorite-Validation-Field"] = field,
      ["X-Meteorite-Validation-Reason"] = reason,
    },
  }
end

local function pattern_match(pattern, value)
  if not pattern or not pattern.parsed then return true end
  if #value < pattern.parsed.min or #value > pattern.parsed.max then return false end
  for i = 1, #value do
    local byte = value:byte(i)
    local ok = false
    for _, range in ipairs(pattern.parsed.ranges) do
      if byte >= range[1] and byte <= range[2] then ok = true; break end
    end
    if not ok then return false end
  end
  return true
end

local function validate_schema(schema, value)
  local kind = schema.kind or schema.type or "string"
  if schema.max_len and #value > schema.max_len then return false end
  if schema.exact_len and #value ~= schema.exact_len then return false end
  if schema.pattern and not pattern_match(schema.pattern, value) then return false end
  if kind == "pattern" then return pattern_match(schema, value) end
  if kind == "u64" then return value:match("^%d+$") ~= nil end
  if kind == "i32" then return value:match("^-?%d+$") ~= nil end
  if kind == "slug" then return value:match("^[a-z0-9_-]+$") ~= nil end
  if kind == "hex" then return value:match("^[0-9a-fA-F]+$") ~= nil end
  if kind == "uuid" then return value:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]%-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") ~= nil end
  if kind == "email" then
    if #value == 0 or #value > 254 then return false end
    local at = value:find("@", 1, true)
    if not at or value:find("@", at + 1, true) then return false end
    local local_part, domain = value:sub(1, at - 1), value:sub(at + 1)
    return #local_part > 0 and #local_part <= 64 and domain:match("^[A-Za-z0-9][A-Za-z0-9.-]*%.[A-Za-z0-9-]+$") ~= nil
  end
  if kind == "token" then return value:match("^[A-Za-z0-9_-]+$") ~= nil end
  if kind == "bool" then return value == "true" or value == "false" or value == "1" or value == "0" end
  return true
end

local function convert_schema(schema, value)
  local kind = schema.kind or schema.type or "string"
  if kind == "u64" or kind == "i32" then return tonumber(value) end
  if kind == "bool" then return value == "true" or value == "1" end
  return value
end

local function validate_specs(domain, specs, values)
  local out = {}
  for _, schema in ipairs(specs or {}) do
    local value = values[schema.name]
    if value == nil then
      if not schema.optional then return nil, validation_response(domain, schema.name, "missing") end
      out[schema.name] = nil
    else
      if not validate_schema(schema, value) then return nil, validation_response(domain, schema.name, "invalid") end
      out[schema.name] = convert_schema(schema, value)
    end
  end
  return out
end

local function match_query(route, query_values)
  return validate_specs("query", route.query, query_values)
end

local function request_headers(request)
  local out = {}
  for name, value in pairs(request.headers or {}) do out[tostring(name):lower()] = value end
  return out
end

local function parse_cookies(header)
  local out = {}
  if type(header) ~= "string" then return out end
  for part in header:gmatch("[^;]+") do
    local key, value = part:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
    if key then
      if out[key] ~= nil then out.__invalid_duplicate = key end
      out[key] = value
    end
  end
  return out
end

local function parse_form_values(body)
  local out = {}
  for pair in (tostring(body or "") .. "&"):gmatch("([^&]*)&") do
    if pair ~= "" then
      local eq = pair:find("=", 1, true)
      local name = eq and pair:sub(1, eq - 1) or pair
      local value = eq and pair:sub(eq + 1) or ""
      if name == "" or not name:match("^[^%%\r\n%z]+$") then out.__invalid = true end
      if value:find("%%[^%x]?") or value:find("[\r\n%z]") then out.__invalid = true end
      if out[name] ~= nil then out.__invalid = true end
      out[name] = value
    end
  end
  return out
end

local function parse_simple_json_object(body)
  body = tostring(body or "")
  local inner = body:match("^%s*{%s*(.-)%s*}%s*$")
  if not inner then return nil end
  local out = {}
  local index = 1
  while index <= #inner do
    while inner:sub(index, index):match("%s") do index = index + 1 end
    if index > #inner then break end
    local key, next_index = inner:match('^"([^"\\]*)"%s*:%s*()', index)
    if not key then return nil end
    index = next_index
    local value
    value, next_index = inner:match('^"([^"\\]*)"%s*()', index)
    if value == nil then
      local literal
      literal, next_index = inner:match('^([%-%d%.]+)%s*()', index)
      if literal then value = tonumber(literal) end
      if value == nil then
        literal, next_index = inner:match('^(true)%s*()', index)
        if literal then value = true end
      end
      if value == nil then
        literal, next_index = inner:match('^(false)%s*()', index)
        if literal then value = false end
      end
    end
    if value == nil then return nil end
    out[key] = value
    index = next_index
    local sep = inner:sub(index, index)
    if sep == "," then
      index = index + 1
    elseif sep == "" then
      break
    elseif sep:match("%s") then
      while inner:sub(index, index):match("%s") do index = index + 1 end
      if inner:sub(index, index) == "," then index = index + 1 elseif index <= #inner then return nil end
    else
      return nil
    end
  end
  return out
end

local function content_type(request)
  return tostring((request.headers or {})["content-type"] or (request.headers or {})["Content-Type"] or ""):lower()
end

local function validate_request_domains(route, request)
  local validation = route.validation or {}
  local headers = request_headers(request)
  local _, err = validate_specs("header", validation.headers, headers)
  if err then return err end
  local cookies = parse_cookies(headers.cookie)
  if cookies.__invalid_duplicate then return validation_response("cookie", cookies.__invalid_duplicate, "invalid") end
  _, err = validate_specs("cookie", validation.cookies, cookies)
  if err then return err end
  local ct = content_type(request)
  if ct:match("^application/json[%s;]?") and #(validation.json_body or {}) > 0 then
    local cjson_ok, cjson = pcall(require, "cjson")
    local ok, parsed
    if cjson_ok then ok, parsed = pcall(cjson.decode, request.body or "") else ok, parsed = true, parse_simple_json_object(request.body) end
    if not ok or type(parsed) ~= "table" then return validation_response("json", "body", "invalid") end
    _, err = validate_specs("json", validation.json_body, parsed)
    if err then return err end
  elseif #(validation.form_body or {}) > 0 then
    if not ct:match("^application/x%-www%-form%-urlencoded[%s;]?") then return validation_response("form", "content-type", "invalid") end
    local form = parse_form_values(request.body or "")
    if form.__invalid then return validation_response("form", "body", "invalid") end
    _, err = validate_specs("form", validation.form_body, form)
    if err then return err end
  end
  return nil
end

local function match_route(route, method, path)
  if route.method ~= method then return nil, "method" end
  local parts = split_path(path)
  local segments = route.path.segments
  if #parts ~= #segments then return nil end
  local params = {}
  local schemas = {}
  for _, schema in ipairs(route.params or {}) do schemas[schema.name] = schema end
  for i, segment in ipairs(segments) do
    local value = parts[i]
    if segment.kind == "literal" then
      if segment.value ~= value then return nil end
    else
      local schema = schemas[segment.name] or { type = "string" }
      if not validate_schema(schema, value) then return nil end
      params[segment.name] = value
    end
  end
  return params
end

local Context = {}
Context.__index = Context

local request_id_counter = 0

local function response_headers(opts)
  if type(opts) == "table" and type(opts.headers) == "table" then return opts.headers end
  return nil
end

local function with_response_headers(response, opts)
  local headers = response_headers(opts)
  if headers then response.headers = headers end
  return response
end

function Context:text(status_or_body, body, opts)
  local status, response_body = 200, status_or_body
  local options = body
  if type(status_or_body) == "number" then status, response_body, options = status_or_body, body, opts end
  self.response = { status = status, content_type = "text/plain; charset=utf-8", body = tostring(response_body or "") }
  return with_response_headers(self.response, options)
end

function Context:json(status_or_value, value, opts)
  local status, body = 200, status_or_value
  local options = value
  if type(status_or_value) == "number" then status, body, options = status_or_value, value, opts end
  self.response = { status = status, content_type = "application/json", body = json.encode(body) }
  return with_response_headers(self.response, options)
end

function Context:bytes(status, content_type, body, opts)
  local options = opts
  if body == nil then body, content_type, status = content_type, "application/octet-stream", 200 end
  self.response = { status = status, content_type = content_type, body = body or "" }
  return with_response_headers(self.response, options)
end

function Context:body()
  return self.request.body or ""
end

function Context:json_body()
  local ok, json = pcall(require, "cjson")
  if not ok then return nil, "json body parser unavailable" end
  local decoded_ok, decoded = pcall(json.decode, self:body())
  if not decoded_ok then return nil, "invalid json body" end
  return decoded, nil
end

local function decode_form_component(value)
  local out = {}
  local index = 1
  while index <= #value do
    local ch = value:sub(index, index)
    if ch == "+" then
      out[#out + 1] = " "
      index = index + 1
    elseif ch == "%" then
      local hex = value:sub(index + 1, index + 2)
      if not hex:match("^%x%x$") then return nil end
      local byte = tonumber(hex, 16)
      if byte == 0 or byte == 10 or byte == 13 then return nil end
      out[#out + 1] = string.char(byte)
      index = index + 3
    else
      local byte = ch:byte()
      if byte == 0 or byte == 10 or byte == 13 then return nil end
      out[#out + 1] = ch
      index = index + 1
    end
  end
  return table.concat(out)
end

function Context:form_body()
  local content_type = self:header("content-type") or ""
  if not content_type:lower():match("^application/x%-www%-form%-urlencoded[%s;]?") then
    return nil, "unsupported form content type"
  end
  local result = {}
  local body = self:body()
  if body == "" then return result, nil end
  for pair in (body .. "&"):gmatch("([^&]*)&") do
    local eq = pair:find("=", 1, true)
    local raw_name = eq and pair:sub(1, eq - 1) or pair
    local raw_value = eq and pair:sub(eq + 1) or ""
    local name = decode_form_component(raw_name)
    local value = decode_form_component(raw_value)
    if not name or not value or name == "" then return nil, "invalid form body" end
    if result[name] == nil then result[name] = value end
  end
  return result, nil
end

function Context:secure_headers(opts)
  opts = opts or {}
  local headers = {
    ["X-Content-Type-Options"] = opts.nosniff == false and nil or "nosniff",
    ["X-Frame-Options"] = opts.frame_options == false and nil or (opts.frame_options or "DENY"),
    ["Referrer-Policy"] = opts.referrer_policy == false and nil or (opts.referrer_policy or "no-referrer"),
    ["Cross-Origin-Opener-Policy"] = opts.coop == false and nil or (opts.coop or "same-origin"),
  }
  if opts.csp then headers["Content-Security-Policy"] = opts.csp end
  if opts.permissions_policy then headers["Permissions-Policy"] = opts.permissions_policy end
  if opts.hsts then
    local hsts = opts.hsts
    if hsts == true then hsts = { max_age = 31536000 } end
    local value = "max-age=" .. tostring(hsts.max_age or hsts.maxAge or 31536000)
    if hsts.include_subdomains or hsts.includeSubDomains then value = value .. "; includeSubDomains" end
    if hsts.preload then value = value .. "; preload" end
    headers["Strict-Transport-Security"] = value
  end
  if type(opts.extra) == "table" then
    for key, value in pairs(opts.extra) do headers[key] = value end
  end
  return headers
end

local function contains(list, value)
  if type(list) ~= "table" then return false end
  for _, item in ipairs(list) do if item == value then return true end end
  return false
end

local function join_header_list(list)
  if type(list) == "string" then return list end
  if type(list) ~= "table" then return nil end
  return table.concat(list, ", ")
end

function Context:cors_headers(opts)
  opts = opts or {}
  local request_origin = self:header("origin") or self:header("Origin")
  local origin = nil
  if opts.origin == "*" or opts.origins == "*" then
    origin = "*"
  elseif type(opts.origin) == "string" then
    origin = opts.origin == request_origin and request_origin or nil
  elseif type(opts.origins) == "table" then
    origin = contains(opts.origins, request_origin) and request_origin or nil
  elseif opts.origin == nil and opts.origins == nil then
    origin = request_origin
  end
  if opts.credentials and origin == "*" and request_origin then origin = request_origin end
  if not origin then return {} end
  local headers = { ["Access-Control-Allow-Origin"] = origin, ["Vary"] = "Origin" }
  if opts.credentials then headers["Access-Control-Allow-Credentials"] = "true" end
  local methods = join_header_list(opts.methods)
  if methods then headers["Access-Control-Allow-Methods"] = methods end
  local allowed_headers = join_header_list(opts.headers)
  if allowed_headers then headers["Access-Control-Allow-Headers"] = allowed_headers end
  if opts.max_age or opts.maxAge then headers["Access-Control-Max-Age"] = tostring(opts.max_age or opts.maxAge) end
  local expose = join_header_list(opts.expose_headers or opts.exposeHeaders)
  if expose then headers["Access-Control-Expose-Headers"] = expose end
  return headers
end

local function server_timing_token(value)
  value = tostring(value or ""):gsub("[^A-Za-z0-9!#$%%&'*+%.^_`|~-]", "_")
  if value == "" then value = "stage" end
  return value:sub(1, 64)
end

local function server_timing_desc(value)
  value = tostring(value or ""):gsub("[%z\r\n]", " "):gsub('"', "'")
  return value:sub(1, 128)
end

local function server_timing_duration(value)
  value = tonumber(value or 0) or 0
  if value < 0 then value = 0 end
  return string.format("%.3f", value)
end

local function append_server_timing(parts, name, metric)
  if type(metric) == "number" then metric = { dur = metric } end
  if type(metric) ~= "table" then return end
  local item = server_timing_token(metric.name or name)
  local duration = metric.dur or metric.duration_ms or metric.durationMs or metric.duration
  if duration ~= nil then item = item .. ";dur=" .. server_timing_duration(duration) end
  if metric.desc or metric.description then item = item .. ";desc=\"" .. server_timing_desc(metric.desc or metric.description) .. "\"" end
  parts[#parts + 1] = item
end

function Context:server_timing(metrics)
  local parts = {}
  if type(metrics) == "table" then
    for _, metric in ipairs(metrics) do append_server_timing(parts, metric.name, metric) end
    for name, metric in pairs(metrics) do
      if type(name) ~= "number" then append_server_timing(parts, name, metric) end
    end
  end
  if #parts == 0 then return {} end
  return { ["Server-Timing"] = table.concat(parts, ", ") }
end

function Context:timing_stage(metrics, name, fn, opts)
  assert(type(metrics) == "table", "timing_stage metrics must be a table")
  assert(type(fn) == "function", "timing_stage requires a function")
  local started = os.clock()
  local result = fn()
  local elapsed = (os.clock() - started) * 1000
  opts = type(opts) == "table" and opts or {}
  metrics[#metrics + 1] = { name = server_timing_token(name), dur = elapsed, desc = opts.desc or opts.description }
  return result
end

function Context:constant_time_equal(left, right)
  left = tostring(left or "")
  right = tostring(right or "")
  local max_len = math.max(#left, #right)
  local diff = #left == #right and 0 or 1
  for index = 1, max_len do
    local left_byte = index <= #left and left:byte(index) or 0
    local right_byte = index <= #right and right:byte(index) or 0
    if left_byte ~= right_byte then diff = 1 end
  end
  return diff == 0
end

local base64_decode = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for index = 1, #alphabet do base64_decode[alphabet:sub(index, index)] = index - 1 end
end

local function decode_base64(value)
  if type(value) ~= "string" or #value == 0 or #value % 4 ~= 0 or value:find("[^A-Za-z0-9%+/=]") then return nil end
  local out = {}
  for index = 1, #value, 4 do
    local c1, c2, c3, c4 = value:sub(index, index), value:sub(index + 1, index + 1), value:sub(index + 2, index + 2), value:sub(index + 3, index + 3)
    local n1, n2 = base64_decode[c1], base64_decode[c2]
    local n3, n4 = c3 == "=" and 0 or base64_decode[c3], c4 == "=" and 0 or base64_decode[c4]
    if not n1 or not n2 or not n3 or not n4 then return nil end
    out[#out + 1] = string.char(n1 * 4 + math.floor(n2 / 16))
    if c3 ~= "=" then out[#out + 1] = string.char((n2 % 16) * 16 + math.floor(n3 / 4)) end
    if c4 ~= "=" then out[#out + 1] = string.char((n3 % 4) * 64 + n4) end
  end
  return table.concat(out)
end

function Context:basic_auth()
  local authorization = self:header("authorization") or self:header("Authorization")
  if type(authorization) ~= "string" then return nil, nil end
  local encoded = authorization:match("^[Bb][Aa][Ss][Ii][Cc]%s+(.+)$")
  if not encoded then return nil, nil end
  local decoded = decode_base64(encoded)
  if not decoded or decoded:find("[%z\r\n]") then return nil, nil end
  local colon = decoded:find(":", 1, true)
  if not colon then return nil, nil end
  return decoded:sub(1, colon - 1), decoded:sub(colon + 1)
end

function Context:bearer_token()
  local authorization = self:header("authorization") or self:header("Authorization")
  if type(authorization) ~= "string" then return nil end
  local token = authorization:match("^[Bb][Ee][Aa][Rr][Ee][Rr]%s+([^%s,]+)%s*$")
  if type(token) ~= "string" or #token > 8192 or token:find("[%z\r\n]") then return nil end
  return token
end

local sensitive_log_headers = {
  authorization = true,
  cookie = true,
  ["set-cookie"] = true,
  ["proxy-authorization"] = true,
  ["x-api-key"] = true,
  ["x-auth-token"] = true,
  ["x-csrf-token"] = true,
}

function Context:safe_header(name)
  if sensitive_log_headers[tostring(name or ""):lower()] then return "[redacted]" end
  return self:header(name)
end

function Context:safe_headers(names)
  local result = {}
  if type(names) ~= "table" then return result end
  for _, name in ipairs(names) do
    local value = self:safe_header(name)
    if value ~= nil then result[name] = value end
  end
  return result
end

local function clean_log_value(value)
  value = tostring(value or ""):gsub("[%z\r\n]", " ")
  if #value > 4096 then value = value:sub(1, 4096) end
  return value
end

local function plain_log_value(value)
  value = clean_log_value(value)
  if value == "" or value:find("%s") then return '"' .. value:gsub('"', "'") .. '"' end
  return value
end

local function encode_log_json(value)
  local ok, json = pcall(require, "utils.json")
  if ok and json and json.encode then return json.encode(value) end
  return "{}"
end

function Context:log(level, message, fields, opts)
  if type(level) == "table" then
    fields, opts, level, message = level, message, "info", "request"
  end
  level = clean_log_value(level or "info")
  message = clean_log_value(message or "request")
  fields = type(fields) == "table" and fields or {}
  opts = type(opts) == "table" and opts or {}
  local event = { level = level, message = message, request_id = self:request_id() }
  for key, value in pairs(fields) do event[clean_log_value(key)] = value end
  if opts.format == "plain" then
    local keys, parts = {}, {
      "level=" .. plain_log_value(event.level),
      "message=" .. plain_log_value(event.message),
      "request_id=" .. plain_log_value(event.request_id),
    }
    for key, _ in pairs(event) do
      if key ~= "level" and key ~= "message" and key ~= "request_id" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = clean_log_value(key) .. "=" .. plain_log_value(event[key]) end
    io.stderr:write(table.concat(parts, " ") .. "\n")
  else
    io.stderr:write(encode_log_json(event) .. "\n")
  end
  return event
end

function Context:header(name)
  local headers = self.request.headers or {}
  if headers[name] ~= nil then return headers[name] end
  local wanted = tostring(name):lower()
  for header_name, value in pairs(headers) do
    if tostring(header_name):lower() == wanted then return value end
  end
  return nil
end

local function safe_request_id(value)
  return type(value) == "string" and #value > 0 and #value <= 128 and value:match("^[A-Za-z0-9_.:-]+$") ~= nil
end

function Context:request_id()
  if self._request_id then return self._request_id end
  local incoming = self:header("x-request-id") or self:header("X-Request-ID")
  if safe_request_id(incoming) then
    self._request_id = incoming
  else
    request_id_counter = request_id_counter + 1
    self._request_id = string.format("local-%08x", request_id_counter)
  end
  return self._request_id
end

local function cookie_value(header, name)
  if type(header) ~= "string" then return nil end
  local found = nil
  for part in header:gmatch("[^;]+") do
    local key, value = part:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
    if key == name then
      if found ~= nil then return nil end
      if value:sub(1, 1) == '"' then
        if value:sub(-1) ~= '"' or #value == 1 then return nil end
        value = value:sub(2, -2)
      elseif value:find('"', 1, true) then
        return nil
      end
      local decoded = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
      if decoded:find("%%") or decoded:find("[%z\r\n;\127]") then return nil end
      found = decoded
    end
  end
  return found
end

local function is_token(value)
  return type(value) == "string" and value:match("^[A-Za-z0-9!#$%%&'*+%.^_`|~-]+$") ~= nil
end

local function is_cookie_value(value)
  if type(value) ~= "string" or #value > 4096 then return false end
  for i = 1, #value do
    local byte = value:byte(i)
    local ok = byte == 0x21 or (byte >= 0x23 and byte <= 0x2b) or (byte >= 0x2d and byte <= 0x3a) or (byte >= 0x3c and byte <= 0x5b) or (byte >= 0x5d and byte <= 0x7e)
    if not ok then return false end
  end
  return true
end

local function valid_cookie_attr(value)
  if value == nil then return true end
  if type(value) ~= "string" or value == "" or #value > 1024 then return false end
  return value:find("[%z\r\n;\127]") == nil
end

local function append_cookie_attr(parts, name, value)
  if value ~= nil then parts[#parts + 1] = name .. "=" .. value end
end

function Context:set_cookie(name, value, opts)
  opts = opts or {}
  name = tostring(name or "")
  value = tostring(value or "")
  if not is_token(name) then error("invalid cookie name") end
  if not is_cookie_value(value) then error("invalid cookie value") end
  local path = opts.path == nil and "/" or tostring(opts.path)
  local domain = opts.domain ~= nil and tostring(opts.domain) or nil
  local expires = opts.expires ~= nil and tostring(opts.expires) or nil
  if not valid_cookie_attr(path) or not valid_cookie_attr(domain) or not valid_cookie_attr(expires) then error("invalid cookie attribute") end
  local secure = opts.secure ~= false
  local http_only = opts.http_only ~= false
  local same_site = opts.same_site == nil and "Lax" or tostring(opts.same_site)
  local same_site_lc = same_site:lower()
  if same_site_lc == "lax" then same_site = "Lax"
  elseif same_site_lc == "strict" then same_site = "Strict"
  elseif same_site_lc == "none" then same_site = "None"
  else error("invalid cookie same_site") end
  if same_site == "None" and not secure then error("SameSite=None requires Secure") end
  local parts = { name .. "=" .. value }
  append_cookie_attr(parts, "Path", path)
  append_cookie_attr(parts, "Domain", domain)
  if opts.max_age ~= nil then parts[#parts + 1] = "Max-Age=" .. tostring(math.floor(tonumber(opts.max_age) or 0)) end
  append_cookie_attr(parts, "Expires", expires)
  if secure then parts[#parts + 1] = "Secure" end
  if http_only then parts[#parts + 1] = "HttpOnly" end
  parts[#parts + 1] = "SameSite=" .. same_site
  return table.concat(parts, "; ")
end

function Context:cookie(name)
  return cookie_value(self:header("cookie") or self:header("Cookie"), name)
end

function Context:set(key, value)
  self.state[key] = value
  return value
end

function Context:get(key)
  return self.state[key]
end

function Context:cache(name)
  name = name or "default"
  local cache = self.worker_cache[name]
  if not cache then
    cache = {}
    self.worker_cache[name] = cache
  end
  return cache
end

---@class MeteoriteHttpResponse
---@field status integer
---@field headers table<string, string>
---@field body any

---@class MeteoriteHttpClient
---@field get fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field post fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field put fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
---@field delete fun(self: MeteoriteHttpClient, path: string, opts?: table): MeteoriteHttpResponse
local HttpClient = {}
HttpClient.__index = HttpClient

local http_client = require("cli.http_client")

local function http_request(method, base_url, path, opts)
  return http_client.request(method, base_url, path, opts)
end

function HttpClient:get(path, opts)
  return http_request("GET", self.base_url, path, opts)
end

function HttpClient:post(path, opts)
  return http_request("POST", self.base_url, path, opts)
end

function HttpClient:put(path, opts)
  return http_request("PUT", self.base_url, path, opts)
end

function HttpClient:patch(path, opts)
  return http_request("PATCH", self.base_url, path, opts)
end

function HttpClient:delete(path, opts)
  return http_request("DELETE", self.base_url, path, opts)
end

function Context:http(name)
  local capability = assert(self.capabilities.http and self.capabilities.http[name], "undeclared http capability: " .. tostring(name))
  local base_url = capability.base_url
  assert(type(base_url) == "string", "http capability missing base_url")
  return setmetatable({ base_url = base_url, requests = self.http_requests }, HttpClient)
end

local Auth = {}
Auth.__index = Auth

function Auth:refresh()
  self.refreshing = true
  self.refresh_count = (self.refresh_count or 0) + 1
  local audience = self.spec.audience or self.name
  self.token = "demo-token-for-" .. tostring(audience)
  self.expires_at = os.time() + 3600
  self.last_error = nil
  self.refreshing = false
  return self.token
end

function Auth:bearer()
  local now = os.time()
  local refresh_before = self.spec.refresh_before_seconds or 30
  if not self.token or (self.expires_at or 0) - refresh_before <= now then
    if self.refreshing then
      return self.token or ""
    end
    self:refresh()
  end
  return "Bearer " .. self.token
end

function Auth:authorization()
  return self:bearer()
end

function Auth:headers()
  return { authorization = self:authorization() }
end

function Context:auth(name)
  local spec = assert(self.capabilities.auth and self.capabilities.auth[name], "undeclared auth capability: " .. tostring(name))
  local key = "auth." .. tostring(name)
  local auth = self.capability_store[key]
  if not auth then
    auth = setmetatable({ name = name, spec = spec, token = nil, expires_at = 0, refreshing = false, refresh_count = 0 }, Auth)
    self.capability_store[key] = auth
  end
  return auth
end

local default_zig = {
  data_cruncher = {
    device_name = function(device_id) return "device:" .. tostring(device_id) end,
  },
}

function Context:zig(name)
  assert(self.capabilities.zig and self.capabilities.zig[name], "undeclared zig capability: " .. tostring(name))
  return (self.zig_helpers and self.zig_helpers[name]) or default_zig[name] or error("missing zig helper: " .. tostring(name))
end

function Context:scope(name)
  return self.scope[name]
end

local function new_context(opts)
  local params = opts.params or {}
  return setmetatable({
    request = opts.request,
    params = params,
    query = opts.query or {},
    state = {},
    scope = opts.scope or {},
    worker_cache = opts.worker_cache or {},
    capability_store = opts.capability_store or {},
    capabilities = opts.capabilities or {},
    zig_helpers = opts.zig_helpers,
    http_requests = {},
  }, Context)
end

local function build_plugin_map(plugins)
  local map = {}
  for _, plugin in ipairs(plugins or {}) do map[plugin.id] = plugin end
  return map
end

local function execute_scope_plugins(route, ctx, plugin_map)
  for _, plugin_ref in ipairs(route.scope.plugins or {}) do
    local plugin = type(plugin_ref) == "table" and plugin_ref.__meteorite_plugin and plugin_ref or plugin_map[plugin_ref]
    if plugin and type(plugin.execute) == "function" then
      local result = plugin.execute(ctx)
      if result then
        if type(result) == "string" then
          return { status = 200, content_type = "text/plain", body = result, http_requests = ctx.http_requests, state = ctx.state }
        end
        return {
          status = result.status or 200,
          content_type = result.content_type or "text/plain",
          body = result.body or "",
          http_requests = ctx.http_requests,
          state = ctx.state,
        }
      end
    end
  end
  return nil
end

function hybrid.invoke(app, request, opts)
  opts = opts or {}
  local store = opts.store or app_store(app)
  local graph = app:normalize({ mode = opts.mode or "dev" })
  local plugin_map = build_plugin_map(graph.plugins)
  local method = request.method or "GET"
  local path, raw_query = split_target(request.path or "/")
  local query_values = parse_query(raw_query)
  local path_matched = false
  for _, route in ipairs(graph.routes) do
    local params = match_route(route, method, path)
    if params then
      local query, query_error = match_query(route, query_values)
      if query_error then return query_error end
      local validation_error = validate_request_domains(route, request)
      if validation_error then return validation_error end
      local ctx = new_context({ request = request, params = params, query = query, scope = route.scope.context or {}, capabilities = graph.capabilities, zig_helpers = opts.zig_helpers, worker_cache = app.cache, capability_store = store.capabilities })
      local plugin_response = execute_scope_plugins(route, ctx, plugin_map)
      if plugin_response then return plugin_response end
      if route.handler.kind == "inline_lua" then
        local response = route.handler.value(ctx) or ctx.response or ctx:text(204, "")
        response.http_requests = ctx.http_requests
        response.state = ctx.state
        return response
      elseif route.handler.kind == "lua" then
        local handler = require(route.handler.module)
        local response = handler(ctx) or ctx.response or ctx:text(204, "")
        response.http_requests = ctx.http_requests
        response.state = ctx.state
        return response
      end
      return { status = 501, content_type = "text/plain", body = "handler requires Zig runtime" }
    end
    if match_route(route, route.method, path) then path_matched = true end
  end
  if path_matched then return { status = 405, content_type = "text/plain", body = "method not allowed" } end
  return { status = 404, content_type = "text/plain", body = "not found" }
end

return hybrid
