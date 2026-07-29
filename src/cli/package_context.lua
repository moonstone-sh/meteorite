local package_context = {}

local function dirname(path)
  return tostring(path):match("^(.*)/[^/]+$") or "."
end

local function parent_dir(path)
  local value = tostring(path):gsub("/+$", "")
  return value:match("^(.*)/[^/]+$") or "."
end

local function find_moonstone_share_root(path)
  local marker = "/share/lua/"
  local start_at, end_at = tostring(path):find(marker, 1, true)
  if not start_at then return nil end
  local rest = path:sub(end_at + 1)
  local lua_ver = rest:match("^([^/]+)")
  if not lua_ver then return nil end
  return path:sub(1, start_at - 1) .. "/share/lua/" .. lua_ver
end

local Context = {}
Context.__index = Context

function Context:candidate_file(paths)
  for _, candidate in ipairs(paths) do
    if candidate and self.read_file(candidate) then return candidate end
  end
  return nil
end

function Context:package_build_file()
  local found = self:candidate_file({
    self.package_root .. "/build.zig",
    self.install_root .. "build.zig",
    self.install_root .. "../build.zig",
    self.share_root and (self.share_root .. "/build.zig") or nil,
    self.libexec_root and (self.libexec_root .. "/build.zig") or nil,
    self.libexec_root and (self.libexec_root .. "/files/build.zig") or nil,
  })
  if found then return found end
  error("Meteorite build.zig not found near " .. tostring(self.install_root))
end

function Context:package_cli_file()
  local found = self:candidate_file({
    self.module_root .. "cli/main.lua",
    self.install_root .. "src/cli/main.lua",
    self.install_root .. "cli/main.lua",
    self.share_root and (self.share_root .. "/meteorite/cli/main.lua") or nil,
    self.libexec_root and (self.libexec_root .. "/src/cli/main.lua") or nil,
    self.libexec_root and (self.libexec_root .. "/files/meteorite/cli/main.lua") or nil,
  })
  if found then return found end
  error("Meteorite CLI not found near " .. tostring(self.install_root))
end

function Context:package_dev_file()
  local found = self:candidate_file({
    self.module_root .. "cli/dev.lua",
    self.install_root .. "src/cli/dev.lua",
    self.install_root .. "cli/dev.lua",
    self.share_root and (self.share_root .. "/meteorite/cli/dev.lua") or nil,
    self.libexec_root and (self.libexec_root .. "/src/cli/dev.lua") or nil,
    self.libexec_root and (self.libexec_root .. "/files/meteorite/cli/dev.lua") or nil,
  })
  if found then return found end
  error("Meteorite dev CLI not found near " .. tostring(self.install_root))
end

function Context:package_guard_file()
  local found = self:candidate_file({
    self.package_root .. "/scripts/guard.sh",
    self.install_root .. "scripts/guard.sh",
    self.install_root .. "../scripts/guard.sh",
    self.share_root and (self.share_root .. "/meteorite/scripts/guard.sh") or nil,
    self.libexec_root and (self.libexec_root .. "/scripts/guard.sh") or nil,
    self.libexec_root and (self.libexec_root .. "/files/scripts/guard.sh") or nil,
  })
  if found then return found end
  return "scripts/guard.sh"
end

function package_context.new(source, read_file)
  read_file = assert(read_file, "read_file required")
  local script_dir = source:match("^(.*[/\\])") or "src/cli/"
  local module_root = script_dir:gsub("cli[/\\]$", "")
  local install_root = module_root:gsub("src[/\\]$", "")
  local share_root = find_moonstone_share_root(source)
  local libexec_root = share_root and (parent_dir(parent_dir(parent_dir(share_root))) .. "/libexec/meteorite") or nil
  local ctx = setmetatable({
    source = source,
    script_dir = script_dir,
    module_root = module_root,
    install_root = install_root,
    share_root = share_root,
    libexec_root = libexec_root,
    read_file = read_file,
  }, Context)
  local package_root = ctx:candidate_file({
    install_root .. "build.zig",
    install_root .. "../build.zig",
    share_root and (share_root .. "/build.zig") or nil,
    libexec_root and (libexec_root .. "/build.zig") or nil,
    libexec_root and (libexec_root .. "/files/build.zig") or nil,
  })
  ctx.package_root = package_root and dirname(package_root) or install_root
  return ctx
end

return package_context
