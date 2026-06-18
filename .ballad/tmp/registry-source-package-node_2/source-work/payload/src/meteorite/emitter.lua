local zon = require("meteorite.zon")
local lifter = require("meteorite.lifter")

local emitter = {}

local function mkdir_p(path)
  os.execute("mkdir -p " .. string.format("%q", path))
end

local function write_file(path, content)
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
end

local function capture(command)
  local pipe = io.popen(command, "r")
  if not pipe then return "" end
  local out = pipe:read("*a") or ""
  pipe:close()
  return (out:gsub("%s+$", ""))
end

local function hash_text(text)
  local tmp = os.tmpname()
  write_file(tmp, text)
  local hash = capture("b3sum --no-names " .. string.format("%q", tmp) .. " 2>/dev/null")
  os.remove(tmp)
  if hash ~= "" then return "b3:" .. hash end
  local h = 2166136261
  for i = 1, #text do h = (h + text:byte(i) * 16777619) % 4294967296 end
  return string.format("fnv32:%08x", h)
end

local function method_enum(method) return { __meteorite_enum = true, value = method } end
local function mode_enum(mode) return { __meteorite_enum = true, value = (mode:gsub("-", "_")) } end

local function zig_ident(value)
  local out = tostring(value):gsub("%W", "_")
  if out:match("^%d") then out = "_" .. out end
  return out
end

