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
    lines[#lines + 1] = "        pub fn queryValue(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.query(self.raw, name); }"
    lines[#lines + 1] = "        pub fn header(self: " .. id .. ", name: []const u8) ?[]const u8 { return self.vtable.header(self.raw, name); }"
    lines[#lines + 1] = "        pub fn body(self: " .. id .. ") ![]const u8 { return self.vtable.body(self.raw); }"
    lines[#lines + 1] = "        pub fn text(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.text(self.raw, status, response_body); }"
    lines[#lines + 1] = "        pub fn bytes(self: " .. id .. ", status: u16, content_type: []const u8, response_body: []const u8) !void { return self.vtable.bytes(self.raw, status, content_type, response_body); }"
    lines[#lines + 1] = "        pub fn json(self: " .. id .. ", status: u16, response_body: []const u8) !void { return self.vtable.json(self.raw, status, response_body); }"
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
  for _, route in ipairs(graph.routes) do
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
  for _, route in ipairs(graph.routes) do
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

  for _, route in ipairs(graph.routes) do
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
    "    \"checkThirdParty\": \"Disable\",",
    "    \"useGitIgnore\": true,",
    "    \"ignoreDir\": [",
    "      \".moonstone/env/bin\",",
    "      \".moonstone/env/bin-runtime\",",
    "      \".moonstone/env/include\",",
    "      \".moonstone/env/libexec\",",
    "      \".ballad\",",
    "      \"zig-cache\",",
    "      \".zig-cache\",",
    "      \"zig-out\",",
    "      \".meteorite/graph\",",
    "      \".meteorite/dev\",",
    "      \".meteorite/cache\",",
    "      \"dist\",",
    "      \"node_modules\",",
    "      \".git\"",
    "    ],",
    "    \"maxPreload\": 2000,",
    "    \"preloadFileSize\": 200",
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

function handler_sync.moonstone_scripts(build_mode)
  local release_mode = build_mode == "release-static" and "static" or "hybrid"
  return {
    { key = "graph", command = "meteorite graph src/main.lua .meteorite/graph/current " .. tostring(build_mode or "hybrid") .. " fast_http" },
    { key = "dev", command = "moon exec ballad play Watch_partiture.lua -- --mode hybrid_dev --backend fast_http --hybrid-profile optimized --router-dispatch param_matchers" },
    { key = "build", command = "moon exec ballad play Dev_partiture.lua -- --mode hybrid_dev --backend fast_http --hybrid-profile optimized --router-dispatch param_matchers" },
    { key = "run", command = "moon run build && ./dist/server" },
    { key = "release", command = "moon exec ballad play partiture.lua -- --mode " .. release_mode .. " --backend fast_http --hybrid-profile optimized --router-dispatch param_matchers" },
    { key = "check", command = "moon exec ballad play Check_partiture.lua -- --mode " .. release_mode .. " --backend fast_http --hybrid-profile optimized --router-dispatch param_matchers" },
    { key = "check:release", command = "moon exec ballad play Check_partiture.lua -- --mode " .. release_mode .. " --backend fast_http --hybrid-profile optimized --router-dispatch param_matchers" },
    { key = "check:static", command = "moon exec ballad play Check_partiture.lua -- --mode static --backend fast_http --router-dispatch param_matchers" },
    { key = "doctor", command = "meteorite doctor" },
    { key = "invoke:health", command = "meteorite invoke --json src/main.lua GET /health" },
  }
end

function handler_sync.moonstone_manifest(name, build_mode)
  local lines = {
    "[package]",
    "name = \"" .. tostring(name) .. "\"",
    "version = \"0.1.0\"",
    "kind = \"app\"",
    "",
    "[interpreter]",
    "name = \"lua\"",
    "version = \"5.4\"",
    "abi = \"5.4\"",
    "",
    "[[dependencies]]",
    "name = \"moonstone/meteorite\"",
    "constraint = \"^0.1.41\"",
    "role = \"tool\"",
    "",
    "[[dependencies]]",
    "name = \"moonstone/ballad\"",
    "constraint = \"^0.2.41\"",
    "role = \"tool\"",
    "",
    "[scripts]",
  }
  for _, script in ipairs(handler_sync.moonstone_scripts(build_mode)) do
    lines[#lines + 1] = script.key .. " = \"" .. script.command .. "\""
  end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function handler_sync.partiture_common()
  return table.concat({
    "local request = require(\"meteorite.build_request\")",
    "",
    "local common = {}",
    "",
    "function common.request(p)",
    "  local value = request.parse(p.invocation.args)",
    "  return request.require_behavior(value, \"Meteorite partiture\")",
    "end",
    "",
    "function common.options(value)",
    "  return request.to_options(value)",
    "end",
    "",
    "return common",
    "",
  }, "\n")
end

function handler_sync.project_build_zig()
  return table.concat({
    "const std = @import(\"std\");",
    "const meteorite = @import(\".moonstone/env/libexec/meteorite/files/meteorite/zig/build_api.zig\");",
    "",
    "pub fn build(b: *std.Build) void {",
    "    const target = b.standardTargetOptions(.{});",
    "    const optimize = b.standardOptimizeOption(.{});",
    "    const mode = b.option([]const u8, \"mode\", \"Meteorite build mode\") orelse \"release-static\";",
    "    const backend = b.option([]const u8, \"backend\", \"Meteorite backend\") orelse \"fast_http\";",
    "    const service = meteorite.addService(b, .{",
    "        .meteorite_root = \".moonstone/env/libexec/meteorite/files/meteorite\",",
    "        .target = target,",
    "        .optimize = optimize,",
    "        .mode = mode,",
    "        .backend = backend,",
    "        .graph_input = b.option([]const u8, \"graph-input\", \"Meteorite app entry\") orelse \"src/main.lua\",",
    "        .graph_output = b.option([]const u8, \"graph-output\", \"Meteorite graph output\") orelse \".meteorite/graph/current\",",
    "        .lua_root = b.option([]const u8, \"lua-root\", \"Lua runtime root\") orelse \".moonstone/env/libexec/lua/files\",",
    "        .hybrid_profile = b.option([]const u8, \"hybrid-profile\", \"Meteorite hybrid profile\") orelse \"default\",",
    "        .router_dispatch = b.option([]const u8, \"router-dispatch\", \"Meteorite router dispatch\") orelse \"method_buckets\",",
    "        .unix_socket_path = b.option([]const u8, \"unix-socket-path\", \"Unix socket path\") orelse \"/tmp/meteorite.sock\",",
    "        .unix_socket_mode = b.option([]const u8, \"unix-socket-mode\", \"Unix socket mode\") orelse \"0660\",",
    "        .unix_socket_unlink_stale = b.option(bool, \"unix-socket-unlink-stale\", \"Unlink stale Unix socket\") orelse true,",
    "        .require_peer_credentials = b.option(bool, \"require-peer-credentials\", \"Require Unix peer credentials\") orelse false,",
    "        .peer_allow_uid = b.option([]const u8, \"peer-allow-uid\", \"Allowed Unix peer UID\") orelse \"\",",
    "        .peer_allow_gid = b.option([]const u8, \"peer-allow-gid\", \"Allowed Unix peer GID\") orelse \"\",",
    "    });",
    "    const meteorite_step = b.step(\"meteorite\", \"Build the Meteorite service\");",
    "    meteorite_step.dependOn(service.install_step);",
    "}",
    "",
  }, "\n")
end

function handler_sync.release_partiture()
  return table.concat({
    "local ballad = require(\"ballad\")",
    "local moonstone = require(\"ballad.plugins.moonstone\")",
    "local common = require(\"partiture_common\")",
    "",
    "return ballad.partiture(function(p)",
    "  local meteorite = p:use(\"meteorite.ballad\")",
    "  local request = common.request(p)",
    "  local project = moonstone.project_prepare({ root = \".\", roles = { \"runtime\" } })",
    "  local release = meteorite.release({",
    "    project = project,",
    "    input = \"src/main.lua\",",
    "    graph_output = \".meteorite/graph/release\",",
    "    build_file = \"build.zig\",",
    "    mode = request.mode,",
    "    bin = \"bin/server\",",
    "    backend = request.backend,",
    "    hybrid_profile = request.hybrid_profile,",
    "    router_dispatch = request.router_dispatch,",
    "    target = request.target,",
    "  })",
    "  p.sink.directory(release, { out = \"dist/release\", file_graph = true })",
    "end)",
    "",
  }, "\n")
end

function handler_sync.dev_partiture()
  return table.concat({
    "local ballad = require(\"ballad\")",
    "local common = require(\"partiture_common\")",
    "",
    "return ballad.partiture(function(p)",
    "  local request = common.request(p)",
    "  local meteorite = p:use(\"meteorite.ballad\")",
    "  local graph = meteorite.graph({ input = \"src/main.lua\", output = \".meteorite/graph/current\", mode = request.mode, backend = request.backend })",
    "  local build = meteorite.zig({ input = \"src/main.lua\", graph = \".meteorite/graph/current\", mode = request.mode, backend = request.backend, hybrid_profile = request.hybrid_profile, router_dispatch = request.router_dispatch, target = request.target })",
    "  p.sink.none(p.task.run(build))",
    "end)",
    "",
  }, "\n")
end

function handler_sync.watch_partiture()
  return table.concat({
    "local ballad = require(\"ballad\")",
    "local common = require(\"partiture_common\")",
    "",
    "return ballad.partiture(function(p)",
    "  local watcher = p:use(ballad.plugins.watcher)",
    "  local request = common.request(p)",
    "  local app = p.source.files({ \"**/*.lua\" }, { root = \"src\" })",
    "  local meteorite = p:use(\"meteorite.ballad\")",
    "  local graph = meteorite.graph({ input = \"src/main.lua\", output = \".meteorite/graph/current\", mode = request.mode, backend = request.backend })",
    "  local build = meteorite.zig({ input = \"src/main.lua\", graph = \".meteorite/graph/current\", mode = request.mode, backend = request.backend, hybrid_profile = request.hybrid_profile, router_dispatch = request.router_dispatch, target = request.target })",
    "  p.sink.none(watcher.watch({",
    "    initial = { run = build, effect = \"./dist/server\" },",
    "    reactions = { { watch = { app }, run = build, effect = \"./dist/server\" } },",
    "  }))",
    "end)",
    "",
  }, "\n")
end

function handler_sync.check_partiture()
  return table.concat({
    "local ballad = require(\"ballad\")",
    "local common = require(\"partiture_common\")",
    "",
    "return ballad.partiture(function(p)",
    "  local meteorite = p:use(\"meteorite.ballad\")",
    "  local request = common.request(p)",
    "  local report = meteorite.check({ input = \"src/main.lua\", output = \".meteorite/check/report\", mode = request.mode, backend = request.backend, target = request.target })",
    "  p.sink.none(report)",
    "end)",
    "",
  }, "\n")
end

return handler_sync
