local static = {}

local function mkdir_p(path)
  os.execute("mkdir -p " .. string.format("%q", path))
end

local function capture(command)
  local pipe = io.popen(command, "r")
  if not pipe then return "" end
  local out = pipe:read("*a") or ""
  pipe:close()
  return (out:gsub("%s+$", ""))
end

local function dirname(path)
  return tostring(path):match("^(.*)/[^/]*$") or "."
end

local function path_join(a, b)
  if a == "" or a == "." then return b end
  return a .. "/" .. b
end

local function shell_quote(path)
  return string.format("%q", tostring(path))
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function write_file(path, content)
  mkdir_p(dirname(path))
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
end

local function hash_text(text)
  local tmp = os.tmpname()
  write_file(tmp, text)
  local hash = capture("b3sum --no-names " .. shell_quote(tmp) .. " 2>/dev/null")
  os.remove(tmp)
  if hash ~= "" then return "b3:" .. hash end
  local h = 2166136261
  for i = 1, #text do h = (h + text:byte(i) * 16777619) % 4294967296 end
  return string.format("fnv32:%08x", h)
end

local function etag_for_text(text)
  return '"' .. hash_text(text) .. '"'
end

local function file_size(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size or 0
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function is_dir(path)
  local ok = os.execute("test -d " .. shell_quote(path) .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function copy_file(src, dst)
  mkdir_p(dirname(dst))
  local input, err = io.open(src, "rb")
  if not input then error("cannot read static file " .. src .. ": " .. tostring(err)) end
  local data = input:read("*a") or ""
  input:close()
  local output, werr = io.open(dst, "wb")
  if not output then error("cannot write static artifact " .. dst .. ": " .. tostring(werr)) end
  output:write(data)
  output:close()
end

function static.infer_content_type(path, overrides)
  local ext = tostring(path):match("%.([^./]+)$") or ""
  ext = ext:lower()
  if overrides and overrides[ext] then return overrides[ext] end
  local map = {
    html = "text/html; charset=utf-8",
    htm = "text/html; charset=utf-8",
    css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8",
    mjs = "application/javascript; charset=utf-8",
    json = "application/json; charset=utf-8",
    svg = "image/svg+xml",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    webp = "image/webp",
    wasm = "application/wasm",
    txt = "text/plain; charset=utf-8",
  }
  return map[ext] or "application/octet-stream"
end

local function static_artifact_path(output, route, relative)
  local route_id = tostring(route.id or route.raw_path):gsub("[^%w_.-]", "_")
  local rel = relative or (tostring(route.raw_path):gsub("[^%w_.-]", "_") .. ".asset")
  return output .. "/static/" .. route_id .. "/" .. rel, "static/" .. route_id .. "/" .. rel
end

local function scan_files(root)
  local links = capture("cd " .. shell_quote(root) .. " && find . -type l -print")
  if links ~= "" then
    error(table.concat({
      "static directory contains symlinks",
      "",
      "Directory:",
      "  " .. tostring(root),
      "",
      "Symlink:",
      "  " .. tostring((links:match("([^\n]+)") or links):gsub("^%./", "")),
      "",
      "Fix:",
      "  copy real files into the static root or remove the symlink",
    }, "\n"))
  end
  local out = capture("cd " .. shell_quote(root) .. " && find . -type f -print")
  local files = {}
  for line in (out .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      local rel = line:gsub("^%./", "")
      assert(not rel:find("%.%./", 1, true) and rel ~= "..", "invalid static file path: " .. rel)
      files[#files + 1] = rel
    end
  end
  table.sort(files)
  return files
end

function static.prepare_route(route, output, mode)
  local handler = route.handler
  if handler.kind == "file" then
    local source = handler.path
    if not file_exists(source) then
      error(table.concat({
        "static file not found",
        "",
        "Route:",
        "  " .. route.method .. " " .. route.raw_path,
        "",
        "File:",
        "  " .. tostring(source),
      }, "\n"))
    end
    local content = read_file(source) or ""
    local artifact, artifact_rel = static_artifact_path(output, route, source:match("([^/\\]+)$") or "file")
    if mode == "release-static" then copy_file(source, artifact) end
    handler.source_path = source
    handler.artifact_path = mode == "release-static" and artifact_rel or source
    handler.content_type = handler.content_type or static.infer_content_type(source)
    handler.content_length = file_size(source) or #content
    handler.etag = etag_for_text(content)
    handler.cache_control = handler.cache or "no-cache"
    handler.only_accept = handler.only and handler.only.accept or nil
  elseif handler.kind == "dir" then
    local root = handler.root
    if not is_dir(root) then
      error(table.concat({
        "static directory not found",
        "",
        "Route:",
        "  " .. route.method .. " " .. route.raw_path,
        "",
        "Directory:",
        "  " .. tostring(root),
      }, "\n"))
    end
    local assets = {}
    for _, rel in ipairs(scan_files(root)) do
      if not rel:match("%.br$") and not rel:match("%.gz$") then
        local source = path_join(root, rel)
        local content = read_file(source) or ""
        local artifact, artifact_rel = static_artifact_path(output, route, rel)
        if mode == "release-static" then copy_file(source, artifact) end
        local br_source = source .. ".br"
        local gz_source = source .. ".gz"
        local br_artifact, gz_artifact = nil, nil
        if handler.compressed and handler.compressed.br and file_exists(br_source) then
          br_artifact = mode == "release-static" and static_artifact_path(output, route, rel .. ".br") or br_source
          if mode == "release-static" then copy_file(br_source, br_artifact) end
        end
        if handler.compressed and handler.compressed.gzip and file_exists(gz_source) then
          gz_artifact = mode == "release-static" and static_artifact_path(output, route, rel .. ".gz") or gz_source
          if mode == "release-static" then copy_file(gz_source, gz_artifact) end
        end
        local _, br_rel = static_artifact_path(output, route, rel .. ".br")
        local _, gz_rel = static_artifact_path(output, route, rel .. ".gz")
        assets[#assets + 1] = {
          request_path = rel,
          artifact_path = mode == "release-static" and artifact_rel or artifact,
          content_type = static.infer_content_type(rel, handler.types),
          content_length = file_size(source) or #content,
          etag = etag_for_text(content),
          cache_control = handler.cache or "no-cache",
          compressed_br_path = br_artifact and (mode == "release-static" and br_rel or br_source) or nil,
          compressed_br_length = br_artifact and file_size(br_source) or nil,
          compressed_br_etag = br_artifact and etag_for_text(read_file(br_source) or "") or nil,
          compressed_gzip_path = gz_artifact and (mode == "release-static" and gz_rel or gz_source) or nil,
          compressed_gzip_length = gz_artifact and file_size(gz_source) or nil,
          compressed_gzip_etag = gz_artifact and etag_for_text(read_file(gz_source) or "") or nil,
        }
      end
    end
    handler.manifest = assets
    handler.cache_control = handler.cache or "no-cache"
  end
end

return static
