local json = require("utils.json")

local M = {}

local result_names = {
  [0] = "ok",
  [1] = "not_found",
  [2] = "method_not_allowed",
  [3] = "validation_error",
  [4] = "payload_too_large",
  [5] = "malformed_message",
  [6] = "unauthorized_peer",
  [7] = "busy",
  [8] = "timeout",
  [9] = "internal_error",
}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, data)
  local f, err = io.open(path, "wb")
  if not f then error("cannot write " .. path .. ": " .. tostring(err)) end
  f:write(data)
  f:close()
end

local function parse_metadata_arg(value)
  local key, metadata_value = tostring(value or ""):match("^([^=]+)=(.*)$")
  if not key or key == "" then error("--metadata must use key=value syntax") end
  return key, metadata_value or ""
end

local function slash_route_to_message(route)
  local value = tostring(route or "")
  value = value:gsub("^/+", ""):gsub("/+$", "")
  value = value:gsub("/+", ".")
  if value == "" then error("--route must not be empty") end
  return value
end

local function parse_ipc_args(argv)
  local opts = {
    action = argv[2] or "send",
    socket = nil,
    message = nil,
    route = nil,
    method = nil,
    path = nil,
    body = "",
    body_file = nil,
    content_type = nil,
    metadata = {},
    json = false,
  }
  local i = 3
  while i <= #argv do
    local value = argv[i]
    if value == "--socket" then
      i = i + 1; opts.socket = argv[i]
    elseif value and value:match("^%-%-socket=") then
      opts.socket = value:match("^%-%-socket=(.*)$")
    elseif value == "--message" then
      i = i + 1; opts.message = argv[i]
    elseif value and value:match("^%-%-message=") then
      opts.message = value:match("^%-%-message=(.*)$")
    elseif value == "--route" then
      i = i + 1; opts.route = argv[i]
    elseif value and value:match("^%-%-route=") then
      opts.route = value:match("^%-%-route=(.*)$")
    elseif value == "--method" then
      i = i + 1; opts.method = argv[i]
    elseif value and value:match("^%-%-method=") then
      opts.method = value:match("^%-%-method=(.*)$")
    elseif value == "--path" then
      i = i + 1; opts.path = argv[i]
    elseif value and value:match("^%-%-path=") then
      opts.path = value:match("^%-%-path=(.*)$")
    elseif value == "--body" then
      i = i + 1; opts.body = argv[i] or ""
    elseif value and value:match("^%-%-body=") then
      opts.body = value:match("^%-%-body=(.*)$") or ""
    elseif value == "--body-file" then
      i = i + 1; opts.body_file = argv[i]
    elseif value and value:match("^%-%-body%-file=") then
      opts.body_file = value:match("^%-%-body%-file=(.*)$")
    elseif value == "--content-type" then
      i = i + 1; opts.content_type = argv[i]
    elseif value and value:match("^%-%-content%-type=") then
      opts.content_type = value:match("^%-%-content%-type=(.*)$")
    elseif value == "--metadata" then
      i = i + 1
      local key, metadata_value = parse_metadata_arg(argv[i])
      opts.metadata[#opts.metadata + 1] = { key = key, value = metadata_value }
    elseif value and value:match("^%-%-metadata=") then
      local key, metadata_value = parse_metadata_arg(value:match("^%-%-metadata=(.*)$"))
      opts.metadata[#opts.metadata + 1] = { key = key, value = metadata_value }
    elseif value == "--json" then
      opts.json = true
    else
      error("unknown ipc argument: " .. tostring(value))
    end
    i = i + 1
  end
  if opts.action ~= "send" and opts.action ~= "stats" and opts.action ~= "inspect" then
    error("unknown ipc action: " .. tostring(opts.action))
  end
  if not opts.socket or opts.socket == "" then error("meteorite ipc requires --socket <path>") end
  if opts.body_file then opts.body = read_file(opts.body_file) or error("cannot read body file: " .. opts.body_file) end
  if opts.action == "stats" then
    opts.message = "meteorite.bench.stats"
    opts.json = true
  elseif opts.action == "inspect" then
    opts.message = "meteorite.bench.meta"
    opts.json = true
  elseif opts.message then
    -- exact native message
  elseif opts.route then
    opts.message = slash_route_to_message(opts.route)
  elseif opts.method and opts.path then
    opts.message = tostring(opts.method):upper() .. " " .. tostring(opts.path)
  else
    error("meteorite ipc send requires --message, --route, or --method with --path")
  end
  if opts.content_type then
    opts.metadata[#opts.metadata + 1] = { key = "content_type", value = opts.content_type }
  end
  return opts
end

local python_driver = [=[
import json
import socket
import struct
import sys

RESULT_NAMES = {
    0: "ok",
    1: "not_found",
    2: "method_not_allowed",
    3: "validation_error",
    4: "payload_too_large",
    5: "malformed_message",
    6: "unauthorized_peer",
    7: "busy",
    8: "timeout",
    9: "internal_error",
}

def recv_all(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RuntimeError("short read")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)

class ProtocolError(RuntimeError):
    pass

def metadata_wire(items):
    out = []
    for item in items:
        key = str(item.get("key", ""))
        value = str(item.get("value", ""))
        if not key or "\n" in key or "=" in key or "\n" in value:
            raise ValueError("invalid metadata key/value")
        out.append(f"{key}={value}\n")
    return "".join(out).encode()

def main():
    with open(sys.argv[1], "rb") as f:
        request = json.load(f)
    route = request["message"].encode()
    metadata = metadata_wire(request.get("metadata", []))
    body_value = request.get("body", "")
    if isinstance(body_value, str):
        body = body_value.encode()
    else:
        body = bytes(body_value or [])
    frame_len = 20 + len(route) + len(metadata) + len(body)
    frame = struct.pack("<IHHQHHI", frame_len, 0, 0, 1, len(route), len(metadata), len(body)) + route + metadata + body
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(request["socket"])
        client.sendall(frame)
        header = recv_all(client, 26)
        declared, version, flags, request_id, result, content_type_len, metadata_len, body_len = struct.unpack("<IHHQHHHI", header)
        if version != 0:
            raise ProtocolError(f"protocol mismatch: response version {version}")
        expected_declared = 22 + content_type_len + metadata_len + body_len
        if declared != expected_declared:
            raise ProtocolError(f"malformed response: declared length {declared}, expected {expected_declared}")
        payload = recv_all(client, content_type_len + metadata_len + body_len)
    content_type = payload[:content_type_len].decode(errors="replace")
    response_metadata = payload[content_type_len:content_type_len + metadata_len].decode(errors="replace")
    response_body = payload[content_type_len + metadata_len:].decode(errors="replace")
    response = {
        "format": "meteorite.ipc.response.v0",
        "request": {"message": request["message"]},
        "response": {
            "request_id": request_id,
            "result": result,
            "result_name": RESULT_NAMES.get(result, f"unknown:{result}"),
            "content_type": content_type,
            "metadata": response_metadata,
            "body": response_body,
        },
    }
    if request.get("json"):
        print(json.dumps(response, separators=(",", ":")))
    else:
        print(f"{response['response']['result_name']}\t{content_type}\t{response_body}")
    return 0 if result == 0 else 2

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProtocolError as exc:
        print(f"meteorite ipc protocol error: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except FileNotFoundError as exc:
        print(f"meteorite ipc socket connection failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except ConnectionRefusedError as exc:
        print(f"meteorite ipc socket connection failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except Exception as exc:
        print(f"meteorite ipc error: {exc}", file=sys.stderr)
        raise SystemExit(1)
]=]

function M.run(argv)
  local opts = parse_ipc_args(argv)
  local token = tostring(os.time()) .. "-" .. tostring(math.random(1000000, 9999999))
  local request_path = "/tmp/meteorite-ipc-request-" .. token .. ".json"
  local script_path = "/tmp/meteorite-ipc-client-" .. token .. ".py"
  write_file(request_path, json.encode(opts))
  write_file(script_path, python_driver)
  local code = os.execute("python3 " .. shell_quote(script_path) .. " " .. shell_quote(request_path))
  os.remove(request_path)
  os.remove(script_path)
  if code == true or code == 0 then return end
  if type(code) == "number" then os.exit(code) end
  os.exit(1)
end

return M
