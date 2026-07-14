local server_config = {}

server_config.valid_backends = {
  ipc_unixsocket = true,
  ipc_unixsocket_http = true,
  std_http = true,
  fast_http = true,
}

function server_config.assert_backend(value)
  if server_config.valid_backends[value] then return value end
  error("unsupported backend: " .. tostring(value) .. " (expected ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http)")
end

local function parse_scalar(value)
  value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  value = value:gsub("%s+#.*$", "")
  if value:sub(1, 1) == '"' and value:sub(-1) == '"' then return value:sub(2, -2) end
  if value == "true" then return true end
  if value == "false" then return false end
  return value
end

function server_config.parse(root, read_file)
  read_file = assert(read_file, "read_file required")
  local data = read_file((root or ".") .. "/moonstone.toml")
  local config = { unix_socket = {} }
  if not data then return config end
  local section = nil
  for line in data:gmatch("[^\n]+") do
    local header = line:match("^%s*%[([^%]]+)%]%s*$")
    if header then
      section = header
    elseif section == "server" or section == "server.unix_socket" or section == "server.ipc_unixsocket" or section == "server.ipc_unixsocket_http" then
      local key, value = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
      if key then
        key = key:gsub("-", "_")
        if section == "server" then
          config[key] = parse_scalar(value)
        else
          config.unix_socket[key] = parse_scalar(value)
        end
      end
    end
  end
  return config
end

return server_config
