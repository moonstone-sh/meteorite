--- Zig handler binding emission for generated graphs.

local helpers = require("codegen.helpers")

local graph_bindings = {}

local function graph_nodes(graph)
  return graph.nodes or graph.routes or {}
end

function graph_bindings.sorted_handler_infos(routes)
  local infos, seen = {}, {}
  local function add(symbol, import, method, path, source)
    if not symbol or symbol == "" or seen[symbol] then return end
    seen[symbol] = true
    infos[#infos + 1] = {
      symbol = symbol,
      import = import or ("handlers." .. symbol),
      method = method,
      path = path,
      source = source,
    }
  end
  for _, route in ipairs(routes) do
    if route.handler.kind == "zig" then
      add(route.handler.symbol, route.handler.import, route.method, route.raw_path, route.source)
    end
    for _, stage in ipairs(route.pipeline or {}) do
      if stage.strat == "zig" and stage.symbol then
        add(stage.symbol, stage.import, route.method, route.raw_path, stage.source or route.source)
      end
    end
  end
  table.sort(infos, function(a, b) return a.symbol < b.symbol end)
  return infos
end

function graph_bindings.sorted_route_handler_infos(routes)
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

function graph_bindings.relative_path(from_dir, to_path)
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
  local index = 1
  while index <= #from_parts and index <= #to_parts and from_parts[index] == to_parts[index] do index = index + 1 end
  local out = {}
  for _ = index, #from_parts do out[#out + 1] = ".." end
  for item = index, #to_parts do out[#out + 1] = to_parts[item] end
  if #out == 0 then return "." end
  return table.concat(out, "/")
end

function graph_bindings.emit(graph, output)
  local infos = graph_bindings.sorted_handler_infos(graph_nodes(graph))
  local route_infos = graph_bindings.sorted_route_handler_infos(graph_nodes(graph))
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
  lines[#lines + 1] = "pub fn callHandlerBySymbol(comptime symbol: []const u8, ctx: anytype) !void {"
  if #infos == 0 then lines[#lines + 1] = "    _ = ctx;" end
  for _, info in ipairs(infos) do
    lines[#lines + 1] = "    if (comptime std.mem.eql(u8, symbol, " .. helpers.zig_string(info.symbol) .. ")) return handlers." .. info.symbol .. "(ctx);"
  end
  lines[#lines + 1] = "    @compileError(\"missing generated handler binding for symbol `\" ++ symbol ++ \"`\");"
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

return graph_bindings
