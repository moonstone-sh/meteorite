local zon = require("meteorite.zon")

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
  if route.handler.kind == "zig" then handler = { zig = route.handler.import or route.handler.symbol }
  elseif route.handler.kind == "lua" then handler = { lua = route.handler.module }
  else handler = { inline_lua = true } end
  return {
    id = route.id,
    method = method_enum(route.method),
    raw_path = route.raw_path,
    path = { segments = segments },
    query = query,
    handler = handler,
    memory = route.memory,
    source = route.source,
  }
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

local function zig_string(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local function zig_ident(value)
  local out = tostring(value):gsub("%W", "_")
  if out:match("^%d") then out = "_" .. out end
  return out
end

local function emit_bindings(graph, output)
  local infos = sorted_handler_infos(graph.routes)
  local lines = {
    "const handlers = @import(\"meteorite_handlers\");",
    "const validators = @import(\"meteorite_validators\");",
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
  lines[#lines + 1] = "pub fn callValidator(comptime id: ValidatorId, value: []const u8) bool {"
  lines[#lines + 1] = "    _ = id;"
  lines[#lines + 1] = "    return validators.none(value);"
  lines[#lines + 1] = "}"
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
    "",
    "pub const max_request_arena_bytes = " .. tostring(max_arena) .. ";",
    "pub const Method = enum { GET, POST, OTHER };",
    "pub const Segment = union(enum) { literal: []const u8, param: []const u8 };",
    "pub const Handler = union(enum) { zig: bindings.HandlerId, lua: []const u8, inline_lua: void };",
    "pub const ParamKind = enum { string, slug, u64, i32, uuid, hex, bool, pattern };",
    "pub const ParamSpec = struct { name: []const u8, kind: ParamKind = .string, max_len: usize = 0, exact_len: usize = 0, pattern: ?PatternId = null };",
    "pub const Route = struct { id: []const u8, method: Method, raw_path: []const u8, path: []const Segment, params: []const ParamSpec, max_body_bytes: usize, request_arena_bytes: usize, handler: Handler };",
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
      lines[#lines + 1] = "    .{ .name = " .. zig_string(param.name) .. ", .kind = ." .. kind .. ", .max_len = " .. tostring(param.max_len or 0) .. ", .exact_len = " .. tostring(param.exact_len or 0) .. ", .pattern = " .. pattern .. " },"
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
    local handler = ".{ .inline_lua = {} }"
    if route.handler.kind == "zig" then handler = ".{ .zig = ." .. route.handler.symbol .. " }" end
    if route.handler.kind == "lua" then handler = ".{ .lua = " .. zig_string(route.handler.module) .. " }" end
    lines[#lines + 1] = "    .{ .id = " .. zig_string(route.id) .. ", .method = ." .. route.method .. ", .raw_path = " .. zig_string(route.raw_path) .. ", .path = &route_" .. i .. "_segments, .params = &route_" .. i .. "_params, .max_body_bytes = " .. route.memory.max_body_bytes .. ", .request_arena_bytes = " .. route.memory.request_arena_bytes .. ", .handler = " .. handler .. " },"
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
  local routes_zon = {}
  for _, route in ipairs(graph.routes) do routes_zon[#routes_zon + 1] = route_to_zon(route) end
  local routes_text = zon.encode(routes_zon)
  local graph_hash = hash_text(routes_text)
  write_file(output .. "/routes.zon", routes_text)
  write_file(output .. "/manifest.zon", zon.encode({ format = "meteorite.graph.v0", meteorite_version = "0.1.0", graph_hash = graph_hash, mode = mode_enum(mode) }))
  write_file(output .. "/runtime.zon", zon.encode({ mode = mode_enum(mode), lua_runtime = mode ~= "release-static", backend = { __meteorite_enum = true, value = "std_http" } }))
  write_file(output .. "/capabilities.zon", zon.encode({ http = true, methods = { "GET", "POST" }, backend = "std.http" }))
  write_file(output .. "/graph_hash.txt", graph_hash .. "\n")
  emit_patterns_report(graph, output)
  emit_bindings(graph, output)
  emit_graph_zig(graph, output)
  return { graph = graph, graph_hash = graph_hash, output = output }
end

return emitter
