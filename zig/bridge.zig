const std = @import("std");
const graph = @import("meteorite_graph");
const c_imports = @import("bridge/c_imports.zig");
const c = c_imports.c;
const lua_stats = @import("bridge/lua_stats.zig");
const lua_vtable = @import("bridge/lua_vtable.zig");
const lua_json = @import("bridge/lua_json.zig");
const lua_http = @import("bridge/lua_http.zig");
const lua_bench_stats = @import("bridge/lua_bench_stats");

// --- Lua ABI Compatibility Shim ---
const LuaAbi = enum {
    lua_5_4,
    lua_5_1,
    unknown,
};

const lua_abi: LuaAbi = if (@hasDecl(c, "lua_pcallk")) .lua_5_4 else if (@hasDecl(c, "lua_pcall")) .lua_5_1 else .unknown;

const LUA_OK = if (lua_abi == .lua_5_4) c.LUA_OK else 0;

inline fn pcall(L: *c.lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) c_int {
    switch (comptime lua_abi) {
        .lua_5_4 => return c.lua_pcallk(L, nargs, nresults, errfunc, 0, null),
        .lua_5_1 => return c.lua_pcall(L, nargs, nresults, errfunc),
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
}

inline fn loadfile(L: *c.lua_State, filename: [*c]const u8) c_int {
    switch (comptime lua_abi) {
        .lua_5_4 => return c.luaL_loadfilex(L, filename, null),
        .lua_5_1 => return c.luaL_loadfile(L, filename),
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
}

inline fn getStatusInt(L: *c.lua_State, idx: c_int, default: u16) u16 {
    switch (comptime lua_abi) {
        .lua_5_4 => {
            if (c.lua_isinteger(L, idx) != 0) {
                return @intCast(c.lua_tointegerx(L, idx, null));
            }
        },
        .lua_5_1 => {
            if (c.lua_isnumber(L, idx) != 0) {
                return @intCast(c.lua_tointeger(L, idx));
            }
        },
        else => @compileError("Undefined ABI layout: " ++ @tagName(lua_abi)),
    }
    return default;
}
// -------------------------------------------

pub const LuaRuntimeUnavailable = struct {
    pub const lua_state_strategy = "none";
    pub const lua_handler_ref_strategy = "none";
    pub const capability_store_strategy = "none";
    pub const require_cache_strategy = "none";

    pub const Stats = LuaStats;

    pub fn snapshotStats() Stats {
        return .{};
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        _ = handler;
        try ctx.text(501, "handler requires Lua runtime");
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        _ = handler;
        _ = ctx;
        return false;
    }

    pub fn reloadAll() !void {}
};

pub const LuaStats = lua_stats.Stats;
const incLua = lua_stats.inc;
const snapshotLuaStats = lua_stats.snapshot;
const AtomicCounter = std.atomic.Value(u64);

pub const HttpClient = lua_http.HttpClient;
const encodeLuaValue = lua_json.encodeLuaValue;
const encodeJsonString = lua_json.encodeJsonString;
const HttpResponse = lua_http.HttpResponse;

pub const HybridContract = struct {
    pub const RequestLocalState = struct {
        allocator: std.mem.Allocator,
    };
};

const VTable = lua_vtable.VTable;
const meteorite_protocol = @import("meteorite_protocol");
const Header = meteorite_protocol.Header;
const makeVTable = lua_vtable.makeVTable;
const globalVtable = lua_vtable.globalVtable;

const lua_bindings = @import("bridge/lua_bindings.zig");

// Re-export bindings for runtime types to use
const upvalueIndex = lua_bindings.upvalueIndex;
const setupLuaPackagePaths = lua_bindings.setupLuaPackagePaths;
const l_text = lua_bindings.l_text;
const l_json = lua_bindings.l_json;
const l_bytes = lua_bindings.l_bytes;
const l_body = lua_bindings.l_body;
const l_param = lua_bindings.l_param;
const l_query = lua_bindings.l_query;
const l_header = lua_bindings.l_header;
const l_request_id = lua_bindings.l_request_id;
const l_cookie = lua_bindings.l_cookie;
const l_set_cookie = lua_bindings.l_set_cookie;
const l_http = lua_bindings.l_http;
const l_http_request = lua_bindings.l_http_request;
const l_auth = lua_bindings.l_auth;
const l_auth_headers = lua_bindings.l_auth_headers;
const l_auth_authorization = lua_bindings.l_auth_authorization;
const l_zig = lua_bindings.l_zig;
const l_zig_device_name = lua_bindings.l_zig_device_name;
const l_get = lua_bindings.l_get;
const l_set = lua_bindings.l_set;
const l_debug = lua_bindings.l_debug;
const l_shared_counter = lua_bindings.l_shared_counter;
const l_worker_counter = lua_bindings.l_worker_counter;
const setClosure = lua_bindings.setClosure;
const pushResponse = lua_bindings.pushResponse;
const pushMethod = lua_bindings.pushMethod;
const getCapabilityString = lua_bindings.getCapabilityString;
const getCapabilityInt = lua_bindings.getCapabilityInt;
const lookupString = lua_bindings.lookupString;
const lookupInt = lua_bindings.lookupInt;
const lookupZig = lua_bindings.lookupZig;
const installGlobalResponseHelpers = lua_bindings.installGlobalResponseHelpers;

const json_body_helper =
    \\return function(ctx)
    \\  local ok, cjson = pcall(require, "cjson")
    \\  if not ok then return nil, "json body parser unavailable" end
    \\  local decoded_ok, value = pcall(cjson.decode, ctx:body())
    \\  if not decoded_ok then return nil, "invalid json body" end
    \\  return value, nil
    \\end
;

const form_body_helper =
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

const secure_headers_helper =
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

const cors_headers_helper =
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

const server_timing_helper =
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

const constant_time_equal_helper =
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

const basic_auth_helper =
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

const bearer_token_helper =
    \\return function(ctx)
    \\  local authorization = ctx:header("authorization") or ctx:header("Authorization")
    \\  if type(authorization) ~= "string" then return nil end
    \\  local token = authorization:match("^[Bb][Ee][Aa][Rr][Ee][Rr]%s+([^%s,]+)%s*$")
    \\  if type(token) ~= "string" or #token > 8192 or token:find("[%z\r\n]") then return nil end
    \\  return token
    \\end
;

const safe_header_helper =
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

const log_helper =
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

fn pushJsonBodyMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, json_body_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "json_body") else c.lua_pop(L, 1);
}

