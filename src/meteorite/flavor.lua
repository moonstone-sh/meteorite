-- meteorite.flavor: which Lua flavor Meteorite is running on, which flavor an
-- application is being built for, and how flavor-tagged files
-- (`handler@lua54.lua`) resolve for it.
--
-- A flavor is Moonstone's (language, os, arch) triple, written
-- `lua54-aarch64-macos` or `luajit-x86_64-linux`. The selection rule itself
-- lives in Moonstone's generated `moonstone.variants` module; this module
-- only feeds it. Every Moonstone call is guarded: without a flavor-aware
-- `moon` (or outside Moonstone entirely) the flavor still comes from runtime
-- detection, and file resolution falls back to the untagged file, which is
-- what Meteorite did before flavors existed.
--
-- Two flavors matter and they are not always the same:
--   * `flavor.host()`   the interpreter running this code (Meteorite's own
--                       modules, e.g. `meteorite.compat`).
--   * `flavor.target()` the Lua embedded in the server being built (handler
--                       files, the release's Lua tree). The Zig build passes
--                       it as METEORITE_LUA_FLAVOR because only the build
--                       knows the -Dtarget os/arch and the -Dlua-root it links.

local flavor = {}

local LANGUAGES = {
  lua51 = { family = "lua", level = 51 },
  lua52 = { family = "lua", level = 52 },
  lua53 = { family = "lua", level = 53 },
  lua54 = { family = "lua", level = 54 },
  lua55 = { family = "lua", level = 55 },
  luajit = { family = "luajit", level = 51 },
  luau = { family = "luau", level = 51 },
}

local function language_of(f)
  if f.family == "lua" then return "lua" .. tostring(f.level) end
  return f.family
end

local function make(family, level, os_tag, arch)
  local f = { family = family, level = level, os = os_tag or "unknown", arch = arch or "unknown" }
  f.id = language_of(f) .. "-" .. f.arch .. "-" .. f.os
  return f
end

--- Parse a flavor id such as `lua54-aarch64-macos` or `luajit-x86_64-linux`.
---@param id string
---@return {id: string, family: string, level: integer, os: string, arch: string}|nil
---@return string? err
function flavor.parse_id(id)
  if type(id) ~= "string" then return nil, "flavor id must be a string" end
  local language, arch, os_tag = id:match("^([%w]+)%-([%w_]+)%-([%w_]+)$")
  local lang = language and LANGUAGES[language]
  if not lang then
    return nil, "invalid flavor id `" .. id .. "` (expected <language>-<arch>-<os>, e.g. lua54-aarch64-macos)"
  end
  return make(lang.family, lang.level, os_tag, arch)
end

--- `moonstone.variants` when the environment has it (moon with flavor
--- support), otherwise nil. Never raises.
function flavor.variants()
  local ok, mod = pcall(require, "moonstone.variants")
  if ok and type(mod) == "table" and type(mod.select) == "function" and type(mod.suffixes) == "function" then
    return mod
  end
  return nil
end

local function moonstone_target()
  local ok, mod = pcall(require, "moonstone.target")
  if ok and type(mod) == "table" and type(mod.family) == "string" and tonumber(mod.level) then
    return mod
  end
  return nil
end

local function running_language()
  local jit = rawget(_G, "jit")
  if type(jit) == "table" and type(jit.version) == "string" then return "luajit", 51 end
  local major, minor = tostring(_VERSION):match("(%d+)%.(%d+)")
  return "lua", tonumber((major or "5") .. (minor or "1"))
end

local function normalize_os(name)
  name = tostring(name or ""):lower()
  if name == "osx" or name == "darwin" or name == "macos" then return "macos" end
  if name == "linux" or name == "windows" or name == "freebsd" then return name end
  if name:match("^mingw") or name:match("^msys") or name:match("^cygwin") then return "windows" end
  return nil
end

local function normalize_arch(name)
  name = tostring(name or ""):lower()
  if name == "x64" or name == "x86_64" or name == "amd64" then return "x86_64" end
  if name == "arm64" or name == "aarch64" then return "aarch64" end
  if name == "riscv64" then return "riscv64" end
  return nil
end

local host_cache

--- The flavor of the running interpreter. The language always comes from
--- the interpreter itself; os/arch come from `moonstone.target` when it
--- describes this interpreter, then from LuaJIT's `jit.os`/`jit.arch`, then
--- from `uname`. Unknown parts are "unknown", which no os/arch tag matches.
function flavor.host()
  if host_cache then return host_cache end
  local family, level = running_language()
  local os_tag, arch
  local target = moonstone_target()
  if target and target.family == family and tonumber(target.level) == level then
    os_tag, arch = target.os, target.arch
  end
  local jit = rawget(_G, "jit")
  if (not os_tag or not arch) and type(jit) == "table" then
    os_tag = os_tag or normalize_os(jit.os)
    arch = arch or normalize_arch(jit.arch)
  end
  if not os_tag or not arch then
    if package.config:sub(1, 1) == "\\" then
      os_tag = os_tag or "windows"
    elseif io.popen then
      local ok, pipe = pcall(io.popen, "uname -sm 2>/dev/null")
      local out = ok and pipe and pipe:read("*l") or ""
      if ok and pipe then pipe:close() end
      local sys, machine = out:match("^(%S+)%s+(%S+)")
      os_tag = os_tag or normalize_os(sys)
      arch = arch or normalize_arch(machine)
    end
  end
  host_cache = make(family, level, os_tag, arch)
  return host_cache
end

--- The flavor an application's Lua is built for, and where it came from:
---   1. METEORITE_LUA_FLAVOR (set by Meteorite's Zig build for the graph
---      step: the linked Lua and the -Dtarget os/arch),
---   2. MOONSTONE_TARGET (set by `moon exec`/`moon run`, or by the caller),
---   3. `moonstone.target` (the environment's flavor),
---   4. the running interpreter.
---@return table flavor
---@return string source
local target_override

function flavor.target()
  if target_override then return target_override, "override" end
  for _, name in ipairs({ "METEORITE_LUA_FLAVOR", "MOONSTONE_TARGET" }) do
    local value = os.getenv(name)
    if value and value ~= "" then
      local parsed, err = flavor.parse_id(value)
      if not parsed then error(name .. ": " .. err, 0) end
      return parsed, name
    end
  end
  local target = moonstone_target()
  if target and type(target.os) == "string" and type(target.arch) == "string" then
    return make(target.family, tonumber(target.level), target.os, target.arch), "moonstone.target"
  end
  return flavor.host(), "runtime"
end

--- Make `flavor.target()` return `f` until the returned function is called.
--- Used by the Ballad release task, which builds for -Dtarget in-process.
function flavor.override_target(f)
  local previous = target_override
  target_override = f
  return function() target_override = previous end
end

--- `base` with os/arch replaced by those of a Zig target triple
--- (`x86_64-linux-gnu`, `aarch64-macos`). "native", "host", nil or an
--- unparsable triple return `base` unchanged.
function flavor.for_zig_target(base, triple)
  if type(triple) ~= "string" or triple == "" or triple == "native" or triple == "host" or triple == "any" then
    return base
  end
  local arch, os_tag = triple:match("^([^%-]+)%-([^%-]+)")
  if not arch then return base end
  return make(base.family, base.level, normalize_os(os_tag) or os_tag, normalize_arch(arch) or arch)
end

local function readable(path)
  local file = io.open(path, "rb")
  if file then file:close() return true end
  return false
end

local function split_tags(suffix)
  local out = {}
  for tag in suffix:gmatch("@([^@]+)") do out[#out + 1] = tag end
  return out
end

--- Is this file name a flavor variant (`name@lua54.lua`)? Uses the
--- Moonstone rule when available; without it nothing counts as a variant.
function flavor.is_variant(file_name)
  local variants = flavor.variants()
  if not variants then return false end
  local base = tostring(file_name):match("([^/\\]+)$") or tostring(file_name)
  local parsed = variants.parse(base)
  return parsed ~= nil
end

--- Resolve a Lua file path for a flavor: `src/app/x.lua` becomes
--- `src/app/x@lua54.lua` when that variant exists and wins the selection.
--- Returns the path to load (the input when no variant applies) and the
--- chosen variant's tags (nil when the untagged file is used).
--- Raises when two variants are equally specific. A module that exists only
--- as variants for other flavors resolves to the (missing) input path, the
--- same "file not found" as before flavors existed.
---@param path string
---@param f table|nil flavor (defaults to flavor.target())
---@param root string|nil directory that relative paths are probed against
---@return string path
---@return string[]|nil tags
function flavor.resolve_file(path, f, root)
  local variants = flavor.variants()
  if not variants or type(path) ~= "string" then return path, nil end
  local base, ext = path:match("^(.+)(%.[^.@/\\]+)$")
  if not base then return path, nil end
  local file_name = base:match("([^/\\]+)$") or base
  if variants.parse(file_name .. ext) then return path, nil end -- already tagged
  f = f or flavor.target()
  local function probe(rel)
    if root and root ~= "" and rel:sub(1, 1) ~= "/" then return readable(root .. "/" .. rel) end
    return readable(rel)
  end
  local candidates, files = {}, {}
  for _, suffix in ipairs(variants.suffixes(f)) do
    local candidate = base .. suffix .. ext
    if probe(candidate) then
      candidates[#candidates + 1] = { tags = split_tags(suffix) }
      files[#files + 1] = candidate
    end
  end
  if #candidates == 0 then return path, nil end
  local has_base = probe(path)
  local choice, first, second = variants.select(candidates, has_base, f)
  if choice == "variant" then return files[first], candidates[first].tags end
  if choice == "ambiguous" then
    error(string.format("%s: %s and %s are equally specific for %s; add a more specific variant or remove one",
      path, files[first], second and files[second] or path, f.id), 0)
  end
  -- Only matching suffixes were probed, so "none" cannot happen here.
  return path, nil
end

--- Project a list of relative file paths the way `moon sync` projects a
--- package: every group of variants of one module collapses to the module's
--- untagged name, sourced from the winning file; losing variants disappear.
--- Returns an array of { source = <rel path>, path = <projected rel path> },
--- in input order of the projected names. Raises on ambiguity or on a
--- malformed tag order. Without `moonstone.variants` it is the identity.
---@param files string[]
---@param f table|nil
function flavor.project_files(files, f)
  local variants = flavor.variants()
  local out = {}
  if not variants then
    for _, rel in ipairs(files) do out[#out + 1] = { source = rel, path = rel } end
    return out
  end
  f = f or flavor.target()
  local groups, order = {}, {}
  for _, rel in ipairs(files) do
    local dir, name = rel:match("^(.-)([^/\\]+)$")
    local parsed, err = variants.parse(name)
    if parsed == false then error(err, 0) end
    local key = parsed and (dir .. parsed.stem .. parsed.ext) or rel
    local group = groups[key]
    if not group then
      group = { key = key, candidates = {}, files = {}, base = nil }
      groups[key] = group
      order[#order + 1] = key
    end
    if parsed then
      group.candidates[#group.candidates + 1] = parsed
      group.files[#group.files + 1] = rel
    else
      group.base = rel
    end
  end
  for _, key in ipairs(order) do
    local group = groups[key]
    if #group.candidates == 0 then
      out[#out + 1] = { source = group.base, path = key }
    else
      local choice, first, second = variants.select(group.candidates, group.base ~= nil, f)
      if choice == "variant" then
        out[#out + 1] = { source = group.files[first], path = key }
      elseif choice == "base" then
        out[#out + 1] = { source = group.base, path = key }
      elseif choice == "ambiguous" then
        error(string.format("%s: %s and %s are equally specific for %s",
          key, group.files[first], second and group.files[second] or tostring(group.base), f.id), 0)
      end
      -- "none": the module does not exist for this flavor.
    end
  end
  return out
end

--- Install Moonstone's runtime searcher for Meteorite's own (unprojected)
--- sources, keyed to the running interpreter. No-op without Moonstone.
function flavor.install_searcher()
  local variants = flavor.variants()
  if not variants or type(variants.install) ~= "function" then return false end
  local ok = pcall(variants.install, flavor.host())
  return ok
end

return flavor