local function zig_string(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local function dirname(path)
  return tostring(path):match("^(.*)/[^/]*$") or "."
end

local function path_join(a, b)
  if a == "" or a == "." then return b end
  return a .. "/" .. b
end

local function project_root_from_output(output)
  local marker = output:find("%.meteorite/", 1)
  if marker then
    local root = output:sub(1, marker - 2)
    return root ~= "" and root or "."
  end
  return "."
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function schema_to_zon(item)
  if item.kind == "pattern" then
    return { name = item.name, kind = "pattern", pattern_id = item.pattern_id or item.id }
  end
  local out = { name = item.name, type = { __meteorite_enum = true, value = item.type or "string" } }
  if item.max_len then out.max_len = item.max_len end
  if item.exact_len then out.exact_len = item.exact_len end
  if item.optional then out.optional = true end
  if item.decode then out.decode = true end
  if item.pattern_id then out.pattern_id = item.pattern_id end
  return out
end

local function route_to_zon(route)
  local segments = {}
  for _, segment in ipairs(route.path.segments) do
    if segment.kind == "literal" then
      segments[#segments + 1] = { literal = segment.value }
    else
      local param_schema = { name = segment.name, type = "string" }
      for _, item in ipairs(route.params) do if item.name == segment.name then param_schema = item end end
      segments[#segments + 1] = { param = schema_to_zon(param_schema) }
    end
  end
  local query = {}
  for _, item in ipairs(route.query) do query[#query + 1] = schema_to_zon(item) end
  local handler
  if route.handler.kind == "zig" then handler = { zig_symbol = { id = route.handler.symbol, symbol = route.handler.import or route.handler.symbol } }
  elseif route.handler.kind == "zig_file" then handler = { zig_file = { id = route.handler.symbol, path = route.handler.path, decl = route.handler.decl or "handle" } }
  elseif route.handler.kind == "lua" then handler = { lua_file = { id = route.id, path = route.handler.path or route.handler.module } }
  else handler = { inline_lua = route.handler.lifted or { id = route.id } } end
  local capabilities = {}
  for _, ref in ipairs(route.capabilities or {}) do capabilities[#capabilities + 1] = { [ref.kind] = ref.name } end
  local runtime = {
    requires_lua = route.runtime.requires_lua,
    requires_http = route.runtime.requires_http,
    requires_auth = route.runtime.requires_auth,
    requires_zig_capability = route.runtime.requires_zig_capability,
    execution_class = { __meteorite_enum = true, value = route.runtime.execution_class },
  }
  local execution = {
    class = { __meteorite_enum = true, value = route.execution.class },
    may_block = route.execution.may_block,
    requires_lua = route.execution.requires_lua,
    requires_worker_pool = route.execution.requires_worker_pool,
  }
  return {
    id = route.id,
    method = method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    query = query,
    handler = handler,
    runtime = runtime,
    execution = execution,
    memory = route.memory,
    capabilities = capabilities,
    source = route.source,
  }
end

local function capability_names(capabilities, kind)
  local out = {}
  for name, _ in pairs((capabilities or {})[kind] or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function emit_build_report(graph, output, mode)
  local inline, zig = 0, 0
  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "inline_lua" then inline = inline + 1 end
    if route.handler.kind == "zig" or route.handler.kind == "zig_file" then zig = zig + 1 end
  end
  local lines = {
    "Meteorite build",
    "  mode: " .. (mode == "release-static" and "static" or "hybrid"),
    "  backend: std.http",
    "  Lua runtime: " .. (mode == "release-static" and "removed" or "included"),
    "  Lua state: single_locked",
    "  workers: auto",
    "  inline Lua handlers: " .. tostring(inline),
    "  Zig handlers: " .. tostring(zig),
    "  HTTP capabilities: " .. (#capability_names(graph.capabilities, "http") > 0 and table.concat(capability_names(graph.capabilities, "http"), ", ") or "none"),
    "  Auth capabilities: " .. (#capability_names(graph.capabilities, "auth") > 0 and table.concat(capability_names(graph.capabilities, "auth"), ", ") or "none"),
    "  Zig capabilities: " .. (#capability_names(graph.capabilities, "zig") > 0 and table.concat(capability_names(graph.capabilities, "zig"), ", ") or "none"),
    "  patterns: " .. tostring(#graph.patterns),
    "  artifact: dist/server",
    "",
  }
  write_file(output .. "/build-report.txt", table.concat(lines, "\n"))
end

local function emit_luals_aids(graph, output)
  local aid_dir = output .. "/../../aids/lua"
  mkdir_p(aid_dir)
  local lines = {
    "---@class MeteoriteContext",
    "---@field params table",
    "---@field query table",
    "---@field state table",
    "local Context = {}",
    "",
    "---@param body string",
    "function Context:text(body) end",
    "",
    "---@param value table|string|number|boolean",
    "function Context:json(value) end",
    "",
    "---@return string",
    "function Context:body() end",
    "",
    "---@param name string",
    "function Context:http(name) end",
    "",
    "---@param name string",
    "function Context:auth(name) end",
    "",
    "---@param name string",
    "function Context:zig(name) end",
    "",
    "---@param key string",
    "function Context:get(key) end",
    "",
    "---@param key string",
    "---@param value any",
    "function Context:set(key, value) end",
    "",
  }
  for _, route in ipairs(graph.routes) do
    if #route.params > 0 then
      local class_name = "MeteoriteParams_" .. zig_ident(route.id)
      lines[#lines + 1] = "---@class " .. class_name
      for _, param in ipairs(route.params) do
        local lua_type = (param.type == "u64" or param.type == "i32") and "integer" or "string"
        lines[#lines + 1] = "---@field " .. param.name .. " " .. lua_type
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---@class MeteoriteContext_" .. zig_ident(route.id) .. " : MeteoriteContext"
      lines[#lines + 1] = "---@field params " .. class_name
      lines[#lines + 1] = ""
    end
    if #(route.query or {}) > 0 then
      local class_name = "MeteoriteQuery_" .. zig_ident(route.id)
      lines[#lines + 1] = "---@class " .. class_name
      for _, item in ipairs(route.query) do
        local lua_type = (item.type == "u64" or item.type == "i32") and "integer" or (item.type == "bool" and "boolean" or "string")
        if item.optional then lua_type = lua_type .. "|nil" end
        lines[#lines + 1] = "---@field " .. item.name .. " " .. lua_type
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---@class MeteoriteContext_" .. zig_ident(route.id) .. " : MeteoriteContext"
      lines[#lines + 1] = "---@field query " .. class_name
      lines[#lines + 1] = ""
    end
  end
  lines[#lines + 1] = "return Context"
  write_file(aid_dir .. "/meteorite.meta.lua", table.concat(lines, "\n") .. "\n")

  local route_lines = {
    "---@meta",
    "",
    "---@diagnostic disable: missing-return",
    "",
  }
  for _, route in ipairs(graph.routes) do
    local route_id = zig_ident(route.id)
    if #route.params > 0 then
      route_lines[#route_lines + 1] = "---@class MeteoriteParams_" .. route_id
      for _, param in ipairs(route.params) do
        local lua_type = (param.type == "u64" or param.type == "i32") and "integer" or "string"
        route_lines[#route_lines + 1] = "---@field " .. param.name .. " " .. lua_type
      end
      route_lines[#route_lines + 1] = ""
    end
    if #(route.query or {}) > 0 then
      route_lines[#route_lines + 1] = "---@class MeteoriteQuery_" .. route_id
      for _, item in ipairs(route.query) do
        local lua_type = (item.type == "u64" or item.type == "i32") and "integer" or (item.type == "bool" and "boolean" or "string")
        if item.optional then lua_type = lua_type .. "|nil" end
        route_lines[#route_lines + 1] = "---@field " .. item.name .. " " .. lua_type
      end
      route_lines[#route_lines + 1] = ""
    end
    route_lines[#route_lines + 1] = "---@class MeteoriteContext_" .. route_id .. " : MeteoriteContext"
    if #route.params > 0 then route_lines[#route_lines + 1] = "---@field params MeteoriteParams_" .. route_id end
    if #(route.query or {}) > 0 then route_lines[#route_lines + 1] = "---@field query MeteoriteQuery_" .. route_id end
    route_lines[#route_lines + 1] = ""
  end
  write_file(aid_dir .. "/routes.meta.lua", table.concat(route_lines, "\n") .. "\n")
end

local function zig_param_type(param)
  local kind = param.type or param.kind or "string"
  local base
  if kind == "u64" then return "u64" end
  if kind == "i32" then return "i32" end
  if kind == "bool" then return "bool" end
  base = "[]const u8"
  return base
end

local function zig_optional_type(param)
  local base = zig_param_type(param)
  if param.optional then return "?" .. base end
  return base
end

local function zig_value_conversion(param, accessor)
  local name = zig_ident(param.name)
  local raw_name = zig_string(param.name)
  local kind = param.type or param.kind or "string"
  local value = accessor .. "(" .. raw_name .. ")"
  if param.optional then
    if kind == "u64" then
      return "." .. name .. " = if (" .. value .. ") |v| try std.fmt.parseInt(u64, v, 10) else null"
    end
    if kind == "i32" then
      return "." .. name .. " = if (" .. value .. ") |v| try std.fmt.parseInt(i32, v, 10) else null"
    end
    if kind == "bool" then
      return "." .. name .. " = if (" .. value .. ") |v| parseBool(v) orelse return error.InvalidParam else null"
    end
    return "." .. name .. " = " .. value
  end
  if kind == "u64" then
    return "." .. name .. " = try std.fmt.parseInt(u64, " .. value .. " orelse return error.MissingParam, 10)"
  end
  if kind == "i32" then
    return "." .. name .. " = try std.fmt.parseInt(i32, " .. value .. " orelse return error.MissingParam, 10)"
  end
  if kind == "bool" then
    return "." .. name .. " = parseBool(" .. value .. " orelse return error.MissingParam) orelse return error.InvalidParam"
  end
  return "." .. name .. " = " .. value .. " orelse return error.MissingParam"
end

local function zig_param_conversion(param)
  return zig_value_conversion(param, "raw.param")
end

local function zig_query_conversion(param)
  return zig_value_conversion(param, "raw.query")
end

local function emit_ctx_zig(graph, output)
  local lines = {
    "const std = @import(\"std\");",
    "",
    "pub const Error = error{ MissingParam, InvalidParam } || std.fmt.ParseIntError;",
    "",
    "const VTable = struct {",
    "    method: *const fn (*anyopaque) []const u8,",
    "    path: *const fn (*anyopaque) []const u8,",
    "    param: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    query: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    header: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    body: *const fn (*anyopaque) anyerror![]const u8,",
    "    text: *const fn (*anyopaque, u16, []const u8) anyerror!void,",
    "    bytes: *const fn (*anyopaque, u16, []const u8, []const u8) anyerror!void,",
    "    json: *const fn (*anyopaque, u16, []const u8) anyerror!void,",
    "};",
    "",
    "fn VTableFor(comptime RawPtr: type) type {",
    "    return struct {",
    "        fn cast(ptr: *anyopaque) RawPtr { return @ptrCast(@alignCast(ptr)); }",
    "        fn method(ptr: *anyopaque) []const u8 { return @tagName(cast(ptr).method()); }",
    "        fn path(ptr: *anyopaque) []const u8 { return cast(ptr).path(); }",
    "        fn param(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).param(name); }",
    "        fn query(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).query(name); }",
    "        fn header(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).header(name); }",
    "        fn body(ptr: *anyopaque) anyerror![]const u8 { return cast(ptr).body(); }",
    "        fn text(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).text(status, response_body); }",
    "        fn bytes(ptr: *anyopaque, status: u16, content_type: []const u8, response_body: []const u8) anyerror!void { return cast(ptr).bytes(status, content_type, response_body); }",
    "        fn json(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).json(status, response_body); }",
    "        pub const value = VTable{ .method = method, .path = path, .param = param, .query = query, .header = header, .body = body, .text = text, .bytes = bytes, .json = json };",
    "    };",
    "}",
    "",
    "fn parseBool(value: []const u8) ?bool {",
    "    if (std.mem.eql(u8, value, \"true\") or std.mem.eql(u8, value, \"1\")) return true;",
    "    if (std.mem.eql(u8, value, \"false\") or std.mem.eql(u8, value, \"0\")) return false;",
    "    return null;",
    "}",
    "",
    "pub const ctx = struct {",
  }
  for _, route in ipairs(graph.routes) do
    local id = zig_ident(route.id)
    local params_name = "Params_" .. id
    local query_name = "Query_" .. id
    lines[#lines + 1] = "    pub const " .. params_name .. " = struct {"
    for _, param in ipairs(route.params) do
      lines[#lines + 1] = "            " .. zig_ident(param.name) .. ": " .. zig_param_type(param) .. ","
    end
    lines[#lines + 1] = "        };"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    pub const " .. query_name .. " = struct {"
    for _, query in ipairs(route.query or {}) do
      lines[#lines + 1] = "            " .. zig_ident(query.name) .. ": " .. zig_optional_type(query) .. ","
    end
    lines[#lines + 1] = "        };"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    pub const " .. id .. " = struct {"
    lines[#lines + 1] = "        pub const method_name = \"" .. route.method .. "\";"
    lines[#lines + 1] = "        pub const route_path = " .. zig_string(route.raw_path) .. ";"
    lines[#lines + 1] = "        params: " .. params_name .. ","
    lines[#lines + 1] = "        query: " .. query_name .. ","
    lines[#lines + 1] = "        raw: *anyopaque,"
    lines[#lines + 1] = "        vtable: *const VTable,"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "        pub fn from(raw: anytype) Error!" .. id .. " {"
    lines[#lines + 1] = "            return .{ .params = .{"
    for i, param in ipairs(route.params) do
      lines[#lines + 1] = "                " .. zig_param_conversion(param) .. (i < #route.params and "," or "")
    end
    lines[#lines + 1] = "            }, .query = .{"
    for i, query in ipairs(route.query or {}) do
      lines[#lines + 1] = "                " .. zig_query_conversion(query) .. (i < #(route.query or {}) and "," or "")
    end
    lines[#lines + 1] = "            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };"
    lines[#lines + 1] = "        }"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "        pub fn method(self: " .. id .. ") []const u8 { return self.vtable.method(self.raw); }"
    lines[#lines + 1] = "        pub fn path(self: " .. id .. ") []const u8 { return self.vtable.path(self.raw); }"
    lines[#lines + 1] = "        pub fn param(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }"
    lines[#lines + 1] = "        pub fn queryValue(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }"
    lines[#lines + 1] = "        pub fn header(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }"
    lines[#lines + 1] = "        pub fn body(self: " .. id .. ") ![]const u8 { return self.vtable.body(self.raw); }"
    lines[#lines + 1] = "        pub fn text(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }"
    lines[#lines + 1] = "        pub fn bytes(self: " .. id .. ", status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }"
    lines[#lines + 1] = "        pub fn json(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }"
    lines[#lines + 1] = "    };"
  end
  lines[#lines + 1] = "};"
  write_file(output .. "/ctx.zig", table.concat(lines, "\n") .. "\n")
end

local function zig_stub_body(route)
  local name = zig_ident(route.id)
  local lines = {
    "pub fn " .. name .. "(c: mt.ctx." .. name .. ") !void {",
    "    // <meteorite:generated-stub>",
    "    // This handler was generated by Meteorite.",
    "    // Replace the body before shipping release-static.",
  }
  for _, param in ipairs(route.params) do
    lines[#lines + 1] = "    _ = c.params." .. zig_ident(param.name) .. ";"
  end
  for _, query in ipairs(route.query or {}) do
    lines[#lines + 1] = "    _ = c.query." .. zig_ident(query.name) .. ";"
  end
  if #route.params == 0 and #(route.query or {}) == 0 then lines[#lines + 1] = "    _ = c;" end
  lines[#lines + 1] = "    return c.text(501, \"handler `" .. name .. "` is not implemented\");"
  lines[#lines + 1] = "    // </meteorite:generated-stub>"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

local function emit_zig_aids(graph, output)
  local aid_dir = output .. "/../../aids"
  mkdir_p(aid_dir)
  local lines = {
    "const mt = @import(\"meteorite_graph\");",
    "",
    "// Copy these stubs into native/src/handlers.zig or use `moon meteorite sync` later.",
    "",
  }
  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "zig" then
      lines[#lines + 1] = zig_stub_body(route)
      lines[#lines + 1] = ""
    end
  end
  write_file(aid_dir .. "/handlers.stub.zig", table.concat(lines, "\n"))
  write_file(aid_dir .. "/validators.stub.zig", "pub fn none(_: []const u8) bool { return true; }\n")
end

local function dev_stub_body(route)
  local name = zig_ident(route.id)
  local lines = {
    "pub fn " .. name .. "(c: mt.ctx." .. name .. ") !void {",
    "    // <meteorite:generated-stub>",
    "    // This handler was generated by Meteorite.",
    "    // Replace the body before shipping release-static.",
  }
  for _, param in ipairs(route.params) do
    lines[#lines + 1] = "    _ = c.params." .. zig_ident(param.name) .. ";"
  end
  for _, query in ipairs(route.query or {}) do
    lines[#lines + 1] = "    _ = c.query." .. zig_ident(query.name) .. ";"
  end
  if #route.params == 0 and #(route.query or {}) == 0 then lines[#lines + 1] = "    _ = c;" end
  lines[#lines + 1] = "    return c.text(501, \"handler `" .. name .. "` is not implemented\");"
  lines[#lines + 1] = "    // </meteorite:generated-stub>"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

local function grouped_zig_routes(graph)
  local routes = {}
  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "zig" then routes[#routes + 1] = route end
  end
  table.sort(routes, function(a, b) return a.id < b.id end)
  return routes
end

local function managed_handlers_block(graph)
  local lines = {
    "// <meteorite:imports>",
    "const mt = @import(\"meteorite_graph\");",
    "// </meteorite:imports>",
    "",
    "// <meteorite:handler-stubs>",
  }
  for _, route in ipairs(grouped_zig_routes(graph)) do
    lines[#lines + 1] = dev_stub_body(route)
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "// </meteorite:handler-stubs>"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function replace_block(content, start_marker, end_marker, replacement)
  local start_at = content:find(start_marker, 1, true)
  local end_at = content:find(end_marker, 1, true)
  if not start_at or not end_at or end_at < start_at then return nil end
  end_at = end_at + #end_marker
  return content:sub(1, start_at - 1) .. replacement .. content:sub(end_at + 1)
end

local function handler_warnings_path(output)
  return output .. "/../../aids/handler-sync.warnings.txt"
end

local function sync_handler_files(graph, output, mode)
  local root = project_root_from_output(output)
  local warnings = {}
  local handler_routes = grouped_zig_routes(graph)
  local handlers_path = path_join(root, "native/src/handlers.zig")
  local handler_content = read_file(handlers_path)

  if mode == "release-static" and handler_content and handler_content:find("<meteorite:generated-stub>", 1, true) then
    local first = handler_routes[1]
    local lines = {
      "release build contains generated handler stub" .. (first and (" `" .. first.id .. "`") or ""),
      "",
    }
    if first then
      lines[#lines + 1] = "route:"
      lines[#lines + 1] = "  " .. first.method .. " " .. first.raw_path
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "hint:"
    lines[#lines + 1] = "  implement native/src/handlers.zig before release-static builds."
    error(table.concat(lines, "\n"))
  end

  if #handler_routes > 0 and mode ~= "release-static" then
    if not handler_content then
      mkdir_p(dirname(handlers_path))
      write_file(handlers_path, managed_handlers_block(graph))
      warnings[#warnings + 1] = "created " .. handlers_path .. " with " .. tostring(#handler_routes) .. " route stubs"
    else
      local block = managed_handlers_block(graph)
      local updated = replace_block(handler_content, "// <meteorite:handler-stubs>", "// </meteorite:handler-stubs>", block:match("// <meteorite:handler%-stubs>.*") or block)
      if updated then
        write_file(handlers_path, updated)
        warnings[#warnings + 1] = "updated managed handler block in " .. handlers_path
      elseif handler_content:find("<meteorite:imports>", 1, true) then
        warnings[#warnings + 1] = "native/src/handlers.zig has Meteorite imports but no handler-stubs block; copy stubs from .meteorite/aids/handlers.stub.zig"
      else
        warnings[#warnings + 1] = table.concat({
          "native/src/handlers.zig exists but has no Meteorite managed block",
          "copy stubs from .meteorite/aids/handlers.stub.zig",
          "or add // <meteorite:handler-stubs> ... // </meteorite:handler-stubs>",
        }, "\n")
      end
    end
  end

  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "zig_file" and mode ~= "release-static" then
      local target = path_join(root, route.handler.path)
      if not file_exists(target) then
        mkdir_p(dirname(target))
        write_file(target, table.concat({
          "const mt = @import(\"meteorite_graph\");",
          "",
          "pub fn " .. (route.handler.decl or "handle") .. "(c: anytype) !void {",
          "    // <meteorite:generated-stub>",
          "    _ = mt;",
          "    _ = c;",
          "    return c.text(501, \"handler `" .. route.raw_path .. "` is not implemented\");",
          "    // </meteorite:generated-stub>",
          "}",
          "",
        }, "\n"))
        warnings[#warnings + 1] = "created " .. target
      end
    elseif route.handler.kind == "lua" and mode ~= "release-static" then
      local target = path_join(root, route.handler.path or route.handler.module)
      if target:match("%.lua$") and not file_exists(target) then
        mkdir_p(dirname(target))
        write_file(target, table.concat({
          "---@param c MeteoriteContext_" .. zig_ident(route.id),
          "return function(c)",
          "  return c:text(\"handler `" .. route.id .. "` is not implemented\")",
          "end",
          "",
        }, "\n"))
        warnings[#warnings + 1] = "created " .. target
      end
    end
  end

  if #warnings > 0 then
    write_file(handler_warnings_path(output), table.concat(warnings, "\n") .. "\n")
  end
end

local function sync_luarc(output)
  local root = project_root_from_output(output)
  local target = path_join(root, ".luarc.json")
  if file_exists(target) then return end
  write_file(target, table.concat({
    "{",
    "  \"workspace\": {",
    "    \"library\": [",
    "      \".meteorite/aids/lua\",",
    "      \".moonstone/env/share/lua\"",
    "    ],",
    "    \"checkThirdParty\": false",
    "  },",
    "  \"runtime\": {",
    "    \"version\": \"Lua 5.4\"",
    "  }",
    "}",
    "",
  }, "\n"))
end

local function scan_capabilities(source)
  local refs, seen = {}, {}
  local function add(kind, name)
    local key = kind .. "." .. name
    if seen[key] then return end
    seen[key] = true
    refs[#refs + 1] = { kind = kind, name = name }
  end
  for name in tostring(source):gmatch("c:http%(%s*[\"']([^\"']+)[\"']%s*%)") do add("http", name) end
  for name in tostring(source):gmatch("c:auth%(%s*[\"']([^\"']+)[\"']%s*%)") do add("auth", name) end
  for name in tostring(source):gmatch("c:zig%(%s*[\"']([^\"']+)[\"']%s*%)") do add("zig", name) end
  table.sort(refs, function(a, b) return (a.kind .. a.name) < (b.kind .. b.name) end)
  return refs
end

local function validate_capability_refs(graph, route, refs)
  for _, ref in ipairs(refs) do
    if not (graph.capabilities and graph.capabilities[ref.kind] and graph.capabilities[ref.kind][ref.name]) then
      error(table.concat({
        "route uses undeclared " .. ref.kind:upper() .. " capability `" .. ref.name .. "`",
        "",
        "route:",
        "  " .. route.method .. " " .. route.raw_path,
        "",
        "source:",
        "  " .. tostring(route.source.file) .. ":" .. tostring(route.source.line or 0) .. ":" .. tostring(route.source.column or 1),
        "",
        "hint:",
        "  declare it on the app with app:capability(\"" .. ref.kind .. "\", { " .. ref.name .. " = { ... } })",
      }, "\n"))
    end
  end
end

local function prepare_graph(graph, output, mode)
  for _, route in ipairs(graph.routes) do
    if route.handler.kind == "inline_lua" then
      local lifted = lifter.lift(route, { output = output })
      route.handler.lifted = lifted
      local file = io.open(lifted.chunk_path, "rb")
      local source = file and file:read("*a") or ""
      if file then file:close() end
      route.capabilities = scan_capabilities(source)
      validate_capability_refs(graph, route, route.capabilities)
      route.runtime.requires_lua = true
      route.runtime.execution_class = "lua"
      route.execution.class = "lua"
      route.execution.requires_lua = true
      for _, ref in ipairs(route.capabilities) do
        if ref.kind == "http" then route.runtime.requires_http = true end
        if ref.kind == "auth" then route.runtime.requires_auth = true end
        if ref.kind == "zig" then route.runtime.requires_zig_capability = true end
      end
    elseif route.handler.kind == "lua" then
      route.runtime.requires_lua = true
      route.runtime.execution_class = "lua"
      route.execution.class = "lua"
      route.execution.requires_lua = true
    end
  end
  return graph
end

local function sorted_handler_infos(routes)
  local infos, seen = {}, {}
  for _, route in ipairs(routes) do
    if route.handler.kind == "zig" and not seen[route.handler.symbol] then
      seen[route.handler.symbol] = true
      infos[#infos + 1] = {
        symbol = route.handler.symbol,
        import = route.handler.import or ("handlers." .. route.handler.symbol),
        method = route.method,
        path = route.raw_path,
        source = route.source,
      }
    end
  end
  table.sort(infos, function(a, b) return a.symbol < b.symbol end)
  return infos
end

local function sorted_route_handler_infos(routes)
  local infos = {}
  for _, route in ipairs(routes) do
    if route.handler.kind == "zig" then
      infos[#infos + 1] = {
        route_id = route.id,
        route_ident = zig_ident(route.id),
        symbol = route.handler.symbol,
        import = route.handler.import or ("handlers." .. route.handler.symbol),
        method = route.method,
        path = route.raw_path,
        source = route.source,
      }
    end
  end
  table.sort(infos, function(a, b) return a.route_id < b.route_id end)
  return infos
end

local function emit_bindings(graph, output)
  local infos = sorted_handler_infos(graph.routes)
  local route_infos = sorted_route_handler_infos(graph.routes)
  local lines = {
    "const handlers = @import(\"meteorite_handlers\");",
    "const validators = @import(\"meteorite_validators\");",
    "const mt = @import(\"meteorite_ctx\");",
    "",
    "comptime {",
  }
  for _, info in ipairs(infos) do
    lines[#lines + 1] = "    if (!@hasDecl(handlers, " .. zig_string(info.symbol) .. ")) @compileError(" .. zig_string(table.concat({
      "route " .. info.method .. " " .. info.path .. " references missing handler `" .. info.import .. "`",
      "",
      "declared at:",
      "  " .. tostring(info.source.file) .. ":" .. tostring(info.source.line or 0) .. ":" .. tostring(info.source.column or 1),
      "",
      "hint:",
      "  define `pub fn " .. info.symbol .. "(ctx: anytype) !void` in native/src/handlers.zig",
    }, "\n")) .. ");"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const HandlerId = enum {"
  for _, info in ipairs(infos) do lines[#lines + 1] = "    " .. info.symbol .. "," end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const ValidatorId = enum { none };"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {"
  lines[#lines + 1] = "    return switch (id) {"
  for _, info in ipairs(infos) do lines[#lines + 1] = "        ." .. info.symbol .. " => handlers." .. info.symbol .. "(ctx)," end
  lines[#lines + 1] = "    };"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callRoute(comptime route_id: []const u8, raw_ctx: anytype) !void {"
  for _, info in ipairs(route_infos) do
    lines[#lines + 1] = "    if (comptime std.mem.eql(u8, route_id, " .. zig_string(info.route_id) .. ")) return handlers." .. info.symbol .. "(try mt.ctx." .. info.route_ident .. ".from(raw_ctx));"
  end
  lines[#lines + 1] = "    @compileError(\"missing generated route handler binding for route `\" ++ route_id ++ \"`\");"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {"
  lines[#lines + 1] = "    _ = id;"
  lines[#lines + 1] = "    return validators.none(value);"
  lines[#lines + 1] = "}"
  table.insert(lines, 1, "const std = @import(\"std\");")
  write_file(output .. "/graph_bindings.zig", table.concat(lines, "\n") .. "\n")
end

local function pattern_class_map(pattern)
  local parsed = pattern.parsed
  local map = {}
  local other = #parsed.ranges
  for i = 0, 255 do map[i + 1] = other end
  for idx, range in ipairs(parsed.ranges) do
    for b = range[1], range[2] do map[b + 1] = idx - 1 end
  end
  return map, other + 1
end

local function emit_pattern_tables(graph, lines)
  lines[#lines + 1] = "pub const PatternId = enum { none" .. (#graph.patterns > 0 and "," or "")
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "    " .. zig_ident(pattern.id) .. "," end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const patterns = struct {"
  lines[#lines + 1] = "    pub fn match(comptime id: PatternId, input: []const u8) bool {"
  lines[#lines + 1] = "        return switch (id) {"
  lines[#lines + 1] = "            .none => true,"
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "            ." .. zig_ident(pattern.id) .. " => " .. zig_ident(pattern.id) .. ".match(input)," end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "    }"
  for _, pattern in ipairs(graph.patterns) do
    local class_map, class_count = pattern_class_map(pattern)
    local max = pattern.parsed.max
    local min = pattern.parsed.min
    local dead = max + 1
    local state_count = max + 2
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    const " .. zig_ident(pattern.id) .. "_class_map = [_]u8{"
    local row = "        "
    for i, class in ipairs(class_map) do
      row = row .. tostring(class) .. ", "
      if i % 32 == 0 then lines[#lines + 1] = row; row = "        " end
    end
    if row ~= "        " then lines[#lines + 1] = row end
    lines[#lines + 1] = "    };"
    lines[#lines + 1] = "    const " .. zig_ident(pattern.id) .. "_transitions = [_]u16{"
    for state = 0, state_count - 1 do
      local items = {}
      for class = 0, class_count - 1 do
        local next_state = dead
        if state < max and class < class_count - 1 then next_state = state + 1 end
        items[#items + 1] = tostring(next_state)
      end
      lines[#lines + 1] = "        " .. table.concat(items, ", ") .. ","
    end
    lines[#lines + 1] = "    };"
    lines[#lines + 1] = "    const " .. zig_ident(pattern.id) .. "_accept = [_]bool{"
    local accepts = {}
    for state = 0, state_count - 1 do accepts[#accepts + 1] = (state >= min and state <= max) and "true" or "false" end
    lines[#lines + 1] = "        " .. table.concat(accepts, ", ") .. ","
    lines[#lines + 1] = "    };"
    lines[#lines + 1] = "    pub const " .. zig_ident(pattern.id) .. " = @import(\"meteorite.zig\").DfaMatcher(.{ .class_map = &" .. zig_ident(pattern.id) .. "_class_map, .transition_table = &" .. zig_ident(pattern.id) .. "_transitions, .accept_table = &" .. zig_ident(pattern.id) .. "_accept, .class_count = " .. class_count .. ", .start_state = 0, .dead_state = " .. dead .. ", .max_input_bytes = " .. max .. " });"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
end

local function emit_graph_zig(graph, output)
  local max_arena = 0
  for _, route in ipairs(graph.routes) do if route.memory.request_arena_bytes > max_arena then max_arena = route.memory.request_arena_bytes end end
  local lines = {
    "pub const bindings = @import(\"graph_bindings.zig\");",
    "pub const ctx = @import(\"meteorite_ctx\").ctx;",
    "",
    "pub const max_request_arena_bytes = " .. tostring(max_arena) .. ";",
    "pub const Method = enum { GET, POST, OTHER };",
    "pub const Segment = union(enum) { literal: []const u8, param: []const u8 };",
    "pub const ZigSymbolHandler = struct { id: bindings.HandlerId, symbol: []const u8 };",
    "pub const ZigFileHandler = struct { id: []const u8, path: []const u8, decl: []const u8 = \"handle\" };",
    "pub const LuaFileHandler = struct { id: []const u8, path: []const u8 };",
    "pub const InlineLuaHandler = struct { id: []const u8, chunk_path: []const u8, source_file: []const u8, source_line: u32, source_column: u32 };",
    "pub const Handler = union(enum) { zig_symbol: ZigSymbolHandler, zig_file: ZigFileHandler, lua_file: LuaFileHandler, inline_lua: InlineLuaHandler };",
    "pub const ExecutionClass = enum { default, lua, blocking_io, cpu };",
    "pub const RouteRuntime = struct { requires_lua: bool = false, requires_http: bool = false, requires_auth: bool = false, requires_zig_capability: bool = false, execution_class: ExecutionClass = .default };",
    "pub const RouteExecution = struct { class: ExecutionClass = .default, may_block: bool = false, requires_lua: bool = false, requires_worker_pool: bool = false };",
    "pub const CapabilityRef = union(enum) { http: []const u8, auth: []const u8, zig: []const u8, lua: []const u8, worker: []const u8 };",
    "pub const WorkerStrategy = enum { auto, single_thread, io_plus_workers, per_core, pinned_appliance };",
    "pub const LuaStateStrategy = enum { single_locked, per_worker };",
    "pub const ThreadCount = union(enum) { auto, fixed: u16 };",
    "pub const RuntimeWorkers = struct { strategy: WorkerStrategy = .auto, io_threads: ThreadCount = .auto, worker_threads: ThreadCount = .auto, lua_state: LuaStateStrategy = .single_locked };",
    "pub const runtime_workers = RuntimeWorkers{};",
    "pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, bool, pattern };",
    "pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };",
    "pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{} };",
    "",
  }
  emit_pattern_tables(graph, lines)
  for i, route in ipairs(graph.routes) do
    lines[#lines + 1] = "const route_" .. i .. "_segments = [_]Segment{"
    for _, segment in ipairs(route.path.segments) do
      if segment.kind == "literal" then lines[#lines + 1] = "    .{ .literal = " .. zig_string(segment.value) .. " },"
      else lines[#lines + 1] = "    .{ .param = " .. zig_string(segment.name) .. " }," end
    end
    lines[#lines + 1] = "};"
    lines[#lines + 1] = "const route_" .. i .. "_query = [_]ParamSpec{"
    for _, query in ipairs(route.query or {}) do
      local pattern = "null"
      local kind = query.type or query.kind or "string"
      if query.kind == "pattern" then
        pattern = "." .. zig_ident(query.id)
        kind = "pattern"
      elseif query.pattern_id then
        pattern = "." .. zig_ident(query.pattern_id)
      end
      lines[#lines + 1] = "    .{ .name = " .. zig_string(query.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(query.max_len or 0) .. ", .exact_len = " .. tostring(query.exact_len or 0) .. ", .optional = " .. tostring(query.optional == true) .. ", .pattern = " .. pattern .. " },"
    end
    lines[#lines + 1] = "};"
    lines[#lines + 1] = "const route_" .. i .. "_params = [_]ParamSpec{"
    for _, param in ipairs(route.params) do
      local pattern = "null"
      local kind = param.type or param.kind or "string"
      if param.kind == "pattern" then
        pattern = "." .. zig_ident(param.id)
        kind = "pattern"
      elseif param.pattern_id then
        pattern = "." .. zig_ident(param.pattern_id)
      end
      lines[#lines + 1] = "    .{ .name = " .. zig_string(param.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(param.max_len or 0) .. ", .exact_len = " .. tostring(param.exact_len or 0) .. ", .optional = " .. tostring(param.optional == true) .. ", .pattern = " .. pattern .. " },"
    end
    lines[#lines + 1] = "};"
    lines[#lines + 1] = "const route_" .. i .. "_capabilities = [_]CapabilityRef{"
    for _, ref in ipairs(route.capabilities or {}) do
      lines[#lines + 1] = "    .{ ." .. ref.kind .. " = " .. zig_string(ref.name) .. " },"
    end
    lines[#lines + 1] = "};"
    lines[#lines + 1] = "pub const Route" .. i .. "Context = struct {"
    lines[#lines + 1] = "    pub const method = Method." .. route.method .. ";"
    lines[#lines + 1] = "    pub const path = " .. zig_string(route.raw_path) .. ";"
    lines[#lines + 1] = "    pub const params = route_" .. i .. "_params;"
    lines[#lines + 1] = "};"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const routes = [_]Route{"
  for i, route in ipairs(graph.routes) do
    local handler = ".{ .inline_lua = .{ .id = " .. zig_string(route.id) .. ", .chunk_path = " .. zig_string((route.handler.lifted or {}).chunk_path or "") .. ", .source_file = " .. zig_string((route.handler.lifted or {}).source_file or tostring(route.source.file)) .. ", .source_line = " .. tostring((route.handler.lifted or {}).source_line or route.source.line or 0) .. ", .source_column = " .. tostring((route.handler.lifted or {}).source_column or route.source.column or 1) .. " } }"
    if route.handler.kind == "zig" then handler = ".{ .zig_symbol = .{ .id = ." .. route.handler.symbol .. ", .symbol = " .. zig_string(route.handler.import or route.handler.symbol) .. " } }" end
    if route.handler.kind == "zig_file" then handler = ".{ .zig_file = .{ .id = " .. zig_string(route.handler.symbol) .. ", .path = " .. zig_string(route.handler.path) .. ", .decl = " .. zig_string(route.handler.decl or "handle") .. " } }" end
    if route.handler.kind == "lua" then handler = ".{ .lua_file = .{ .id = " .. zig_string(route.id) .. ", .path = " .. zig_string(route.handler.path or route.handler.module) .. " } }" end
    local runtime = ".{ .requires_lua = " .. tostring(route.runtime.requires_lua) .. ", .requires_http = " .. tostring(route.runtime.requires_http) .. ", .requires_auth = " .. tostring(route.runtime.requires_auth) .. ", .requires_zig_capability = " .. tostring(route.runtime.requires_zig_capability) .. ", .execution_class = ." .. route.runtime.execution_class .. " }"
    local execution = ".{ .class = ." .. route.execution.class .. ", .may_block = " .. tostring(route.execution.may_block) .. ", .requires_lua = " .. tostring(route.execution.requires_lua) .. ", .requires_worker_pool = " .. tostring(route.execution.requires_worker_pool) .. " }"
    lines[#lines + 1] = "    .{ .id = " .. zig_string(route.id) .. ", .method = ." .. route.method .. ", .raw_path = " .. zig_string(route.raw_path) .. ", .path = &route_" .. i .. "_segments, .params = &route_" .. i .. "_params, .query = &route_" .. i .. "_query, .max_body_bytes = " .. route.memory.max_body_bytes .. ", .request_arena_bytes = " .. route.memory.request_arena_bytes .. ", .handler = " .. handler .. ", .runtime = " .. runtime .. ", .execution = " .. execution .. ", .capabilities = &route_" .. i .. "_capabilities },"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  write_file(output .. "/graph.zig", table.concat(lines, "\n"))
end

local function json_quote(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local function emit_patterns_report(graph, output)
  local lines = { "[" }
  for i, pattern in ipairs(graph.patterns) do
    local r = pattern.report
    lines[#lines + 1] = "  {"
    lines[#lines + 1] = "    \"id\": " .. json_quote(pattern.id) .. ","
    lines[#lines + 1] = "    \"pattern\": " .. json_quote(r.pattern) .. ","
    lines[#lines + 1] = "    \"strategy\": " .. json_quote(r.strategy) .. ","
    lines[#lines + 1] = "    \"input_bound\": " .. r.input_bound .. ","
    lines[#lines + 1] = "    \"alphabet_classes\": " .. r.alphabet_classes .. ","
    lines[#lines + 1] = "    \"nfa_states\": " .. r.nfa_states .. ","
    lines[#lines + 1] = "    \"dfa_states\": " .. r.dfa_states .. ","
    lines[#lines + 1] = "    \"transition_table_bytes\": " .. r.transition_table_bytes .. ","
    lines[#lines + 1] = "    \"class_map_bytes\": " .. r.class_map_bytes .. ","
    lines[#lines + 1] = "    \"estimated_bytes\": " .. r.estimated_bytes .. ","
    lines[#lines + 1] = "    \"linear_time\": true,"
    lines[#lines + 1] = "    \"backtracking\": false"
    lines[#lines + 1] = "  }" .. (i < #graph.patterns and "," or "")
  end
  lines[#lines + 1] = "]\n"
  write_file(output .. "/patterns.graph.json", table.concat(lines, "\n"))
end

function emitter.emit(app, opts)
  opts = opts or {}
  local output = opts.output or ".meteorite/graph/current"
  local mode = opts.mode or "dev"
  mkdir_p(output)
  local graph = app:normalize({ mode = mode })
  graph = prepare_graph(graph, output, mode)
  local routes_zon = {}
  for _, route in ipairs(graph.routes) do routes_zon[#routes_zon + 1] = route_to_zon(route) end
  local routes_text = zon.encode(routes_zon)
  local graph_hash = hash_text(routes_text)
  write_file(output .. "/routes.zon", routes_text)
  write_file(output .. "/manifest.zon", zon.encode({ format = "meteorite.graph.v0", meteorite_version = "0.1.0", graph_hash = graph_hash, mode = mode_enum(mode) }))
  write_file(output .. "/runtime.zon", zon.encode({ mode = mode_enum(mode), lua_runtime = mode ~= "release-static", backend = { __meteorite_enum = true, value = "std_http" }, workers = { strategy = { __meteorite_enum = true, value = "auto" }, lua_state = { __meteorite_enum = true, value = "single_locked" } } }))
  write_file(output .. "/capabilities.zon", zon.encode({ backend = "std.http", methods = { "GET", "POST" }, declared = graph.capabilities or {} }))
  write_file(output .. "/graph_hash.txt", graph_hash .. "\n")
  emit_patterns_report(graph, output)
  emit_build_report(graph, output, mode)
  emit_luals_aids(graph, output)
  emit_ctx_zig(graph, output)
  emit_zig_aids(graph, output)
  sync_handler_files(graph, output, mode)
  sync_luarc(output)
  emit_bindings(graph, output)
  emit_graph_zig(graph, output)
  return { graph = graph, graph_hash = graph_hash, output = output }
end

return emitter