fn pushFormBodyMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, form_body_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "form_body") else c.lua_pop(L, 1);
}

fn pushSecureHeadersMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, secure_headers_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "secure_headers") else c.lua_pop(L, 1);
}

fn pushCorsHeadersMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, cors_headers_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "cors_headers") else c.lua_pop(L, 1);
}

fn pushServerTimingMethods(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, server_timing_helper.ptr);
    if (pcall(L, 0, 1, 0) != LUA_OK) {
        c.lua_pop(L, 1);
        return;
    }
    _ = c.lua_getfield(L, -1, "headers");
    c.lua_setfield(L, -3, "server_timing");
    _ = c.lua_getfield(L, -1, "stage");
    c.lua_setfield(L, -3, "timing_stage");
    c.lua_pop(L, 1);
}

fn pushConstantTimeEqualMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, constant_time_equal_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "constant_time_equal") else c.lua_pop(L, 1);
}

fn pushBasicAuthMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, basic_auth_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "basic_auth") else c.lua_pop(L, 1);
}

fn pushBearerTokenMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, bearer_token_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "bearer_token") else c.lua_pop(L, 1);
}

fn pushSafeHeaderMethods(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, safe_header_helper.ptr);
    if (pcall(L, 0, 1, 0) != LUA_OK) {
        c.lua_pop(L, 1);
        return;
    }
    _ = c.lua_getfield(L, -1, "one");
    c.lua_setfield(L, -3, "safe_header");
    _ = c.lua_getfield(L, -1, "many");
    c.lua_setfield(L, -3, "safe_headers");
    c.lua_pop(L, 1);
}

fn pushLogMethod(L: *c.lua_State) void {
    _ = c.luaL_loadstring(L, log_helper.ptr);
    if (pcall(L, 0, 1, 0) == LUA_OK) c.lua_setfield(L, -2, "log") else c.lua_pop(L, 1);
}

