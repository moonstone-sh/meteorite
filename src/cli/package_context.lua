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

-- Expanded libexec candidates go last in each list: candidate_file walks
-- with ipairs, so they must follow any optional (nil) entry, and they are
-- empty exactly when share_root is nil.
local function unpack_candidates(list)
  return (table.unpack or unpack)(list, 1, list.n or #list)
end

--- Each suffix under every libexec root Meteorite may be mounted at
--- (namespaced first, then the flat compatibility alias).
function Context:libexec_candidates(suffixes)
  local out = { n = 0 }
  for _, root in ipairs(self.libexec_roots or {}) do
    for _, suffix in ipairs(suffixes) do
      out.n = out.n + 1
      out[out.n] = root .. suffix
    end
  end
  return out
end

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
    unpack_candidates(self:libexec_candidates({ "/build.zig", "/meteorite/build.zig", "/files/build.zig" })),
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
    unpack_candidates(self:libexec_candidates({ "/src/cli/main.lua", "/meteorite/cli/main.lua", "/files/meteorite/cli/main.lua" })),
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
    unpack_candidates(self:libexec_candidates({ "/src/cli/dev.lua", "/meteorite/cli/dev.lua", "/files/meteorite/cli/dev.lua" })),
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
    unpack_candidates(self:libexec_candidates({ "/scripts/guard.sh", "/files/scripts/guard.sh" })),
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
  -- Moonstone 0.5.9+ mounts packages at libexec/<namespace>/<name>; the flat
  -- libexec/meteorite path is only a compatibility alias (absent when another
  -- package, e.g. hydronium/meteorite, shares the name). Try both.
  local env_root = share_root and parent_dir(parent_dir(parent_dir(share_root))) or nil
  local libexec_roots = env_root and { env_root .. "/libexec/moonstone/meteorite", env_root .. "/libexec/meteorite" } or {}
  local libexec_root = libexec_roots[1]
  local ctx = setmetatable({
    source = source,
    script_dir = script_dir,
    module_root = module_root,
    install_root = install_root,
    share_root = share_root,
    libexec_root = libexec_root,
    libexec_roots = libexec_roots,
    read_file = read_file,
  }, Context)
  local package_root = ctx:candidate_file({
    install_root .. "build.zig",
    install_root .. "../build.zig",
    share_root and (share_root .. "/build.zig") or nil,
    unpack_candidates(ctx:libexec_candidates({ "/build.zig", "/meteorite/build.zig", "/files/build.zig" })),
  })
  ctx.package_root = package_root and dirname(package_root) or install_root
  return ctx
end

return package_context
