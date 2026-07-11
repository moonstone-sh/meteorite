--- Context Zig emission, handler stub generation, and file sync.
--- Extracted from emitter.lua.
---
--- @class HandlerSyncModule
--- @field emit_ctx_zig fun(graph: table, output: string): void  Emit ctx.zig with route context types
--- @field sync_handler_files fun(graph: table, output: string, mode: string): void  Sync handler stub files
--- @field sync_luarc fun(output: string): void  Sync .luarc.json for LuaLS

---@type HandlerSyncModule
local helpers = require("codegen.helpers")
local project_root_from_output = helpers.project_root_from_output
local detect_lua_version = helpers.detect_lua_version
local fs = require("utils.fs")

local handler_sync = {}

local function graph_nodes(graph)
  return graph.nodes or graph.routes or {}
end

function handler_sync.zig_param_type(param)
  local kind = param.type or param.kind or "string"
  local base
  if kind == "u64" then return "u64" end
  if kind == "i32" then return "i32" end
  if kind == "bool" then return "bool" end
  base = "[]const u8"
  return base
end

function handler_sync.zig_optional_type(param)
  local base = handler_sync.zig_param_type(param)
  if param.optional then return "?" .. base end
  return base
end

function handler_sync.zig_value_conversion(param, accessor)
  local name = helpers.zig_ident(param.name)
  local raw_name = helpers.zig_string(param.name)
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

function handler_sync.zig_param_conversion(param)
  return handler_sync.zig_value_conversion(param, "raw.param")
end

function handler_sync.zig_query_conversion(param)
  return handler_sync.zig_value_conversion(param, "raw.query")
end

