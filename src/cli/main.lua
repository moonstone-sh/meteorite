local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/cli/"
local module_root = script_dir:gsub("cli[/\\]$", "")
local install_root = module_root:gsub("src[/\\]$", "")
package.path = "src/?.lua;src/?/init.lua;" .. module_root .. "?.lua;" .. module_root .. "?/init.lua;" .. install_root .. "?.lua;" .. install_root .. "?/init.lua;" .. package.path

local cli_deps = require("cli.deps").new(source)
local command = arg[1] or "graph"
if command == "--" then
  table.remove(arg, 1)
  command = arg[1] or "graph"
end

local help_text = require("cli.help_text")

local function print_help(topic)
  topic = topic or "main"
  topic = ({ ["--help"] = "main", ["-h"] = "main", help = "main" })[topic] or topic
  local page = help_text[topic]
  if not page then
    io.stderr:write("unknown help topic: " .. tostring(topic) .. "\n\n")
    page = help_text.main
  end
  print(page)
end

if command == "help" or command == "--help" or command == "-h" then
  print_help(arg[2])
  return
end

local function init_project()
  return require("cli.init").run(arg, cli_deps.init(print_help))
end

local function build_project()
  return require("cli.build").run(arg, cli_deps.build(print_help))
end

local function dev_project()
  return require("cli.dev_command").run(cli_deps.dev())
end

local function doctor_project()
  return require("cli.doctor").run(cli_deps.doctor())
end

if (command == "graph" or command == "invoke" or command == "doctor" or command == "dev" or command == "client") and (arg[2] == "--help" or arg[2] == "-h") then
  print_help(command)
  return
end
if command == "init" then init_project(); return end
if command == "build" then build_project(); return end
if command == "dev" then dev_project(); return end
if command == "doctor" then doctor_project(); return end
if command == "client" then require("cli.client").run(arg); return end
if command == "ipc" then require("cli.ipc").run(arg); return end
if command == "routes" then require("cli.routes").run(arg); return end
if command == "graph" then require("cli.graph").run(arg, cli_deps.graph()); return end
if command == "invoke" then require("cli.invoke_command").run(arg); return end

error("unknown meteorite command: " .. tostring(command) .. "\n\nRun:\n  meteorite help")
