local invoke_command = {}

local function parse_header_arg(value)
  local name, header_value = tostring(value or ""):match("^([^:]+):%s*(.*)$")
  if not name or name == "" then error("invoke header must use 'Name: value' syntax") end
  return name, header_value or ""
end

local function parse_args(args)
  local opts = { input = "src/main.lua", method = "GET", path = "/", body = "", json = false, show_headers = false, headers = {} }
  local positional = {}
  local i = 2
  while i <= #args do
    local value = args[i]
    if value == "--json" then
      opts.json = true
    elseif value == "--headers" then
      opts.show_headers = true
    elseif value == "--header" or value == "-H" then
      i = i + 1
      local name, header_value = parse_header_arg(args[i])
      opts.headers[name] = header_value
    elseif value and value:match("^%-%-header=") then
      local name, header_value = parse_header_arg(value:match("^%-%-header=(.*)$"))
      opts.headers[name] = header_value
    elseif value == "--body" then
      i = i + 1
      opts.body = args[i] or ""
    elseif value and value:match("^%-%-body=") then
      opts.body = value:match("^%-%-body=(.*)$") or ""
    else
      positional[#positional + 1] = value
    end
    i = i + 1
  end
  opts.input = positional[1] or opts.input
  opts.method = positional[2] or opts.method
  opts.path = positional[3] or opts.path
  if positional[4] ~= nil then opts.body = positional[4] end
  return opts
end

local function print_json(opts, response)
  local json = require("utils.json")
  print(json.encode({
    format = "meteorite.invoke.v0",
    request = {
      method = opts.method,
      path = opts.path,
      headers = opts.headers,
    },
    response = {
      status = response.status,
      content_type = response.content_type or "",
      headers = response.headers or {},
      body = response.body or "",
    },
  }))
end

local function print_text(opts, response)
  io.write(tostring(response.status), "\t", response.content_type or "", "\t", response.body or "", "\n")
  if opts.show_headers then
    local response_headers = response.headers or {}
    local sorted_names = {}
    for name, _ in pairs(response_headers) do sorted_names[#sorted_names + 1] = name end
    table.sort(sorted_names)
    for _, name in ipairs(sorted_names) do
      io.write(name, ": ", tostring(response_headers[name]), "\n")
    end
  end
end

function invoke_command.run(args)
  local opts = parse_args(args)
  local app = require("cli.app_loader").load(opts.input, "dev")
  local response = require("cli.hybrid").invoke(app, {
    method = opts.method,
    path = opts.path,
    body = opts.body,
    headers = opts.headers,
  }, { mode = "dev" })
  if opts.json then
    print_json(opts, response)
  else
    print_text(opts, response)
  end
  return response
end

invoke_command.parse_args = parse_args

return invoke_command