--- Emit ctx.zig with route context types.
---@param graph table  Normalized route graph
---@param output string  Output directory
function handler_sync.emit_ctx_zig(graph, output)
  local lines = {
    "const std = @import(\"std\");",
    "const protocol = @import(\"meteorite_protocol\");",
    "",
    "pub const Header = protocol.Header;",
    "pub const CookieOptions = protocol.CookieOptions;",
    "",
    "pub const Error = error{ MissingParam, InvalidParam } || std.fmt.ParseIntError;",
    "",
    "const VTable = struct {",
    "    method: *const fn (*anyopaque) []const u8,",
    "    path: *const fn (*anyopaque) []const u8,",
    "    param: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    message: *const fn (*anyopaque) []const u8,",
    "    metadata: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    query: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    header: *const fn (*anyopaque, []const u8) ?[]const u8,",
    "    request_id: *const fn (*anyopaque) anyerror![]const u8,",
    "    body: *const fn (*anyopaque) anyerror![]const u8,",
    "    text: *const fn (*anyopaque, u16, []const u8) anyerror!void,",
    "    text_with_headers: *const fn (*anyopaque, u16, []const u8, []const Header) anyerror!void,",
    "    bytes: *const fn (*anyopaque, u16, []const u8, []const u8) anyerror!void,",
    "    bytes_with_headers: *const fn (*anyopaque, u16, []const u8, []const u8, []const Header) anyerror!void,",
    "    json: *const fn (*anyopaque, u16, []const u8) anyerror!void,",
    "    json_with_headers: *const fn (*anyopaque, u16, []const u8, []const Header) anyerror!void,",
    "    empty: *const fn (*anyopaque, u16) anyerror!void,",
    "    empty_with_headers: *const fn (*anyopaque, u16, []const Header) anyerror!void,",
    "    redirect: *const fn (*anyopaque, u16, []const u8) anyerror!void,",
    "    set_cookie: *const fn (*anyopaque, []u8, []const u8, []const u8, CookieOptions) anyerror!Header,",
    "};",
    "",
    "fn VTableFor(comptime RawPtr: type) type {",
    "    return struct {",
    "        fn cast(ptr: *anyopaque) RawPtr { return @ptrCast(@alignCast(ptr)); }",
    "        fn method(ptr: *anyopaque) []const u8 { return @tagName(cast(ptr).method()); }",
    "        fn path(ptr: *anyopaque) []const u8 { return cast(ptr).path(); }",
    "        fn param(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).param(name); }",
    "        fn message(ptr: *anyopaque) []const u8 { return cast(ptr).message(); }",
    "        fn metadata(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).metadata(name); }",
    "        fn query(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).query(name); }",
    "        fn header(ptr: *anyopaque, name: []const u8) ?[]const u8 { return cast(ptr).header(name); }",
    "        fn requestId(ptr: *anyopaque) anyerror![]const u8 { return cast(ptr).requestId(); }",
    "        fn body(ptr: *anyopaque) anyerror![]const u8 { return cast(ptr).body(); }",
    "        fn text(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).text(status, response_body); }",
    "        fn textWithHeaders(ptr: *anyopaque, status: u16, response_body: []const u8, headers: []const Header) anyerror!void { return cast(ptr).textWithHeaders(status, response_body, headers); }",
    "        fn bytes(ptr: *anyopaque, status: u16, content_type: []const u8, response_body: []const u8) anyerror!void { return cast(ptr).bytes(status, content_type, response_body); }",
    "        fn bytesWithHeaders(ptr: *anyopaque, status: u16, content_type: []const u8, response_body: []const u8, headers: []const Header) anyerror!void { return cast(ptr).bytesWithHeaders(status, content_type, response_body, headers); }",
    "        fn json(ptr: *anyopaque, status: u16, response_body: []const u8) anyerror!void { return cast(ptr).json(status, response_body); }",
    "        fn jsonWithHeaders(ptr: *anyopaque, status: u16, response_body: []const u8, headers: []const Header) anyerror!void { return cast(ptr).jsonWithHeaders(status, response_body, headers); }",
    "        fn empty(ptr: *anyopaque, status: u16) anyerror!void { return cast(ptr).empty(status); }",
    "        fn emptyWithHeaders(ptr: *anyopaque, status: u16, headers: []const Header) anyerror!void { return cast(ptr).emptyWithHeaders(status, headers); }",
    "        fn redirect(ptr: *anyopaque, status: u16, location: []const u8) anyerror!void { return cast(ptr).redirect(status, location); }",
    "        fn setCookie(ptr: *anyopaque, buffer: []u8, name: []const u8, cookie_value: []const u8, options: CookieOptions) anyerror!Header { return cast(ptr).setCookie(buffer, name, cookie_value, options); }",
    "        pub const value = VTable{ .method = method, .path = path, .param = param, .message = message, .metadata = metadata, .query = query, .header = header, .request_id = requestId, .body = body, .text = text, .text_with_headers = textWithHeaders, .bytes = bytes, .bytes_with_headers = bytesWithHeaders, .json = json, .json_with_headers = jsonWithHeaders, .empty = empty, .empty_with_headers = emptyWithHeaders, .redirect = redirect, .set_cookie = setCookie };",
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
  for _, route in ipairs(graph_nodes(graph)) do
    local id = helpers.zig_ident(route.id)
    local params_name = "Params_" .. id
    local query_name = "Query_" .. id
    lines[#lines + 1] = "    pub const " .. params_name .. " = struct {"
    for _, param in ipairs(route.params) do
      lines[#lines + 1] = "            " .. helpers.zig_ident(param.name) .. ": " .. handler_sync.zig_param_type(param) .. ","
    end
    lines[#lines + 1] = "        };"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    pub const " .. query_name .. " = struct {"
    for _, query in ipairs(route.query or {}) do
      lines[#lines + 1] = "            " .. helpers.zig_ident(query.name) .. ": " .. handler_sync.zig_optional_type(query) .. ","
    end
    lines[#lines + 1] = "        };"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    pub const " .. id .. " = struct {"
    lines[#lines + 1] = "        pub const method_name = \"" .. route.method .. "\";"
    lines[#lines + 1] = "        pub const route_path = " .. helpers.zig_string(route.raw_path) .. ";"
    lines[#lines + 1] = "        params: " .. params_name .. ","
    lines[#lines + 1] = "        query: " .. query_name .. ","
    lines[#lines + 1] = "        raw: *anyopaque,"
    lines[#lines + 1] = "        vtable: *const VTable,"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "        pub fn from(raw: anytype) Error!" .. id .. " {"
    lines[#lines + 1] = "            return .{ .params = .{"
    for i, param in ipairs(route.params) do
      lines[#lines + 1] = "                " .. handler_sync.zig_param_conversion(param) .. (i < #route.params and "," or "")
    end
    lines[#lines + 1] = "            }, .query = .{"
    for i, query in ipairs(route.query or {}) do
      lines[#lines + 1] = "                " .. handler_sync.zig_query_conversion(query) .. (i < #(route.query or {}) and "," or "")
    end
    lines[#lines + 1] = "            }, .raw = raw, .vtable = &VTableFor(@TypeOf(raw)).value };"
    lines[#lines + 1] = "        }"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "        pub fn method(self: " .. id .. ") []const u8 { return self.vtable.method(self.raw); }"
    lines[#lines + 1] = "        pub fn path(self: " .. id .. ") []const u8 { return self.vtable.path(self.raw); }"
    lines[#lines + 1] = "        pub fn param(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.param(self.raw, name); }"
    lines[#lines + 1] = "        pub fn message(self: " .. id .. ") []const u8 { return self.vtable.message(self.raw); }"
    lines[#lines + 1] = "        pub fn metadata(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.metadata(self.raw, name); }"
    lines[#lines + 1] = "        pub fn queryValue(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }"
    lines[#lines + 1] = "        pub fn header(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }"
    lines[#lines + 1] = "        pub fn requestId(self: " .. id .. ") ![]const u8 { return self.vtable.request_id(self.raw); }"
    lines[#lines + 1] = "        pub fn body(self: " .. id .. ") ![]const u8 { return self.vtable.body(self.raw); }"
    lines[#lines + 1] = "        pub fn text(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }"
    lines[#lines + 1] = "        pub fn textWithHeaders(self: " .. id .. ", status: u16, response_body: []const u8, headers: []const Header) !void { return self.vtable.text_with_headers(self.raw, status, response_body, headers); }"
    lines[#lines + 1] = "        pub fn bytes(self: " .. id .. ", status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }"
    lines[#lines + 1] = "        pub fn bytesWithHeaders(self: " .. id .. ", status: u16, content_type: []const u8, response_body: []const u8, headers: []const Header) !void { return self.vtable.bytes_with_headers(self.raw, status, content_type, response_body, headers); }"
    lines[#lines + 1] = "        pub fn json(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }"
    lines[#lines + 1] = "        pub fn jsonWithHeaders(self: " .. id .. ", status: u16, response_body: []const u8, headers: []const Header) !void { return self.vtable.json_with_headers(self.raw, status, response_body, headers); }"
    lines[#lines + 1] = "        pub fn empty(self: " .. id .. ", status: u16) !void { return self.vtable.empty(self.raw, status); }"
    lines[#lines + 1] = "        pub fn emptyWithHeaders(self: " .. id .. ", status: u16, headers: []const Header) !void { return self.vtable.empty_with_headers(self.raw, status, headers); }"
    lines[#lines + 1] = "        pub fn redirect(self: " .. id .. ", status: u16, location: []const u8) !void { return self.vtable.redirect(self.raw, status, location); }"
    lines[#lines + 1] = "        pub fn setCookie(self: " .. id .. ", buffer: []u8, name: []const u8, value: []const u8, options: CookieOptions) !Header { return self.vtable.set_cookie(self.raw, buffer, name, value, options); }"
    lines[#lines + 1] = "    };"
  end
  lines[#lines + 1] = "};"
  helpers.write_file(output .. "/ctx.zig", table.concat(lines, "\n") .. "\n")
end

function handler_sync.zig_stub_body(route)
  local name = helpers.zig_ident(route.id)
  local lines = {
    "pub fn " .. name .. "(c: mt.ctx." .. name .. ") !void {",
    "    // <meteorite:generated-stub>",
    "    // This handler was generated by Meteorite.",
    "    // Replace the body before shipping release-static.",
  }
  for _, param in ipairs(route.params) do
    lines[#lines + 1] = "    _ = c.params." .. helpers.zig_ident(param.name) .. ";"
  end
  for _, query in ipairs(route.query or {}) do
    lines[#lines + 1] = "    _ = c.query." .. helpers.zig_ident(query.name) .. ";"
  end
  if #route.params == 0 and #(route.query or {}) == 0 then lines[#lines + 1] = "    _ = c;" end
  lines[#lines + 1] = "    return c.text(501, \"handler `" .. name .. "` is not implemented\");"
  lines[#lines + 1] = "    // </meteorite:generated-stub>"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

function handler_sync.emit_zig_aids(graph, output)
  local aid_dir = output .. "/../../aids"
  fs.mkdir_p(aid_dir)
  local lines = {
    "const mt = @import(\"meteorite_graph\");",
    "",
    "// Copy these stubs into zig/handlers.zig or use `moon meteorite sync` later.",
    "",
  }
  for _, route in ipairs(graph_nodes(graph)) do
    if route.handler.kind == "zig" then
      lines[#lines + 1] = handler_sync.zig_stub_body(route)
      lines[#lines + 1] = ""
    end
  end
  helpers.write_file(aid_dir .. "/handlers.stub.zig", table.concat(lines, "\n"))
  helpers.write_file(aid_dir .. "/validators.stub.zig", "pub fn none(_: []const u8) bool { return true; }\n")
end

function handler_sync.dev_stub_body(route)
  local name = helpers.zig_ident(route.id)
  local lines = {
    "pub fn " .. name .. "(c: mt.ctx." .. name .. ") !void {",
    "    // <meteorite:generated-stub>",
    "    // This handler was generated by Meteorite.",
    "    // Replace the body before shipping release-static.",
  }
  for _, param in ipairs(route.params) do
    lines[#lines + 1] = "    _ = c.params." .. helpers.zig_ident(param.name) .. ";"
  end
  for _, query in ipairs(route.query or {}) do
    lines[#lines + 1] = "    _ = c.query." .. helpers.zig_ident(query.name) .. ";"
  end
  if #route.params == 0 and #(route.query or {}) == 0 then lines[#lines + 1] = "    _ = c;" end
  lines[#lines + 1] = "    return c.text(501, \"handler `" .. name .. "` is not implemented\");"
  lines[#lines + 1] = "    // </meteorite:generated-stub>"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

function handler_sync.grouped_zig_routes(graph)
  local routes = {}
  for _, route in ipairs(graph_nodes(graph)) do
    if route.handler.kind == "zig" then routes[#routes + 1] = route end
  end
  table.sort(routes, function(a, b) return a.id < b.id end)
  return routes
end

function handler_sync.managed_handlers_block(graph)
  local lines = {
    "// <meteorite:imports>",
    "const mt = @import(\"meteorite_graph\");",
    "// </meteorite:imports>",
    "",
    "// <meteorite:handler-stubs>",
  }
  for _, route in ipairs(handler_sync.grouped_zig_routes(graph)) do
    lines[#lines + 1] = handler_sync.dev_stub_body(route)
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "// </meteorite:handler-stubs>"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function handler_sync.replace_block(content, start_marker, end_marker, replacement)
  local start_at = content:find(start_marker, 1, true)
  local end_at = content:find(end_marker, 1, true)
  if not start_at or not end_at or end_at < start_at then return nil end
  end_at = end_at + #end_marker
  return content:sub(1, start_at - 1) .. replacement .. content:sub(end_at + 1)
end

function handler_sync.handler_warnings_path(output)
  return output .. "/../../aids/handler-sync.warnings.txt"
end

--- Sync handler stub files for missing Zig handlers.
---@param graph table  Normalized route graph
---@param output string  Output directory
---@param mode string  Build mode
function handler_sync.sync_handler_files(graph, output, mode)
  local root = project_root_from_output(output)
  local warnings = {}
  local handler_routes = handler_sync.grouped_zig_routes(graph)
  local handlers_path = helpers.path_join(root, "zig/handlers.zig")
  local handler_content = helpers.read_file(handlers_path)

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
    lines[#lines + 1] = "  implement zig/handlers.zig before release-static builds."
    error(table.concat(lines, "\n"))
  end

  if #handler_routes > 0 and mode ~= "release-static" then
    if not handler_content then
      fs.mkdir_p(helpers.dirname(handlers_path))
      helpers.write_file(handlers_path, handler_sync.managed_handlers_block(graph))
      warnings[#warnings + 1] = "created " .. handlers_path .. " with " .. tostring(#handler_routes) .. " route stubs"
    else
      local block = handler_sync.managed_handlers_block(graph)
      local updated = handler_sync.replace_block(handler_content, "// <meteorite:handler-stubs>", "// </meteorite:handler-stubs>", block:match("// <meteorite:handler%-stubs>.*") or block)
      if updated then
        helpers.write_file(handlers_path, updated)
        warnings[#warnings + 1] = "updated managed handler block in " .. handlers_path
      elseif handler_content:find("<meteorite:imports>", 1, true) then
        warnings[#warnings + 1] = "zig/handlers.zig has Meteorite imports but no handler-stubs block; copy stubs from .meteorite/aids/handlers.stub.zig"
      else
        warnings[#warnings + 1] = table.concat({
          "zig/handlers.zig exists but has no Meteorite managed block",
          "copy stubs from .meteorite/aids/handlers.stub.zig",
          "or add // <meteorite:handler-stubs> ... // </meteorite:handler-stubs>",
        }, "\n")
      end
    end
  end

  for _, route in ipairs(graph_nodes(graph)) do
    if route.handler.kind == "zig_file" and mode ~= "release-static" then
      local target = helpers.path_join(root, route.handler.path)
      if not helpers.file_exists(target) then
        fs.mkdir_p(helpers.dirname(target))
        helpers.write_file(target, table.concat({
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
      local target = helpers.path_join(root, route.handler.path or route.handler.module)
      if target:match("%.lua$") and not helpers.file_exists(target) then
        fs.mkdir_p(helpers.dirname(target))
        helpers.write_file(target, table.concat({
          "---@param c MeteoriteContext_" .. helpers.zig_ident(route.id),
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
    helpers.write_file(handler_sync.handler_warnings_path(output), table.concat(warnings, "\n") .. "\n")
  end
end

function handler_sync.sync_luarc(output)
  local root = project_root_from_output(output)
  local target = helpers.path_join(root, ".luarc.json")
  local lua_ver = helpers.detect_lua_version(root)
  helpers.write_file(target, table.concat({
    "{",
    "  \"workspace\": {",
    "    \"library\": [",
    "      \".meteorite/aids/lua\",",
    "      \".moonstone/env/share/lua/" .. lua_ver .. "\",",
    "      \".moonstone/env/lib/lua/" .. lua_ver .. "\",",
    "      \"src\"",
    "    ],",
    "    \"checkThirdParty\": false,",
    "    \"useGitIgnore\": false,",
    "    \"ignoreDir\": [",
    "      \".moonstone/env/bin\",",
    "      \".moonstone/env/include\",",
    "      \"zig-cache\",",
    "      \"zig-out\",",
    "      \".meteorite/graph\",",
    "      \"dist\",",
    "      \".git\"",
    "    ]",
    "  },",
    "  \"runtime\": {",
    "    \"version\": \"Lua " .. lua_ver .. "\",",
    "    \"path\": [",
    "      \"src/?.lua\",",
    "      \"src/?/init.lua\",",
    "      \".meteorite/aids/lua/?.lua\",",
    "      \".meteorite/aids/lua/?/init.lua\",",
    "      \".moonstone/env/share/lua/" .. lua_ver .. "/?.lua\",",
    "      \".moonstone/env/share/lua/" .. lua_ver .. "/?/init.lua\",",
    "      \".moonstone/env/share/lua/" .. lua_ver .. "/meteorite/?.lua\",",
    "      \".moonstone/env/share/lua/" .. lua_ver .. "/meteorite/?/init.lua\"",
    "    ]",
    "  },",
    "  \"completion\": {",
    "    \"autoRequire\": true",
    "  },",
    "  \"diagnostics\": {",
    "    \"disable\": [",
    "      \"lowercase-global\"",
    "    ]",
    "  }",
    "}",
    "",
  }, "\n"))
end

return handler_sync
