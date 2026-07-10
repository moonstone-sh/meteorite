local static = {}

local fs = require("utils.fs")
local mkdir_p = fs.mkdir_p
local dirname = fs.dirname
local path_join = fs.join
local shell_quote = fs.shell_quote
local read_file = fs.read_file
local write_file = fs.write_file
local hash_text = fs.hash_text
local etag_for_text = fs.etag_for_text
local file_size = fs.file_size

local function file_exists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local is_dir = fs.is_dir

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
  local links_raw = fs.list_symlinks(root)
  local links = {}
  for _, l in ipairs(links_raw) do links[#links + 1] = l end
  if #links > 0 then
    local first_link = links[1]
    error(table.concat({
      "static directory contains symlinks",
      "",
      "Directory:",
      "  " .. tostring(root),
      "",
      "Symlink:",
      "  " .. tostring(first_link:gsub("^%./", "")),
      "",
      "Fix:",
      "  copy real files into the static root or remove the symlink",
    }, "\n"))
  end
  local files_raw = fs.list_files(root)
  local out = ""
  for _, f in ipairs(files_raw) do out = out .. "./" .. f .. "\n" end
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
    copy_file(source, artifact)
    handler.source_path = source
    handler.artifact_path = artifact_rel
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
        copy_file(source, artifact)
        local br_source = source .. ".br"
        local gz_source = source .. ".gz"
        local br_artifact_rel, gz_artifact_rel = nil, nil
        if handler.compressed and handler.compressed.br and file_exists(br_source) then
          local br_artifact
          br_artifact, br_artifact_rel = static_artifact_path(output, route, rel .. ".br")
          copy_file(br_source, br_artifact)
        end
        if handler.compressed and handler.compressed.gzip and file_exists(gz_source) then
          local gz_artifact
          gz_artifact, gz_artifact_rel = static_artifact_path(output, route, rel .. ".gz")
          copy_file(gz_source, gz_artifact)
        end
        assets[#assets + 1] = {
          request_path = rel,
          artifact_path = artifact_rel,
          content_type = static.infer_content_type(rel, handler.types),
          content_length = file_size(source) or #content,
          etag = etag_for_text(content),
          cache_control = handler.cache or "no-cache",
          compressed_br_path = br_artifact_rel,
          compressed_br_length = br_artifact_rel and file_size(br_source) or nil,
          compressed_br_etag = br_artifact_rel and etag_for_text(read_file(br_source) or "") or nil,
          compressed_gzip_path = gz_artifact_rel,
          compressed_gzip_length = gz_artifact_rel and file_size(gz_source) or nil,
          compressed_gzip_etag = gz_artifact_rel and etag_for_text(read_file(gz_source) or "") or nil,
        }
      end
    end
    handler.manifest = assets
    handler.cache_control = handler.cache or "no-cache"
  end
end

return static