fn pushCoreContextMethods(L: *c.lua_State) void {
    pushMethod(L, "text", l_text);
    pushMethod(L, "json", l_json);
    pushMethod(L, "bytes", l_bytes);
    pushMethod(L, "body", l_body);
    pushJsonBodyMethod(L);
    pushFormBodyMethod(L);
    pushSecureHeadersMethod(L);
    pushCorsHeadersMethod(L);
    pushServerTimingMethods(L);
    pushConstantTimeEqualMethod(L);
    pushBasicAuthMethod(L);
    pushBearerTokenMethod(L);
    pushSafeHeaderMethods(L);
    pushLogMethod(L);
    pushMethod(L, "param", l_param);
    pushMethod(L, "query", l_query);
    pushMethod(L, "header", l_header);
    pushMethod(L, "request_id", l_request_id);
    pushMethod(L, "cookie", l_cookie);
    pushMethod(L, "set_cookie", l_set_cookie);
    pushMethod(L, "http", l_http);
    pushMethod(L, "auth", l_auth);
    pushMethod(L, "zig", l_zig);
    pushMethod(L, "get", l_get);
    pushMethod(L, "set", l_set);
    pushMethod(L, "debug", l_debug);
    pushMethod(L, "shared_counter", l_shared_counter);
    pushMethod(L, "worker_counter", l_worker_counter);
}

fn pushFullRequestTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    c.lua_newtable(L);
    pushCoreContextMethods(L);

    if (@hasField(@TypeOf(ctx.*), "captures")) {
        c.lua_newtable(L);
        const captures = ctx.captures;
        for (captures.items[0..captures.len]) |item| {
            _ = c.lua_pushlstring(L, @ptrCast(item.value.ptr), item.value.len);
            c.lua_setfield(L, -2, @ptrCast(item.name.ptr));
        }
        c.lua_setfield(L, -2, "params");
    }

    if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query")) {
        c.lua_newtable(L);
        const query_specs = ctx.route.query;
        for (query_specs) |spec| {
            if (vtable.query(ctx, spec.name)) |value| {
                _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                c.lua_setfield(L, -2, @ptrCast(spec.name.ptr));
            }
        }
        c.lua_setfield(L, -2, "query");
    }

    c.lua_newtable(L);
    c.lua_setfield(L, -2, "state");

    if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
        c.lua_newtable(L);
        for (ctx.route.scope.context) |ref| {
            _ = c.lua_pushlstring(L, @ptrCast(ref.value.ptr), ref.value.len);
            c.lua_setfield(L, -2, @ptrCast(ref.key.ptr));
        }
        c.lua_setfield(L, -2, "scope");
    }

    return 1;
}

fn pushLazyContextTable(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    _ = handler;
    _ = ctx;
    _ = vtable;
    c.lua_newtable(L);
    pushCoreContextMethods(L);
    c.lua_newtable(L);
    c.lua_setfield(L, -2, "state");
    return 1;
}

fn pushDirectParamArgs(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    var pushed: c_int = 0;
    var index: usize = 0;
    while (index < handler.nparams) : (index += 1) {
        if (vtable.param_at(ctx, index)) |value| {
            _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
        } else {
            c.lua_pushnil(L);
        }
        pushed += 1;
    }
    return pushed;
}

fn pushHandlerArgs(comptime handler: anytype, L: *c.lua_State, ctx: anytype, vtable: *const VTable) c_int {
    return switch (handler.arg_mode) {
        .no_args => 0,
        .direct_params => pushDirectParamArgs(handler, L, ctx, vtable),
        .lazy_context => pushLazyContextTable(handler, L, ctx, vtable),
        .request_table => pushFullRequestTable(handler, L, ctx, vtable),
    };
}

