local lifter = {}

local function read_file(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local data = file:read("*a")
  file:close()
  return data
end

local function write_file(path, content)
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
end

local function mkdir_p(path)
  os.execute("mkdir -p " .. string.format("%q", path))
end

local function split_lines(text)
  local lines = {}
  text = text:gsub("\r\n", "\n")
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  return lines
end

local function token_at(text, index)
  local a, b, word = text:find("^([%a_][%w_]*)", index)
  if a then return word, b + 1 end
  return nil, index + 1
end

local function skip_short_string(text, index, quote)
  index = index + 1
  while index <= #text do
    local ch = text:sub(index, index)
    if ch == "\\" then index = index + 2
    elseif ch == quote then return index + 1
    else index = index + 1 end
  end
  return index
end

local function find_function_literal(text)
  local start = text:find("%f[%w_]function%f[^%w_]", 1)
  if not start then return nil, "could not find inline function literal" end
  local index = start
  local depth = 0
  while index <= #text do
    local ch = text:sub(index, index)
    local next2 = text:sub(index, index + 1)
    if ch == '"' or ch == "'" then
      index = skip_short_string(text, index, ch)
    elseif next2 == "--" then
      local newline = text:find("\n", index + 2, true)
      index = newline and (newline + 1) or (#text + 1)
    else
      local word, next_index = token_at(text, index)
      if word then
        if word == "function" or word == "if" or word == "do" or word == "for" or word == "while" then
          depth = depth + 1
        elseif word == "end" then
          depth = depth - 1
          if depth == 0 then
            return text:sub(start, next_index - 1)
          end
        end
        index = next_index
      else
        index = index + 1
      end
    end
  end
  return nil, "could not find matching end for inline function"
end

local function check_upvalues(route, fn)
  local index = 1
  while true do
    local name = debug.getupvalue(fn, index)
    if not name then return end
    if name ~= "_ENV" then
      error(table.concat({
        "inline Lua handler captures outer local `" .. tostring(name) .. "`",
        "",
        "route:",
        "  " .. route.method .. " " .. route.raw_path,
        "",
        "declared at:",
        "  " .. tostring(route.source.file) .. ":" .. tostring(route.source.line or 0) .. ":" .. tostring(route.source.column or 1),
        "",
        "hybrid inline handlers must be source-liftable.",
        "",
        "hint:",
        "  move requires and mutable values inside the handler body.",
      }, "\n"))
    end
    index = index + 1
  end
end

function lifter.lift(route, opts)
  opts = opts or {}
  local fn = assert(route.handler.value, "inline Lua handler is missing function value")
  check_upvalues(route, fn)
  local info = debug.getinfo(fn, "Slu") or {}
  local source = info.source or route.source.file
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  if source:sub(1, 1) ~= "/" and source:match("^%[") then
    error("inline Lua handler is not backed by a source file for " .. route.method .. " " .. route.raw_path)
  end
  local content, err = read_file(source)
  if not content then error("cannot read inline Lua source " .. tostring(source) .. ": " .. tostring(err)) end
  local lines = split_lines(content)
  local first = info.linedefined or route.source.line
  local last = info.lastlinedefined or first
  local region = {}
  for line = first, last do region[#region + 1] = lines[line] or "" end
  local literal, scan_err = find_function_literal(table.concat(region, "\n"))
  if not literal then
    error(table.concat({
      "inline Lua handler cannot be source-lifted with the restricted scanner",
      "",
      "route:",
      "  " .. route.method .. " " .. route.raw_path,
      "",
      "declared at:",
      "  " .. tostring(route.source.file) .. ":" .. tostring(route.source.line or 0) .. ":" .. tostring(route.source.column or 1),
      "",
      "reason:",
      "  " .. tostring(scan_err),
      "",
      "hint:",
      "  use a direct inline function literal or move the handler to m.lua(...).",
    }, "\n"))
  end
  local chunk = "return " .. literal .. "\n"
  local out_dir = opts.out_dir or ((opts.output or ".meteorite/graph/current") .. "/../../lua/inline")
  mkdir_p(out_dir)
  local chunk_path = out_dir .. "/" .. route.id .. ".lua"
  write_file(chunk_path, chunk)
  local loaded, load_err = loadfile(chunk_path)
  if not loaded then error("lifted inline Lua chunk failed to load: " .. tostring(load_err)) end
  local ok, result = pcall(loaded)
  if not ok or type(result) ~= "function" then error("lifted inline Lua chunk did not return a function: " .. chunk_path) end
  return {
    id = route.id,
    chunk_path = chunk_path,
    source_file = source,
    source_line = first,
    source_column = 1,
  }
end

function lifter.lift_plugin(plugin, opts)
  local fn = assert(plugin.execute, "plugin missing execute function")
  local info = debug.getinfo(fn, "Slu") or {}
  local source = info.source or "?"
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  local route = {
    id = plugin.id,
    method = "PLUGIN",
    raw_path = plugin.id,
    handler = { kind = "inline_lua", value = fn },
    source = { file = source, line = info.linedefined or 0, column = 1 },
  }
  local output = opts and opts.output or ".meteorite/graph/current"
  local plugin_opts = { output = output, out_dir = output .. "/../../lua/plugins" }
  return lifter.lift(route, plugin_opts)
end

return lifter
