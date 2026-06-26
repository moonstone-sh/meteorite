local json = require("utils.json")

local M = {}

local function parse_headers(raw)
  local out = {}
  for line in tostring(raw):gmatch("[^\r\n]+") do
    local name, value = line:match("^([^:]+):%s*(.*)$")
    if name then out[name:lower()] = value end
  end
  return out
end

local function curl(method, url, headers, body)
  local tmp_headers = os.tmpname()
  local tmp_body = os.tmpname()
  local tmp_req_body = os.tmpname()
  local args = { "curl", "-s", "-i", "-X", method, "-D", tmp_headers, "-o", tmp_body }
  if body and body ~= "" then
    local f = io.open(tmp_req_body, "wb")
    if f then f:write(body); f:close() end
    table.insert(args, "-d")
    table.insert(args, "@" .. tmp_req_body)
  end
  for name, value in pairs(headers or {}) do
    table.insert(args, "-H")
    table.insert(args, name .. ": " .. tostring(value))
  end
  table.insert(args, url)

  local ok, status = pcall(function()
    local handle = io.popen(table.concat(args, " ") .. " 2>&1", "r")
    local output = handle and handle:read("*a") or ""
    if handle then handle:close() end
    return output
  end)

  os.remove(tmp_req_body)

  if not ok then
    os.remove(tmp_headers)
    os.remove(tmp_body)
    return { status = 0, headers = {}, body = { error = tostring(status) } }
  end

  local hf = io.open(tmp_headers, "rb")
  local raw_headers = hf and hf:read("*a") or ""
  if hf then hf:close() end
  os.remove(tmp_headers)

  local status_line = raw_headers:match("^HTTP/%d%.%d%s+(%d+)")
  local headers_map = parse_headers(raw_headers)

  local bf = io.open(tmp_body, "rb")
  local response_text = bf and bf:read("*a") or ""
  if bf then bf:close() end
  os.remove(tmp_body)

  local status_code = tonumber(status_line) or 0
  local parsed_body = response_text
  if (headers_map["content-type"] or ""):match("application/json") then
    local decoded, decode_err = json.decode(response_text)
    if decoded then parsed_body = decoded end
  end

  return { status = status_code, headers = headers_map, body = parsed_body }
end

function M.request(method, base_url, path, opts)
  opts = opts or {}
  local url = base_url .. path
  local headers = opts.headers or {}
  local body = ""
  if opts.body and type(opts.body) == "table" then
    body = json.encode(opts.body)
    headers["content-type"] = headers["content-type"] or "application/json"
  elseif opts.body then
    body = tostring(opts.body)
  end
  return curl(method, url, headers, body)
end

return M