const ResponseHeaders = struct {
    items: [16]Header = undefined,
    len: usize = 0,

    fn append(self: *ResponseHeaders, name: []const u8, value: []const u8) !void {
        if (self.len >= self.items.len) return error.TooManyResponseHeaders;
        self.items[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }

    fn slice(self: *const ResponseHeaders) []const Header {
        return self.items[0..self.len];
    }
};

fn absoluteIndex(L: *c.lua_State, index: c_int) c_int {
    return if (index < 0) c.lua_gettop(L) + index + 1 else index;
}

fn parseResponseHeaders(L: *c.lua_State, response_index: c_int) !ResponseHeaders {
    const table_index = absoluteIndex(L, response_index);
    var headers: ResponseHeaders = .{};
    _ = c.lua_getfield(L, table_index, "headers");
    defer c.lua_pop(L, 1);
    if (c.lua_isnil(L, -1)) return headers;
    if (!c.lua_istable(L, -1)) return error.InvalidResponseHeaders;

    const headers_index = absoluteIndex(L, -1);
    c.lua_pushnil(L);
    while (c.lua_next(L, headers_index) != 0) {
        defer c.lua_pop(L, 1);
        if (c.lua_type(L, -2) != c.LUA_TSTRING or c.lua_isstring(L, -1) == 0) return error.InvalidResponseHeaders;
        var name_len: usize = 0;
        const name_ptr = c.lua_tolstring(L, -2, &name_len);
        var value_len: usize = 0;
        const value_ptr = c.lua_tolstring(L, -1, &value_len);
        const name = name_ptr[0..name_len];
        const value = value_ptr[0..value_len];
        try meteorite_protocol.validateResponseHeader(name, value);
        try headers.append(name, value);
    }
    return headers;
}

fn respondLuaTable(L: *c.lua_State, table_index: c_int, ctx: *anyopaque, vtable: *const VTable) !void {
    const response_index = absoluteIndex(L, table_index);
    _ = c.lua_getfield(L, response_index, "status");
    const status: u16 = getStatusInt(L, -1, 200);
    c.lua_pop(L, 1);

    const headers = try parseResponseHeaders(L, response_index);

    _ = c.lua_getfield(L, response_index, "content_type");
    _ = c.lua_getfield(L, response_index, "body");
    defer c.lua_pop(L, 2);
    var content_type_len: usize = 0;
    const content_type_ptr = c.lua_tolstring(L, -2, &content_type_len);
    var body_len: usize = 0;
    const body_ptr = c.lua_tolstring(L, -1, &body_len);
    const body = body_ptr[0..body_len];

    if (content_type_ptr != null) {
        const content_type = content_type_ptr[0..content_type_len];
        return vtable.bytes_with_headers(ctx, status, content_type, body, headers.slice());
    }
    return vtable.bytes_with_headers(ctx, status, "text/plain; charset=utf-8", body, headers.slice());
}

fn finishLuaResponse(L: *c.lua_State, ctx: *anyopaque, vtable: *const VTable) !bool {
    if (c.lua_istable(L, -1)) {
        try respondLuaTable(L, -1, ctx, vtable);
        c.lua_pop(L, 1);
        return true;
    }
    if (c.lua_isstring(L, -1) != 0) {
        var len: usize = 0;
        const ptr = c.lua_tolstring(L, -1, &len);
        try vtable.text(ctx, 200, ptr[0..len]);
        c.lua_pop(L, 1);
        return true;
    }
    return false;
}
pub const HybridLuaRuntime = struct {
    pub const lua_state_strategy = "per_request_state";
    pub const lua_handler_ref_strategy = "load_per_request";
    pub const capability_store_strategy = "process_shared_zig_debug_store";
    pub const require_cache_strategy = "per_request_lua_package_loaded";

    pub fn snapshotStats() LuaStats {
        return snapshotLuaStats();
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        incLua(&lua_stats.stats.lua_state_reuse_misses);
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaOutOfMemory;
        };
        incLua(&lua_stats.stats.lua_states_created);
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        try setupLuaPackagePaths(L);
        installGlobalResponseHelpers(L);

        if (loadfile(L, @ptrCast(handler.path.ptr)) != LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("load handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (pcall(L, 0, 1, 0) != LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("init handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("handler {s} did not return a function", .{handler.path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }

        const nargs = pushHandlerArgs(handler, L, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (@hasField(@TypeOf(handler), "bench_route")) lua_bench_stats.incLuaPcallByPath(handler.bench_route);
        if (pcall(L, nargs, 1, 0) != LUA_OK) {
            const err = c.lua_tolstring(L, -1, null);
            std.log.err("handler {s}: {s}", .{ handler.path, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L, 1);
            return;
        }

        if (!try finishLuaResponse(L, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        const vtable = globalVtable(@TypeOf(ctx.*));
        const L = c.luaL_newstate() orelse {
            std.log.err("failed to create Lua state for plugin", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        };
        defer c.lua_close(L);
        c.luaL_openlibs(L);

        setupLuaPackagePaths(L) catch return error.LuaRuntimeError;
        installGlobalResponseHelpers(L);

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (loadfile(L, @ptrCast(plugin_path.ptr)) != LUA_OK) {
            std.log.err("load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (pcall(L, 0, 1, 0) != LUA_OK) {
            std.log.err("init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L, -1)) {
            std.log.err("plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }

        c.lua_newtable(L);
        pushMethod(L, "text", l_text);
        pushMethod(L, "json", l_json);
        pushMethod(L, "bytes", l_bytes);
        pushMethod(L, "body", l_body);
        pushJsonBodyMethod(L);
        pushFormBodyMethod(L);
        pushSecureHeadersMethod(L);
        pushCorsHeadersMethod(L);
        pushServerTimingMethods(L);
        pushConstantTimeEqualMethod(L);
        pushBasicAuthMethod(L);
        pushBearerTokenMethod(L);
        pushSafeHeaderMethods(L);
        pushLogMethod(L);
        pushMethod(L, "param", l_param);
        pushMethod(L, "query", l_query);
        pushMethod(L, "header", l_header);
        pushMethod(L, "request_id", l_request_id);
        pushMethod(L, "cookie", l_cookie);
        pushMethod(L, "set_cookie", l_set_cookie);
        pushMethod(L, "http", l_http);
        pushMethod(L, "auth", l_auth);
        pushMethod(L, "zig", l_zig);
        pushMethod(L, "get", l_get);
        pushMethod(L, "set", l_set);
        pushMethod(L, "debug", l_debug);
        pushMethod(L, "shared_counter", l_shared_counter);
        pushMethod(L, "worker_counter", l_worker_counter);

        if (@hasField(@TypeOf(ctx.*), "captures")) {
            c.lua_newtable(L);
            const captures = ctx.captures;
            for (captures.items[0..captures.len]) |item| {
                _ = c.lua_pushlstring(L, @ptrCast(item.value.ptr), item.value.len);
                c.lua_setfield(L, -2, @ptrCast(item.name.ptr));
            }
            c.lua_setfield(L, -2, "params");
        }

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query")) {
            c.lua_newtable(L);
            const query_specs = ctx.route.query;
            for (query_specs) |spec| {
                if (vtable.query(ctx, spec.name)) |value| {
                    _ = c.lua_pushlstring(L, @ptrCast(value.ptr), value.len);
                    c.lua_setfield(L, -2, @ptrCast(spec.name.ptr));
                }
            }
            c.lua_setfield(L, -2, "query");
        }

        c.lua_newtable(L);
        c.lua_setfield(L, -2, "state");

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
            c.lua_newtable(L);
            for (ctx.route.scope.context) |ref| {
                _ = c.lua_pushlstring(L, @ptrCast(ref.value.ptr), ref.value.len);
                c.lua_setfield(L, -2, @ptrCast(ref.key.ptr));
            }
            c.lua_setfield(L, -2, "scope");
        }

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (pcall(L, 1, 1, 0) != LUA_OK) {
            std.log.err("plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L, 1);
            return true;
        }

        if (try finishLuaResponse(L, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) return true;
        c.lua_pop(L, 1);
        return false;
    }
};

const graph_cached = graph;

fn inlineLuaRouteCount() usize {
    comptime var count: usize = 0;
    inline for (graph_cached.routes) |route| {
        if (route.handler == .inline_lua) count += 1;
    }
    return count;
}

fn routeIndexCached(comptime route_id: []const u8) usize {
    comptime var count: usize = 0;
    inline for (graph_cached.routes) |route| {
        if (route.handler == .inline_lua) {
            if (std.mem.eql(u8, route.id, route_id)) {
                return count;
            }
            count += 1;
        }
    }
    @compileError("unknown inline Lua route: " ++ route_id);
}

pub const CachedHybridRuntime = struct {
    pub const lua_state_strategy = "per_thread_cached_refs";
    pub const lua_handler_ref_strategy = "per_thread_registry_refs";
    pub const capability_store_strategy = "process_shared_zig_debug_store";
    pub const require_cache_strategy = "per_thread_package_loaded";

    pub fn snapshotStats() LuaStats {
        return snapshotLuaStats();
    }

    threadlocal var L: ?*c.lua_State = null;
    threadlocal var refs: [inlineLuaRouteCount()]c_int = undefined;
    threadlocal var initialized: bool = false;
    threadlocal var loaded_reload_epoch: u64 = 0;
    var reload_epoch = AtomicCounter.init(0);

    fn init() !void {
        if (initialized) {
            incLua(&lua_stats.stats.lua_state_reuse_hits);
            return;
        }
        incLua(&lua_stats.stats.lua_state_reuse_misses);
        L = c.luaL_newstate() orelse {
            std.log.err("failed to create cached Lua state", .{});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaOutOfMemory;
        };
        incLua(&lua_stats.stats.lua_states_created);
        c.luaL_openlibs(L.?);

        try setupLuaPackagePaths(L);
        installGlobalResponseHelpers(L);

        comptime var idx: usize = 0;
        inline for (graph_cached.routes) |route| {
            if (route.handler == .inline_lua) {
                const handler = route.handler.inline_lua;
                try loadHandlerRef(idx, handler, false);
                idx += 1;
            }
        }
        loaded_reload_epoch = reload_epoch.load(.acquire);
        initialized = true;
    }

    fn reloadRefs() !void {
        comptime var idx: usize = 0;
        inline for (graph_cached.routes) |route| {
            if (route.handler == .inline_lua) {
                try loadHandlerRef(idx, route.handler.inline_lua, true);
                idx += 1;
            }
        }
    }

    fn refreshIfStale() !void {
        const current_epoch = reload_epoch.load(.acquire);
        if (loaded_reload_epoch == current_epoch) return;
        try reloadRefs();
        loaded_reload_epoch = current_epoch;
    }

    fn loadHandlerRef(comptime idx: usize, comptime handler: graph_cached.InlineLuaHandler, comptime replace: bool) !void {
        if (replace) c.luaL_unref(L.?, c.LUA_REGISTRYINDEX, refs[idx]);
        if (loadfile(L.?, @ptrCast(handler.chunk_path.ptr)) != LUA_OK) {
            std.log.err("cached load handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaLoadFailed;
        }
        if (pcall(L.?, 0, 1, 0) != LUA_OK) {
            std.log.err("cached init handler {s}: {s}", .{ handler.chunk_path, c.lua_tolstring(L.?, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L.?, -1)) {
            std.log.err("cached handler {s} did not return a function", .{handler.chunk_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }
        refs[idx] = c.luaL_ref(L.?, c.LUA_REGISTRYINDEX);
        incLua(&lua_stats.stats.lua_handler_refs_loaded);
    }

    pub fn reloadAll() !void {
        try init();
        try reloadRefs();
        loaded_reload_epoch = reload_epoch.fetchAdd(1, .acq_rel) + 1;
    }

    pub fn call(comptime handler: anytype, ctx: anytype) !void {
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        try refreshIfStale();
        const L2 = L.?;

        const idx = comptime routeIndexCached(handler.id);
        _ = c.lua_rawgeti(L2, c.LUA_REGISTRYINDEX, refs[idx]);

        const nargs = pushHandlerArgs(handler, L2, ctx, vtable);

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer lua_vtable.resetCurrent();

        if (@hasField(@TypeOf(handler), "bench_route")) lua_bench_stats.incLuaPcallByPath(handler.bench_route);
        if (pcall(L2, nargs, 1, 0) != LUA_OK) {
            const err = c.lua_tolstring(L2, -1, null);
            std.log.err("cached handler {s}: {s}", .{ handler.id, err });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L2, 1);
            return;
        }

        if (!try finishLuaResponse(L2, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) {
            try lua_vtable.current_vtable.?.text(lua_vtable.current_ctx.?, 204, "");
            c.lua_pop(L2, 1);
        }
    }

    pub fn callPlugin(comptime handler: anytype, ctx: anytype) !bool {
        const vtable = globalVtable(@TypeOf(ctx.*));
        try init();
        const L2 = L.?;

        const plugin_path = if (@hasField(@TypeOf(handler), "chunk_path")) handler.chunk_path else handler.path;
        if (loadfile(L2, @ptrCast(plugin_path.ptr)) != LUA_OK) {
            std.log.err("cached load plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (pcall(L2, 0, 1, 0) != LUA_OK) {
            std.log.err("cached init plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }
        if (!c.lua_isfunction(L2, -1)) {
            std.log.err("cached plugin {s} did not return a function", .{plugin_path});
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaHandlerInvalid;
        }

        c.lua_newtable(L2);
        pushMethod(L2, "text", l_text);
        pushMethod(L2, "json", l_json);
        pushMethod(L2, "bytes", l_bytes);
        pushMethod(L2, "body", l_body);
        pushJsonBodyMethod(L2);
        pushFormBodyMethod(L2);
        pushSecureHeadersMethod(L2);
        pushCorsHeadersMethod(L2);
        pushServerTimingMethods(L2);
        pushConstantTimeEqualMethod(L2);
        pushBasicAuthMethod(L2);
        pushBearerTokenMethod(L2);
        pushSafeHeaderMethods(L2);
        pushLogMethod(L2);
        pushMethod(L2, "param", l_param);
        pushMethod(L2, "query", l_query);
        pushMethod(L2, "header", l_header);
        pushMethod(L2, "request_id", l_request_id);
        pushMethod(L2, "cookie", l_cookie);
        pushMethod(L2, "set_cookie", l_set_cookie);
        pushMethod(L2, "http", l_http);
        pushMethod(L2, "auth", l_auth);
        pushMethod(L2, "zig", l_zig);
        pushMethod(L2, "get", l_get);
        pushMethod(L2, "set", l_set);
        pushMethod(L2, "debug", l_debug);
        pushMethod(L2, "shared_counter", l_shared_counter);
        pushMethod(L2, "worker_counter", l_worker_counter);

        if (@hasField(@TypeOf(ctx.*), "captures")) {
            c.lua_newtable(L2);
            const captures = ctx.captures;
            for (captures.items[0..captures.len]) |item| {
                _ = c.lua_pushlstring(L2, @ptrCast(item.value.ptr), item.value.len);
                c.lua_setfield(L2, -2, @ptrCast(item.name.ptr));
            }
            c.lua_setfield(L2, -2, "params");
        }

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "query")) {
            c.lua_newtable(L2);
            const query_specs = ctx.route.query;
            for (query_specs) |spec| {
                if (vtable.query(ctx, spec.name)) |value| {
                    _ = c.lua_pushlstring(L2, @ptrCast(value.ptr), value.len);
                    c.lua_setfield(L2, -2, @ptrCast(spec.name.ptr));
                }
            }
            c.lua_setfield(L2, -2, "query");
        }

        c.lua_newtable(L2);
        c.lua_setfield(L2, -2, "state");

        if (@hasField(@TypeOf(ctx.*), "route") and @hasField(@TypeOf(ctx.route), "scope")) {
            c.lua_newtable(L2);
            for (ctx.route.scope.context) |ref| {
                _ = c.lua_pushlstring(L2, @ptrCast(ref.value.ptr), ref.value.len);
                c.lua_setfield(L2, -2, @ptrCast(ref.key.ptr));
            }
            c.lua_setfield(L2, -2, "scope");
        }

        lua_vtable.current_ctx = ctx;
        lua_vtable.current_vtable = vtable;
        lua_vtable.current_responded = false;
        defer {
            lua_vtable.resetCurrent();
        }

        if (pcall(L2, 1, 1, 0) != LUA_OK) {
            std.log.err("cached plugin {s}: {s}", .{ plugin_path, c.lua_tolstring(L2, -1, null) });
            incLua(&lua_stats.stats.lua_errors);
            return error.LuaRuntimeError;
        }

        if (lua_vtable.current_responded) {
            c.lua_pop(L2, 1);
            return true;
        }

        if (try finishLuaResponse(L2, lua_vtable.current_ctx.?, lua_vtable.current_vtable.?)) return true;
        c.lua_pop(L2, 1);
        return false;
    }
};
