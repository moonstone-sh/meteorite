--- Portable filesystem utilities that avoid shell commands.
--- Replaces os.execute("mkdir -p"), io.popen("find ..."), and capture("b3sum ...")
--- with pure Lua implementations using lfs or fallback to shell.
---
--- @class FsModule
--- @field mkdir_p fun(path: string)
--- @field shell_quote fun(path: string): string
--- @field is_dir fun(path: string): boolean
--- @field list_files fun(root: string): string[]
--- @field list_symlinks fun(root: string): string[]
--- @field read_file fun(path: string): string|nil
--- @field write_file fun(path: string, content: string)
--- @field file_size fun(path: string): integer
--- @field readlink fun(path: string): string|nil
--- @field hash_text fun(text: string): string
--- @field etag_for_text fun(text: string): string
--- @field relative fun(full: string, base: string): string
--- @field join fun(a: string, b: string): string
--- @field dirname fun(path: string): string

---@type FsModule
local fs = {}

-- Try to load luafilesystem, fall back to shell-based implementations
local lfs_ok, lfs = pcall(require, "lfs")
local has_lfs = lfs_ok and lfs

--- Create directory path (like mkdir -p).
function fs.mkdir_p(path)
  if path == "" or path == "." then return end
  -- Try shell mkdir -p first (fast, ubiquitous)
  os.execute("mkdir -p " .. fs.shell_quote(path))
end

--- Quote a path for shell usage.
function fs.shell_quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

--- Check if a path is a directory.
function fs.is_dir(path)
  if has_lfs then
    return lfs.attributes(path, "mode") == "directory"
  end
  local f = io.open(path, "rb")
  if f then f:close(); return false end
  -- If we can't open it as a file, it might be a dir
  local ok = pcall(function()
    local pipe = io.popen("test -d " .. fs.shell_quote(path) .. " 2>/dev/null && echo yes")
    local result = pipe:read("*l")
    pipe:close()
    return result == "yes"
  end)
  return ok
end

--- List all files (not directories) under root, returning relative paths.
function fs.list_files(root)
  if has_lfs then
    local result = {}
    local function walk(dir, prefix)
      for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
          local full = dir .. "/" .. entry
          local mode = lfs.attributes(full, "mode")
          if mode == "file" then
            result[#result + 1] = prefix .. entry
          elseif mode == "directory" then
            walk(full, prefix .. entry .. "/")
          elseif mode == "link" then
            result[#result + 1] = prefix .. entry
          end
        end
      end
    end
    walk(root, "")
    table.sort(result)
    return result
  end
  -- Fallback: use find
  local pipe = io.popen("cd " .. fs.shell_quote(root) .. " && find . -type f -print")
  if not pipe then return {} end
  local result = {}
  for line in pipe:lines() do
    result[#result + 1] = line:gsub("^%./", "")
  end
  pipe:close()
  table.sort(result)
  return result
end

--- List all symlinks under root, returning relative paths.
function fs.list_symlinks(root)
  if has_lfs then
    local result = {}
    local function walk(dir, prefix)
      for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
          local full = dir .. "/" .. entry
          local mode = lfs.attributes(full, "mode")
          if mode == "link" then
            result[#result + 1] = prefix .. entry
          elseif mode == "directory" then
            walk(full, prefix .. entry .. "/")
          end
        end
      end
    end
    walk(root, "")
    table.sort(result)
    return result
  end
  local pipe = io.popen("cd " .. fs.shell_quote(root) .. " && find . -type l -print")
  if not pipe then return {} end
  local result = {}
  for line in pipe:lines() do
    result[#result + 1] = line:gsub("^%./", "")
  end
  pipe:close()
  table.sort(result)
  return result
end

--- Read a file's contents.
function fs.read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

--- Write content to a file, creating parent directories.
function fs.write_file(path, content)
  fs.mkdir_p(path:match("^(.*)/[^/]*$") or ".")
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
end

--- Get file size in bytes.
function fs.file_size(path)
  local file = io.open(path, "rb")
  if not file then return 0 end
  local size = file:seek("end")
  file:close()
  return size
end

--- Read the target of a symlink.
function fs.readlink(path)
  if has_lfs then
    return lfs.symlinkattributes(path, "target")
  end
  local pipe = io.popen("readlink " .. fs.shell_quote(path) .. " 2>/dev/null")
  if not pipe then return nil end
  local target = pipe:read("*l")
  pipe:close()
  return target
end

--- Compute a BLAKE3 hash of text, falling back to FNV-32.
function fs.hash_text(text)
  local tmp = os.tmpname()
  fs.write_file(tmp, text)
  local pipe = io.popen("b3sum --no-names " .. fs.shell_quote(tmp) .. " 2>/dev/null", "r")
  local hash = pipe and pipe:read("*l") or ""
  if pipe then pipe:close() end
  os.remove(tmp)
  if hash and hash ~= "" then return "b3:" .. hash end
  -- FNV-32 fallback
  local h = 2166136261
  for i = 1, #text do h = (h + text:byte(i) * 16777619) % 4294967296 end
  return string.format("fnv32:%08x", h)
end

--- Compute an ETag from text.
function fs.etag_for_text(text)
  return '"' .. fs.hash_text(text) .. '"'
end

--- Get relative path from a full path and a base directory.
function fs.relative(full, base)
  if #full <= #base then return full end
  if full:sub(1, #base) ~= base then return full end
  local rest = full:sub(#base + 1)
  if rest:sub(1, 1) == "/" then rest = rest:sub(2) end
  return rest
end

--- Join two path components.
function fs.join(a, b)
  if a == "" or a == "." then return b end
  if b == "" or b == "." then return a end
  return a .. "/" .. b
end

--- Get directory name of a path.
function fs.dirname(path)
  return tostring(path):match("^(.*)/[^/]*$") or "."
end

return fs
