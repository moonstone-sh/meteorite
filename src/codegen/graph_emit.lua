--- Graph preparation, Zig bindings, route modules, and graph.zig emission.
--- Extracted from emitter.lua.
---
--- @class GraphEmitModule
--- @field prepare_graph fun(graph: table, output: string, mode: string): table  Prepare and clean graph data
--- @field emit_bindings fun(graph: table, output: string): void  Emit graph_bindings.zig
--- @field emit_pattern_modules fun(graph: table, output: string): void  Emit pattern/*.zig modules
--- @field emit_route_modules fun(graph: table, output: string): void  Emit routes/*.zig modules
--- @field emit_graph_zig fun(graph: table, output: string): void  Emit main graph.zig

---@type GraphEmitModule
local helpers = require("codegen.helpers")
local zon = require("codegen.zon")
local lifter = require("codegen.lifter")
local static_compiler = require("codegen.static")
local fs = require("utils.fs")

local graph_emit = {}
function graph_emit.scan_capabilities(source)
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

function graph_emit.validate_capability_refs(graph, route, refs)
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

--- Prepare and clean graph data before emission.
---@param graph table  Normalized route graph
---@param output string  Output directory
---@param mode string  Build mode
---@return table  Prepared graph
function graph_emit.prepare_graph(graph, output, mode)
  for _, plugin in ipairs(graph.plugins or {}) do
    if type(plugin.execute) ~= "function" then
      error("plugin " .. tostring(plugin.id) .. " must declare an execute function")
    end
    local lifted = lifter.lift_plugin(plugin, { output = output })
    plugin.handler = { kind = "inline_lua", lifted = lifted }
    plugin.execute = nil
  end
  for _, route in ipairs(graph.routes) do
    local plugin_ids = {}
    for _, plugin in ipairs(route.scope.plugins or {}) do
      if type(plugin) == "table" and plugin.__meteorite_plugin then
        plugin_ids[#plugin_ids + 1] = plugin.id
      elseif type(plugin) == "string" then
        plugin_ids[#plugin_ids + 1] = plugin
      end
    end
    route.scope.plugins = plugin_ids
    if route.handler.kind == "zig_file" and not tostring(route.handler.path or ""):match("^/") then
      route.handler.source_path = helpers.path_join(helpers.project_root_from_output(output), route.handler.path)
    end
    static_compiler.prepare_route(route, output, mode)
    if route.handler.kind == "inline_lua" then
      local lifted = lifter.lift(route, { output = output })
      route.handler.lifted = lifted
      local file = io.open(lifted.chunk_path, "rb")
      local source = file and file:read("*a") or ""
      if file then file:close() end
      route.capabilities = graph_emit.scan_capabilities(source)
      graph_emit.validate_capability_refs(graph, route, route.capabilities)
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

function graph_emit.sorted_handler_infos(routes)
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

function graph_emit.sorted_route_handler_infos(routes)
  local infos = {}
  for _, route in ipairs(routes) do
    if route.handler.kind == "zig" or route.handler.kind == "zig_file" then
      infos[#infos + 1] = {
        route_id = route.id,
        route_ident = helpers.zig_ident(route.id),
        kind = route.handler.kind,
        symbol = route.handler.symbol,
        file_path = route.handler.source_path or route.handler.path,
        decl = route.handler.decl or "handle",
        import = route.handler.import or ("handlers." .. tostring(route.handler.symbol)),
        method = route.method,
        path = route.raw_path,
        source = route.source,
      }
    end
  end
  table.sort(infos, function(a, b) return a.route_id < b.route_id end)
  return infos
end

function graph_emit.relative_path(from_dir, to_path)
  local from = tostring(from_dir or ""):gsub("\\", "/")
  local to = tostring(to_path or ""):gsub("\\", "/")
  local from_parts = {}
  for part in from:gmatch("[^/]+") do
    if part ~= "." and part ~= "" then from_parts[#from_parts + 1] = part end
  end
  local to_parts = {}
  for part in to:gmatch("[^/]+") do
    if part ~= "." and part ~= "" then to_parts[#to_parts + 1] = part end
  end
  local i = 1
  while i <= #from_parts and i <= #to_parts and from_parts[i] == to_parts[i] do i = i + 1 end
  local out = {}
  for _ = i, #from_parts do out[#out + 1] = ".." end
  for j = i, #to_parts do out[#out + 1] = to_parts[j] end
  if #out == 0 then return "." end
  return table.concat(out, "/")
end

--- Emit graph_bindings.zig with handler bindings.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_emit.emit_bindings(graph, output)
  local infos = graph_emit.sorted_handler_infos(graph.routes)
  local route_infos = graph_emit.sorted_route_handler_infos(graph.routes)
  local lines = {
    "const handlers = @import(\"meteorite_handlers\");",
    "const validators = @import(\"meteorite_validators\");",
    "const mt = @import(\"meteorite_ctx\");",
    "",
    "comptime {",
  }
  for _, info in ipairs(infos) do
    lines[#lines + 1] = "    if (!@hasDecl(handlers, " .. helpers.zig_string(info.symbol) .. ")) @compileError(" .. helpers.zig_string(table.concat({
      "route " .. info.method .. " " .. info.path .. " references missing handler `" .. info.import .. "`",
      "",
      "declared at:",
      "  " .. tostring(info.source.file) .. ":" .. tostring(info.source.line or 0) .. ":" .. tostring(info.source.column or 1),
      "",
      "hint:",
      "  define `pub fn " .. info.symbol .. "(ctx: anytype) !void` in zig/handlers.zig",
    }, "\n")) .. ");"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  for _, info in ipairs(route_infos) do
    if info.kind == "zig_file" then
      lines[#lines + 1] = "const zig_file_" .. info.route_ident .. " = @import(" .. helpers.zig_string("meteorite_zig_file_" .. info.route_ident) .. ");"
    end
  end
  if #route_infos > 0 then lines[#lines + 1] = "" end
  lines[#lines + 1] = "pub const HandlerId = enum {"
  for _, info in ipairs(infos) do lines[#lines + 1] = "    " .. info.symbol .. "," end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const ValidatorId = enum { none };"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callHandler(comptime id: HandlerId, ctx: anytype) !void {"
  if #infos == 0 then lines[#lines + 1] = "    _ = ctx;" end
  lines[#lines + 1] = "    return switch (id) {"
  for _, info in ipairs(infos) do lines[#lines + 1] = "        ." .. info.symbol .. " => handlers." .. info.symbol .. "(ctx)," end
  lines[#lines + 1] = "    };"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callRoute(comptime route_id: []const u8, raw_ctx: anytype) !void {"
  if #route_infos == 0 then lines[#lines + 1] = "    _ = raw_ctx;" end
  for _, info in ipairs(route_infos) do
    if info.kind == "zig_file" then
      lines[#lines + 1] = "    if (comptime std.mem.eql(u8, route_id, " .. helpers.zig_string(info.route_id) .. ")) return zig_file_" .. info.route_ident .. "." .. info.decl .. "(try mt.ctx." .. info.route_ident .. ".from(raw_ctx));"
    else
      lines[#lines + 1] = "    if (comptime std.mem.eql(u8, route_id, " .. helpers.zig_string(info.route_id) .. ")) return handlers." .. info.symbol .. "(try mt.ctx." .. info.route_ident .. ".from(raw_ctx));"
    end
  end
  lines[#lines + 1] = "    @compileError(\"missing generated route handler binding for route `\" ++ route_id ++ \"`\");"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {"
  lines[#lines + 1] = "    _ = id;"
  lines[#lines + 1] = "    return validators.none(value);"
  lines[#lines + 1] = "}"
  table.insert(lines, 1, "const std = @import(\"std\");")
  helpers.write_file(output .. "/graph_bindings.zig", table.concat(lines, "\n") .. "\n")
  local zig_file_lines = {}
  local root = helpers.project_root_from_output(output)
  for _, info in ipairs(route_infos) do
    if info.kind == "zig_file" then
      local file_path = tostring(info.file_path or "")
      if not file_path:match("^/") then file_path = helpers.path_join(root, file_path) end
      zig_file_lines[#zig_file_lines + 1] = "meteorite_zig_file_" .. info.route_ident .. "\t" .. file_path
    end
  end
  helpers.write_file(output .. "/zig-files.tsv", table.concat(zig_file_lines, "\n") .. (#zig_file_lines > 0 and "\n" or ""))
end

function graph_emit.pattern_class_map(pattern)
  return pattern.class_map or {}, pattern.class_count or 1
end

function graph_emit.pattern_module_name(pattern)
  return "pattern_" .. helpers.zig_ident(pattern.id)
end

function graph_emit.pattern_module_content(pattern)
  local lines = {}
  local class_map, class_count = graph_emit.pattern_class_map(pattern)
  local state_count = pattern.dfa_states
  local dead = pattern.dead_state
  local start = pattern.start_state
  local max = pattern.max_len
  local transitions = pattern.transitions
  local accept = pattern.accept
  lines[#lines + 1] = "const class_map = [_]u8{"
  local row = "    "
  for i, class in ipairs(class_map) do
    row = row .. tostring(class) .. ", "
    if i % 32 == 0 then lines[#lines + 1] = row; row = "    " end
  end
  if row ~= "    " then lines[#lines + 1] = row end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = "const transitions = [_]u16{"
  for state = 1, state_count do
    local items = {}
    for class = 1, class_count do
      local idx = (state - 1) * class_count + class
      items[#items + 1] = tostring(transitions[idx] or dead)
    end
    lines[#lines + 1] = "    " .. table.concat(items, ", ") .. ","
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = "const accept = [_]bool{"
  local accepts = {}
  for state = 1, state_count do accepts[#accepts + 1] = accept[state] and "true" or "false" end
  lines[#lines + 1] = "    " .. table.concat(accepts, ", ") .. ","
  lines[#lines + 1] = "};"
  lines[#lines + 1] = "pub const matcher = @import(\"meteorite_pattern\").DfaMatcher(.{ .class_map = &class_map, .transition_table = &transitions, .accept_table = &accept, .class_count = " .. class_count .. ", .start_state = " .. (start - 1) .. ", .dead_state = " .. (dead - 1) .. ", .max_input_bytes = " .. max .. " });"
  return table.concat(lines, "\n") .. "\n"
end

--- Emit pattern/*.zig DFA modules.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_emit.emit_pattern_modules(graph, output)
  local dir = output .. "/patterns"
  fs.mkdir_p(dir)
  for _, pattern in ipairs(graph.patterns) do
    helpers.write_file(dir .. "/" .. graph_emit.pattern_module_name(pattern) .. ".zig", graph_emit.pattern_module_content(pattern))
  end
end

function graph_emit.emit_pattern_tables(graph, lines, output)
  graph_emit.emit_pattern_modules(graph, output)
  lines[#lines + 1] = "pub const PatternId = enum { none" .. (#graph.patterns > 0 and "," or "")
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "    " .. helpers.zig_ident(pattern.id) .. "," end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  for _, pattern in ipairs(graph.patterns) do
    lines[#lines + 1] = "const " .. graph_emit.pattern_module_name(pattern) .. " = @import(\"patterns/" .. graph_emit.pattern_module_name(pattern) .. ".zig\");"
  end
  if #graph.patterns > 0 then lines[#lines + 1] = "" end
  lines[#lines + 1] = "pub const patterns = struct {"
  lines[#lines + 1] = "    pub fn match(comptime id: PatternId, input: []const u8) bool {"
  if #graph.patterns == 0 then lines[#lines + 1] = "        _ = input;" end
  lines[#lines + 1] = "        return switch (id) {"
  lines[#lines + 1] = "            .none => true,"
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "            ." .. helpers.zig_ident(pattern.id) .. " => " .. graph_emit.pattern_module_name(pattern) .. ".matcher.match(input)," end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "    }"
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
end


function graph_emit.is_array_table(value)
  if type(value) ~= "table" then return false end
  local keys = {}
  for k, _ in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
  end)
  for i, k in ipairs(keys) do
    if k ~= i then return false end
  end
  return #keys > 0
end


function graph_emit.is_array_table(value)
  if type(value) ~= "table" then return false end
  local keys = {}
  for k, _ in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
  end)
  for i, k in ipairs(keys) do
    if k ~= i then return false end
  end
  return #keys > 0
end

function graph_emit.capability_value_to_zig(value, indent)
  indent = indent or ""
  local t = type(value)
  if t == "string" then return helpers.zig_string(value) end
  if t == "number" then
    if value == math.floor(value) then
      return string.format("%d", value)
    end
    return string.format("%g", value)
  end
  if t == "boolean" then return value and "true" or "false" end
  if t ~= "table" then return "null" end
  if graph_emit.is_array_table(value) then
    local items = {}
    for _, v in ipairs(value) do
      items[#items + 1] = graph_emit.capability_value_to_zig(v, indent .. "    ")
    end
    return ".{ " .. table.concat(items, ", ") .. " }"
  end
  local keys = {}
  for k, _ in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  local fields = {}
  for _, k in ipairs(keys) do
    fields[#fields + 1] = "." .. helpers.zig_ident(k) .. " = " .. graph_emit.capability_value_to_zig(value[k], indent .. "    ")
  end
  return ".{" .. "\n" .. indent .. "    " .. table.concat(fields, "," .. "\n" .. indent .. "    ") .. "\n" .. indent .. "}"
end

function graph_emit.emit_capabilities(graph, lines)
  lines[#lines + 1] = "pub const capabilities = struct {"
  local kinds = { "http", "auth", "zig" }
  for _, kind in ipairs(kinds) do
    lines[#lines + 1] = "    pub const " .. helpers.zig_ident(kind) .. " = struct {"
    local configs = (graph.capabilities or {})[kind] or {}
    local names = {}
    for name, _ in pairs(configs) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      lines[#lines + 1] = "        pub const " .. helpers.zig_ident(name) .. " = " .. graph_emit.capability_value_to_zig(configs[name], "        ") .. ";"
    end
    lines[#lines + 1] = "    };"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
end

function graph_emit.route_module_name(route)
  return "route_" .. helpers.zig_ident(route.method .. "_" .. route.raw_path .. "_" .. route.id)
end

function graph_emit.param_pattern_zig(param)
  local pattern = "null"
  local kind = param.type or param.kind or "string"
  if param.kind == "pattern" then
    pattern = "." .. helpers.zig_ident(param.id)
    kind = "pattern"
  elseif param.pattern_id then
    pattern = "." .. helpers.zig_ident(param.pattern_id)
  end
  return kind, pattern
end

function graph_emit.route_handler_zig(route)
  local handler = ".{ .inline_lua = .{ .id = " .. helpers.zig_string(route.id) .. ", .chunk_path = " .. helpers.zig_string((route.handler.lifted or {}).chunk_path or "") .. ", .source_file = " .. helpers.zig_string((route.handler.lifted or {}).source_file or tostring(route.source.file)) .. ", .source_line = " .. tostring((route.handler.lifted or {}).source_line or route.source.line or 0) .. ", .source_column = " .. tostring((route.handler.lifted or {}).source_column or route.source.column or 1) .. " } }"
  if route.handler.kind == "zig" then handler = ".{ .zig_symbol = .{ .id = ." .. route.handler.symbol .. ", .symbol = " .. helpers.zig_string(route.handler.import or route.handler.symbol) .. " } }" end
  if route.handler.kind == "zig_file" then handler = ".{ .zig_file = .{ .id = " .. helpers.zig_string(route.handler.symbol) .. ", .path = " .. helpers.zig_string(route.handler.path) .. ", .decl = " .. helpers.zig_string(route.handler.decl or "handle") .. " } }" end
  if route.handler.kind == "lua" then handler = ".{ .lua_file = .{ .id = " .. helpers.zig_string(route.id) .. ", .path = " .. helpers.zig_string(route.handler.path or route.handler.module) .. " } }" end
  if route.handler.kind == "file" then
    handler = ".{ .file = .{ .artifact_path = " .. helpers.zig_string(route.handler.artifact_path or route.handler.path) .. ", .content_type = " .. helpers.zig_string(route.handler.content_type or "application/octet-stream") .. ", .content_length = " .. tostring(route.handler.content_length or 0) .. ", .etag = " .. helpers.zig_string(route.handler.etag or "") .. ", .cache_control = " .. helpers.zig_string(route.handler.cache_control or route.handler.cache or "no-cache") .. ", .only_accept = " .. (route.handler.only_accept and helpers.zig_string(route.handler.only_accept) or "null") .. " } }"
  end
  if route.handler.kind == "dir" then
    handler = ".{ .dir = .{ .mount_root = " .. helpers.zig_string("") .. ", .param_name = " .. helpers.zig_string(route.handler.param) .. ", .manifest = &data.static_assets, .cache_control = " .. helpers.zig_string(route.handler.cache_control or route.handler.cache or "no-cache") .. ", .immutable = " .. tostring(route.handler.immutable == true) .. " } }"
  end
  return handler
end

function graph_emit.route_runtime_zig(route)
  return ".{ .requires_lua = " .. tostring(route.runtime.requires_lua) .. ", .requires_http = " .. tostring(route.runtime.requires_http) .. ", .requires_auth = " .. tostring(route.runtime.requires_auth) .. ", .requires_zig_capability = " .. tostring(route.runtime.requires_zig_capability) .. ", .execution_class = ." .. route.runtime.execution_class .. " }"
end

function graph_emit.route_execution_zig(route)
  return ".{ .class = ." .. route.execution.class .. ", .may_block = " .. tostring(route.execution.may_block) .. ", .requires_lua = " .. tostring(route.execution.requires_lua) .. ", .requires_worker_pool = " .. tostring(route.execution.requires_worker_pool) .. " }"
end

function graph_emit.route_memory_zig(route)
  local memory = route.memory
  return ".{ .profile_name = " .. helpers.zig_string(memory.profile_name) .. ", .request_arena_bytes = " .. memory.request_arena_bytes .. ", .max_body_bytes = " .. memory.max_body_bytes .. ", .max_uri_bytes = " .. memory.max_uri_bytes .. ", .max_path_bytes = " .. memory.max_path_bytes .. ", .max_query_bytes = " .. memory.max_query_bytes .. ", .max_query_pairs = " .. memory.max_query_pairs .. ", .max_path_segments = " .. memory.max_path_segments .. ", .max_response_bytes = " .. memory.max_response_bytes .. ", .max_capability_response_bytes = " .. memory.max_capability_response_bytes .. ", .lua_heap_bytes = " .. memory.lua_heap_bytes .. ", .estimated_peak_bytes = " .. memory.estimated_peak_bytes .. " }"
end

function graph_emit.route_scope_zig(scope)
  local normalized = helpers.normalized_scope(scope)
  return ".{ .id = " .. helpers.zig_string(normalized.id) .. ", .parent = " .. helpers.zig_string(normalized.parent) .. ", .path_prefix = " .. helpers.zig_string(normalized.path_prefix) .. ", .chain = &data.scope_chain, .plugins = &data.scope_plugins, .context = &data.scope_context }"
end


function graph_emit.plugin_handler_zig(plugin)
  local handler = plugin.handler or {}
  if handler.kind == "inline_lua" then
    return ".{ .inline_lua = .{ .id = " .. helpers.zig_string(plugin.id) .. ", .chunk_path = " .. helpers.zig_string((handler.lifted or {}).chunk_path or "") .. ", .source_file = " .. helpers.zig_string((handler.lifted or {}).source_file or "") .. ", .source_line = " .. tostring((handler.lifted or {}).source_line or 0) .. ", .source_column = " .. tostring((handler.lifted or {}).source_column or 1) .. " } }"
  elseif handler.kind == "lua" then
    return ".{ .lua_file = .{ .id = " .. helpers.zig_string(plugin.id) .. ", .path = " .. helpers.zig_string(handler.path or handler.module) .. " } }"
  elseif handler.kind == "zig" then
    return ".{ .zig_symbol = .{ .id = ." .. handler.symbol .. ", .symbol = " .. helpers.zig_string(handler.import or handler.symbol) .. " } }"
  end
  return ".none"
end

function graph_emit.static_asset_zig(asset)
  return ".{ .request_path = " .. helpers.zig_string(asset.request_path or "")
    .. ", .artifact_path = " .. helpers.zig_string(asset.artifact_path or "")
    .. ", .content_type = " .. helpers.zig_string(asset.content_type or "application/octet-stream")
    .. ", .content_length = " .. tostring(asset.content_length or 0)
    .. ", .etag = " .. helpers.zig_string(asset.etag or "")
    .. ", .cache_control = " .. helpers.zig_string(asset.cache_control or "no-cache")
    .. ", .compressed_br_path = " .. (asset.compressed_br_path and helpers.zig_string(asset.compressed_br_path) or "null")
    .. ", .compressed_br_length = " .. tostring(asset.compressed_br_length or 0)
    .. ", .compressed_br_etag = " .. (asset.compressed_br_etag and helpers.zig_string(asset.compressed_br_etag) or "null")
    .. ", .compressed_gzip_path = " .. (asset.compressed_gzip_path and helpers.zig_string(asset.compressed_gzip_path) or "null")
    .. ", .compressed_gzip_length = " .. tostring(asset.compressed_gzip_length or 0)
    .. ", .compressed_gzip_etag = " .. (asset.compressed_gzip_etag and helpers.zig_string(asset.compressed_gzip_etag) or "null")
    .. " }"
end

function graph_emit.route_module_content(route)
  local lines = {
    "pub fn route(comptime graph: type) graph.Route {",
    "    const data = struct {",
    "        const segments = [_]graph.Segment{",
  }
  for _, segment in ipairs(route.path.segments) do
    if segment.kind == "literal" then lines[#lines + 1] = "            .{ .literal = " .. helpers.zig_string(segment.value) .. " },"
    elseif segment.catch_all then lines[#lines + 1] = "            .{ .catch_all_param = " .. helpers.zig_string(segment.name) .. " },"
    else lines[#lines + 1] = "            .{ .param = " .. helpers.zig_string(segment.name) .. " }," end
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const query = [_]graph.ParamSpec{"
  for _, query in ipairs(route.query or {}) do
    local kind, pattern = graph_emit.param_pattern_zig(query)
    lines[#lines + 1] = "            .{ .name = " .. helpers.zig_string(query.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(query.max_len or 0) .. ", .exact_len = " .. tostring(query.exact_len or 0) .. ", .optional = " .. tostring(query.optional == true) .. ", .pattern = " .. pattern .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const params = [_]graph.ParamSpec{"
  for _, param in ipairs(route.params) do
    local kind, pattern = graph_emit.param_pattern_zig(param)
    lines[#lines + 1] = "            .{ .name = " .. helpers.zig_string(param.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(param.max_len or 0) .. ", .exact_len = " .. tostring(param.exact_len or 0) .. ", .optional = " .. tostring(param.optional == true) .. ", .pattern = " .. pattern .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const capabilities = [_]graph.CapabilityRef{"
  for _, ref in ipairs(route.capabilities or {}) do
    lines[#lines + 1] = "            .{ ." .. ref.kind .. " = " .. helpers.zig_string(ref.name) .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const static_assets = [_]graph.StaticAsset{"
  for _, asset in ipairs((route.handler and route.handler.manifest) or {}) do
    lines[#lines + 1] = "            " .. graph_emit.static_asset_zig(asset) .. ","
  end
  lines[#lines + 1] = "        };"
  local scope = helpers.normalized_scope(route.scope)
  lines[#lines + 1] = "        const scope_chain = [_]graph.ScopeRef{"
  for _, item in ipairs(scope.chain) do
    lines[#lines + 1] = "            .{ .id = " .. helpers.zig_string(item.id) .. ", .path_prefix = " .. helpers.zig_string(item.path_prefix) .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const scope_plugins = [_][]const u8{"
  for _, plugin in ipairs(scope.plugins) do
    lines[#lines + 1] = "            " .. helpers.zig_string(plugin) .. ","
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "        const scope_context = [_]graph.ScopeContextRef{"
  for _, item in ipairs(scope.context) do
    lines[#lines + 1] = "            .{ .key = " .. helpers.zig_string(item.key) .. ", .value = " .. helpers.zig_string(item.value) .. " },"
  end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "    };"
  local scope_zig = graph_emit.route_scope_zig(route.scope)
  lines[#lines + 1] = "    return .{ .id = " .. helpers.zig_string(route.id) .. ", .method = ." .. route.method .. ", .raw_path = " .. helpers.zig_string(route.raw_path) .. ", .path = &data.segments, .params = &data.params, .query = &data.query, .memory = " .. graph_emit.route_memory_zig(route) .. ", .max_body_bytes = " .. route.memory.max_body_bytes .. ", .request_arena_bytes = " .. route.memory.request_arena_bytes .. ", .handler = " .. graph_emit.route_handler_zig(route) .. ", .runtime = " .. graph_emit.route_runtime_zig(route) .. ", .execution = " .. graph_emit.route_execution_zig(route) .. ", .capabilities = &data.capabilities, .scope = " .. scope_zig .. " };"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

--- Emit individual route/*.zig modules.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_emit.emit_route_modules(graph, output)
  local dir = output .. "/routes"
  fs.mkdir_p(dir)
  for _, route in ipairs(graph.routes) do
    helpers.write_file(dir .. "/" .. graph_emit.route_module_name(route) .. ".zig", graph_emit.route_module_content(route))
  end
end

--- Emit the main graph.zig file.
---@param graph table  Normalized route graph
---@param output string  Output directory
function graph_emit.emit_graph_zig(graph, output)
  local max_arena = 0
  local max_uri, max_path, max_query, max_query_pairs, max_path_segments = 0, 0, 0, 0, 0
  for _, route in ipairs(graph.routes) do
    local memory = route.memory
    if memory.request_arena_bytes > max_arena then max_arena = memory.request_arena_bytes end
    if memory.max_uri_bytes > max_uri then max_uri = memory.max_uri_bytes end
    if memory.max_path_bytes > max_path then max_path = memory.max_path_bytes end
    if memory.max_query_bytes > max_query then max_query = memory.max_query_bytes end
    if memory.max_query_pairs > max_query_pairs then max_query_pairs = memory.max_query_pairs end
    if memory.max_path_segments > max_path_segments then max_path_segments = memory.max_path_segments end
  end
  local lines = {
    "pub const bindings = @import(\"graph_bindings.zig\");",
    "const std = @import(\"std\");",
    "",
    "pub const ctx = @import(\"meteorite_ctx\").ctx;",
    "",
    "pub const max_request_arena_bytes = " .. tostring(max_arena) .. ";",
    "pub const max_uri_bytes = " .. tostring(max_uri) .. ";",
    "pub const max_path_bytes = " .. tostring(max_path) .. ";",
    "pub const max_query_bytes = " .. tostring(max_query) .. ";",
    "pub const max_query_pairs = " .. tostring(max_query_pairs) .. ";",
    "pub const max_path_segments = " .. tostring(max_path_segments) .. ";",
    "pub const Method = enum { GET, HEAD, POST, PUT, PATCH, DELETE, OTHER };",
    "pub const Segment = union(enum) { literal: []const u8, param: []const u8, catch_all_param: []const u8 };",
    "pub const ZigSymbolHandler = struct { id: bindings.HandlerId, symbol: []const u8 };",
    "pub const ZigFileHandler = struct { id: []const u8, path: []const u8, decl: []const u8 = \"handle\" };",
    "pub const LuaFileHandler = struct { id: []const u8, path: []const u8 };",
    "pub const InlineLuaHandler = struct { id: []const u8, chunk_path: []const u8, source_file: []const u8, source_line: u32, source_column: u32 };",
    "pub const FileHandler = struct { artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, only_accept: ?[]const u8 = null };",
    "pub const StaticAsset = struct { request_path: []const u8, artifact_path: []const u8, content_type: []const u8, content_length: u64, etag: []const u8, cache_control: []const u8, compressed_br_path: ?[]const u8 = null, compressed_br_length: u64 = 0, compressed_br_etag: ?[]const u8 = null, compressed_gzip_path: ?[]const u8 = null, compressed_gzip_length: u64 = 0, compressed_gzip_etag: ?[]const u8 = null };",
    "pub const DirHandler = struct { mount_root: []const u8, param_name: []const u8, manifest: []const StaticAsset, cache_control: []const u8, immutable: bool = false };",
    "pub const Handler = union(enum) { zig_symbol: ZigSymbolHandler, zig_file: ZigFileHandler, lua_file: LuaFileHandler, inline_lua: InlineLuaHandler, file: FileHandler, dir: DirHandler };",
    "pub const ExecutionClass = enum { default, lua, blocking_io, cpu };",
    "pub const RouteRuntime = struct { requires_lua: bool = false, requires_http: bool = false, requires_auth: bool = false, requires_zig_capability: bool = false, execution_class: ExecutionClass = .default };",
    "pub const RouteExecution = struct { class: ExecutionClass = .default, may_block: bool = false, requires_lua: bool = false, requires_worker_pool: bool = false };",
    "pub const CapabilityRef = union(enum) { http: []const u8, auth: []const u8, zig: []const u8, lua: []const u8, worker: []const u8 };",
    "pub const WorkerStrategy = enum { auto, single_thread, io_plus_workers, per_core, pinned_appliance };",
    "pub const LuaStateStrategy = enum { single_locked, per_worker };",
    "pub const ThreadCount = union(enum) { auto, fixed: u16 };",
    "pub const RuntimeWorkers = struct { strategy: WorkerStrategy = .auto, io_threads: ThreadCount = .auto, worker_threads: ThreadCount = .auto, lua_state: LuaStateStrategy = .single_locked };",
    "pub const runtime_workers = RuntimeWorkers{};",
    "pub const RouteMemory = struct { profile_name: []const u8, request_arena_bytes: usize, max_body_bytes: usize, max_uri_bytes: usize, max_path_bytes: usize, max_query_bytes: usize, max_query_pairs: usize, max_path_segments: usize, max_response_bytes: usize, max_capability_response_bytes: usize, lua_heap_bytes: usize, estimated_peak_bytes: usize };",
    "pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, email, token, bool, pattern };",
    "pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, optional: bool = false, pattern: ?PatternId = null };",
    "pub const ScopeRef = struct { id: []const u8, path_prefix: []const u8 };",
    "pub const ScopeContextRef = struct { key: []const u8, value: []const u8 };",
    "pub const RouteScope = struct { id: []const u8 = \"root\", parent: []const u8 = \"\", path_prefix: []const u8 = \"\", chain: []const ScopeRef = &.{}, plugins: []const []const u8 = &.{}, context: []const ScopeContextRef = &.{} };",
    "pub const PluginHandler = union(enum) { inline_lua: InlineLuaHandler, lua_file: LuaFileHandler, zig_symbol: ZigSymbolHandler, none };",
    "pub const PluginDescriptor = struct { id: []const u8, kind: []const u8, handler: PluginHandler = .none };",
    "pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, query: []const ParamSpec, memory: RouteMemory, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler, runtime: RouteRuntime = .{}, execution: RouteExecution = .{}, capabilities: []const CapabilityRef = &.{}, scope: RouteScope = .{} };",
    "",
  }
  graph_emit.emit_pattern_tables(graph, lines, output)

    graph_emit.emit_capabilities(graph, lines)

  graph_emit.emit_route_modules(graph, output)
  for _, route in ipairs(graph.routes) do
    lines[#lines + 1] = "const " .. graph_emit.route_module_name(route) .. " = @import(\"routes/" .. graph_emit.route_module_name(route) .. ".zig\");"
  end
  lines[#lines + 1] = ""

  if #graph.plugins > 0 then
    lines[#lines + 1] = "pub const plugins = [_]PluginDescriptor{"
    for _, plugin in ipairs(graph.plugins) do
      lines[#lines + 1] = "    .{ .id = " .. helpers.zig_string(plugin.id) .. ", .kind = " .. helpers.zig_string(plugin.kind) .. ", .handler = " .. graph_emit.plugin_handler_zig(plugin) .. " },"
    end
    lines[#lines + 1] = "};"
  else
    lines[#lines + 1] = "pub const plugins = [_]PluginDescriptor{};"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub fn pluginById(comptime id: []const u8) ?PluginDescriptor {"
  lines[#lines + 1] = "    inline for (plugins) |p| { if (std.mem.eql(u8, p.id, id)) return p; }"
  lines[#lines + 1] = "    return null;"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "pub const routes = [_]Route{"
  for _, route in ipairs(graph.routes) do
    lines[#lines + 1] = "    " .. graph_emit.route_module_name(route) .. ".route(@This()),"
  end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  local method_buckets = { GET = {}, HEAD = {}, POST = {}, PUT = {}, PATCH = {}, DELETE = {}, OTHER = {} }
  for i, route in ipairs(graph.routes) do method_buckets[route.method][#method_buckets[route.method] + 1] = i - 1 end
  local explicit_head = {}
  for _, route in ipairs(graph.routes) do
    if route.method == "HEAD" then explicit_head[route.raw_path] = true end
  end
  for i, route in ipairs(graph.routes) do
    if route.method == "GET" and (route.handler.kind == "file" or route.handler.kind == "dir") and not explicit_head[route.raw_path] then
      method_buckets.HEAD[#method_buckets.HEAD + 1] = i - 1
    end
  end
  local method_names = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OTHER" }
  for _, method in ipairs(method_names) do
    lines[#lines + 1] = "pub const " .. method:lower() .. "_routes = [_]Route{"
    for _, route_index in ipairs(method_buckets[method]) do
      lines[#lines + 1] = "    routes[" .. tostring(route_index) .. "],"
    end
    lines[#lines + 1] = "};"
  end
  lines[#lines + 1] = ""
  helpers.write_file(output .. "/graph.zig", table.concat(lines, "\n"))
end

return graph_emit
