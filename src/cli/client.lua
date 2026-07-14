local client = {}

local function usage()
  return [[Meteorite client

Usage:
  meteorite client lua [input] [output]

Examples:
  meteorite client lua src/main.lua .meteorite/client.lua]]
end

local function write_file(path, content)
  local dir = path:match("^(.*[/\\])")
  if dir and dir ~= "" then os.execute("mkdir -p " .. string.format("%q", dir)) end
  local file, err = io.open(path, "wb")
  if not file then error(err) end
  file:write(content)
  file:close()
end

local function load_graph(input)
  _G.METEORITE_BUILD_MODE = "dev"
  local input_dir = input:match("^(.*[/\\])") or ""
  if input_dir ~= "" then
    package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path
  end
  local chunk, err = loadfile(input)
  if not chunk then error(err) end
  local app = chunk()
  if type(app) ~= "table" or not app.__meteorite_app then error(input .. " must return a Meteorite app") end
  return app:normalize({ mode = "dev" })
end

function client.run(args)
  local kind = args[2]
  if kind == "--help" or kind == "-h" or not kind then
    print(usage())
    return
  end
  if kind ~= "lua" then error("unknown client target `" .. tostring(kind) .. "`; expected lua") end
  local input = args[3] or "src/main.lua"
  local output = args[4] or ".meteorite/client.lua"
  local graph = load_graph(input)
  local source = require("codegen.lua_client").emit(graph, { module_name = "client" })
  write_file(output, source)
  print("Meteorite Lua client written: " .. output)
end

return client
