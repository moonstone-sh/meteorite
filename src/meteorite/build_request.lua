--- Explicit, invocation-scoped Meteorite build behavior.
--- Moonstone forwards script arguments; Ballad transports them; Meteorite owns
--- their meaning here. Project manifests do not provide behavior defaults.
local request = {}

request.valid_backends = {
  ipc_unixsocket = true,
  ipc_unixsocket_http = true,
  std_http = true,
  fast_http = true,
}

local function value_after(argv, index, flag)
  local value = argv[index + 1]
  if not value or value:sub(1, 2) == "--" then error(flag .. " requires a value") end
  return value
end

function request.assert_backend(value)
  if request.valid_backends[value] then return value end
  error("unsupported backend: " .. tostring(value) .. " (expected ipc_unixsocket, ipc_unixsocket_http, std_http, or fast_http)")
end

function request.parse(argv)
  local parsed = { extras = {}, unix_socket = {} }
  local index = 1
  while index <= #(argv or {}) do
    local argument = argv[index]
    if argument == "--mode" then
      parsed.mode = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-mode=") then
      parsed.mode = argument:match("^%-%-mode=(.*)$")
    elseif argument == "--backend" then
      parsed.backend = request.assert_backend(value_after(argv, index, argument)); index = index + 1
    elseif argument:match("^%-%-backend=") then
      parsed.backend = request.assert_backend(argument:match("^%-%-backend=(.*)$"))
    elseif argument:match("^%-Dbackend=") then
      parsed.backend = request.assert_backend(argument:match("^%-Dbackend=(.*)$"))
    elseif argument == "--hybrid-profile" then
      parsed.hybrid_profile = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-hybrid%-profile=") then
      parsed.hybrid_profile = argument:match("^%-%-hybrid%-profile=(.*)$")
    elseif argument == "--router-dispatch" then
      parsed.router_dispatch = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-router%-dispatch=") then
      parsed.router_dispatch = argument:match("^%-%-router%-dispatch=(.*)$")
    elseif argument == "--target" then
      parsed.target = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-target=") then
      parsed.target = argument:match("^%-%-target=(.*)$")
    elseif argument == "--unix-socket-path" then
      parsed.unix_socket.path = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-unix%-socket%-path=") then
      parsed.unix_socket.path = argument:match("^%-%-unix%-socket%-path=(.*)$")
    elseif argument == "--unix-socket-mode" then
      parsed.unix_socket.mode = value_after(argv, index, argument); index = index + 1
    elseif argument:match("^%-%-unix%-socket%-mode=") then
      parsed.unix_socket.mode = argument:match("^%-%-unix%-socket%-mode=(.*)$")
    elseif argument == "--unix-socket-unlink-stale" then
      parsed.unix_socket.unlink_stale = true
    elseif argument == "--no-unix-socket-unlink-stale" then
      parsed.unix_socket.unlink_stale = false
    elseif argument == "--require-peer-credentials" then
      parsed.require_peer_credentials = true
    elseif argument == "--no-require-peer-credentials" then
      parsed.require_peer_credentials = false
    elseif argument == "--peer-allow-uid" then
      parsed.peer_allow_uid = value_after(argv, index, argument); index = index + 1
    elseif argument == "--peer-allow-gid" then
      parsed.peer_allow_gid = value_after(argv, index, argument); index = index + 1
    else
      parsed.extras[#parsed.extras + 1] = argument
    end
    index = index + 1
  end
  return parsed
end

function request.require_behavior(parsed, subject)
  local missing = {}
  if not parsed.mode or parsed.mode == "" then missing[#missing + 1] = "--mode" end
  if not parsed.backend or parsed.backend == "" then missing[#missing + 1] = "--backend" end
  if #missing == 0 then return parsed end
  error((subject or "Meteorite build") .. " requires explicit " .. table.concat(missing, " and ")
    .. ". Run a generated Moonstone script, or pass --mode <mode> --backend <backend>.")
end

function request.to_options(parsed)
  request.require_behavior(parsed)
  return {
    mode = parsed.mode, backend = parsed.backend, hybrid_profile = parsed.hybrid_profile,
    router_dispatch = parsed.router_dispatch, target = parsed.target,
    unix_socket_path = parsed.unix_socket.path, unix_socket_mode = parsed.unix_socket.mode,
    unix_socket_unlink_stale = parsed.unix_socket.unlink_stale,
    require_peer_credentials = parsed.require_peer_credentials,
    peer_allow_uid = parsed.peer_allow_uid, peer_allow_gid = parsed.peer_allow_gid,
  }
end

function request.to_build_flags(parsed, quote)
  request.require_behavior(parsed)
  quote = quote or function(value) return value end
  local flags = { "-Dmode=" .. quote(parsed.mode), "-Dbackend=" .. quote(parsed.backend) }
  local function append(name, value)
    if value ~= nil and value ~= "" then flags[#flags + 1] = "-D" .. name .. "=" .. quote(tostring(value)) end
  end
  append("hybrid-profile", parsed.hybrid_profile)
  append("router-dispatch", parsed.router_dispatch)
  append("target", parsed.target)
  append("unix-socket-path", parsed.unix_socket.path)
  append("unix-socket-mode", parsed.unix_socket.mode)
  append("unix-socket-unlink-stale", parsed.unix_socket.unlink_stale)
  append("require-peer-credentials", parsed.require_peer_credentials)
  append("peer-allow-uid", parsed.peer_allow_uid)
  append("peer-allow-gid", parsed.peer_allow_gid)
  for _, extra in ipairs(parsed.extras) do flags[#flags + 1] = quote(extra) end
  return flags
end

function request.to_cli_args(parsed)
  request.require_behavior(parsed)
  local args = { "build", "--mode", parsed.mode, "--backend", parsed.backend }
  local function append(flag, value)
    if value ~= nil and value ~= "" then args[#args + 1] = flag; args[#args + 1] = tostring(value) end
  end
  append("--hybrid-profile", parsed.hybrid_profile)
  append("--router-dispatch", parsed.router_dispatch)
  append("--target", parsed.target)
  append("--unix-socket-path", parsed.unix_socket.path)
  append("--unix-socket-mode", parsed.unix_socket.mode)
  if parsed.unix_socket.unlink_stale == true then args[#args + 1] = "--unix-socket-unlink-stale" end
  if parsed.unix_socket.unlink_stale == false then args[#args + 1] = "--no-unix-socket-unlink-stale" end
  if parsed.require_peer_credentials == true then args[#args + 1] = "--require-peer-credentials" end
  if parsed.require_peer_credentials == false then args[#args + 1] = "--no-require-peer-credentials" end
  append("--peer-allow-uid", parsed.peer_allow_uid)
  append("--peer-allow-gid", parsed.peer_allow_gid)
  for _, extra in ipairs(parsed.extras) do args[#args + 1] = extra end
  return args
end

function request.metadata(parsed)
  local value = request.to_options(parsed)
  value.extras = parsed.extras
  return value
end

return request
