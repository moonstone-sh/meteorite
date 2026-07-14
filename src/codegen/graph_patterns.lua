--- Zig pattern DFA module emission.

local helpers = require("codegen.helpers")
local fs = require("utils.fs")

local graph_patterns = {}

function graph_patterns.pattern_class_map(pattern)
  return pattern.class_map or {}, pattern.class_count or 1
end

function graph_patterns.pattern_module_name(pattern)
  return "pattern_" .. helpers.zig_ident(pattern.id)
end

function graph_patterns.pattern_module_content(pattern)
  local lines = {}
  local class_map, class_count = graph_patterns.pattern_class_map(pattern)
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

function graph_patterns.emit_pattern_modules(graph, output)
  local dir = output .. "/patterns"
  fs.mkdir_p(dir)
  for _, pattern in ipairs(graph.patterns) do
    helpers.write_file(dir .. "/" .. graph_patterns.pattern_module_name(pattern) .. ".zig", graph_patterns.pattern_module_content(pattern))
  end
end

function graph_patterns.emit_pattern_tables(graph, lines, output)
  graph_patterns.emit_pattern_modules(graph, output)
  lines[#lines + 1] = "pub const PatternId = enum { none" .. (#graph.patterns > 0 and "," or "")
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "    " .. helpers.zig_ident(pattern.id) .. "," end
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
  for _, pattern in ipairs(graph.patterns) do
    lines[#lines + 1] = "const " .. graph_patterns.pattern_module_name(pattern) .. " = @import(\"patterns/" .. graph_patterns.pattern_module_name(pattern) .. ".zig\");"
  end
  if #graph.patterns > 0 then lines[#lines + 1] = "" end
  lines[#lines + 1] = "pub const patterns = struct {"
  lines[#lines + 1] = "    pub fn match(comptime id: PatternId, input: []const u8) bool {"
  if #graph.patterns == 0 then lines[#lines + 1] = "        _ = input;" end
  lines[#lines + 1] = "        return switch (id) {"
  lines[#lines + 1] = "            .none => true,"
  for _, pattern in ipairs(graph.patterns) do lines[#lines + 1] = "            ." .. helpers.zig_ident(pattern.id) .. " => " .. graph_patterns.pattern_module_name(pattern) .. ".matcher.match(input)," end
  lines[#lines + 1] = "        };"
  lines[#lines + 1] = "    }"
  lines[#lines + 1] = "};"
  lines[#lines + 1] = ""
end

return graph_patterns
