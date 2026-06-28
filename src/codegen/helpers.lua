--- Shared helper functions for the codegen pipeline.
--- Extracted from emitter.lua to reduce its size and clarify concerns.
---
--- @class CodegenHelpers
--- @field write_file fun(path: string, content: string): boolean
--- @field read_file fun(path: string): string|nil
--- @field file_exists fun(path: string): boolean
--- @field mkdir_p fun(path: string)
--- @field hash_text fun(text: string): string
--- @field hash_zon fun(value: any): string
--- @field sorted_keys fun(value: table): string[]
--- @field method_enum fun(method: string): table
--- @field mode_enum fun(mode: string): table
--- @field zig_ident fun(value: any): string
--- @field zig_string fun(value: any): string
--- @field scope_value fun(value: any): string
--- @field scope_plugin_ref fun(plugin: any): string
--- @field normalized_scope fun(scope: table): table
--- @field project_root_from_output fun(output: string): string
--- @field detect_lua_version fun(root: string): string
--- @field dirname fun(path: string): string
--- @field path_join fun(a: string, b: string): string

---@type CodegenHelpers

local zon = require("codegen.zon")
local fs = require("utils.fs")

local helpers = {}

-- File operations (write-on-change pattern)
helpers.write_file = function(path, content)
  local existing = fs.read_file(path)
  if existing == content then return false end
  fs.write_file(path, content)
  return true
end

helpers.read_file = function(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

helpers.file_exists = function(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

helpers.mkdir_p = fs.mkdir_p
helpers.hash_text = fs.hash_text
helpers.dirname = fs.dirname
helpers.path_join = fs.join

-- ZON hashing
--- Hash a ZON-encoded value.
---@param value any  Value to encode and hash
---@return string  Hash with prefix (b3: or fnv32:)
function helpers.hash_zon(value)
  return helpers.hash_text(zon.encode(value))
end

-- Key sorting
--- Get sorted keys of a table.
---@param value table  Table to get keys from
---@return string[]  Sorted keys
function helpers.sorted_keys(value)
  local keys = {}
  for key, _ in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Enum markers for ZON encoding
--- Create a ZON enum marker for HTTP method.
---@param method string  HTTP method (GET, POST, etc.)
---@return table  Enum marker
function helpers.method_enum(method) return { __meteorite_enum = true, value = method } end
--- Create a ZON enum marker for build mode.
---@param mode string  Build mode (release-static, hybrid, etc.)
---@return table  Enum marker
function helpers.mode_enum(mode) return { __meteorite_enum = true, value = (mode:gsub("-", "_")) } end

-- Zig identifier and string formatting
--- Convert a value to a valid Zig identifier.
---@param value any  Value to convert
---@return string  Zig-safe identifier
function helpers.zig_ident(value)
  local out = tostring(value):gsub("%W", "_")
  if out:match("^%d") then out = "_" .. out end
  return out
end

--- Quote a value as a Zig string literal.
---@param value any  Value to quote
---@return string  Quoted Zig string
function helpers.zig_string(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

-- Scope normalization
--- Extract a scope value string from a value.
---@param value any  Scope value
---@return string  String representation
function helpers.scope_value(value)
  if value == nil then return "" end
  if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if type(value) == "table" then return tostring(value.id or value.name or value.kind or "table") end
  return type(value)
end

--- Extract a plugin reference string from a plugin spec.
---@param plugin any  Plugin spec (string or table)
---@return string  Plugin reference string
function helpers.scope_plugin_ref(plugin)
  if type(plugin) == "string" then return plugin end
  if type(plugin) == "table" then return tostring(plugin.id or plugin.name or plugin.kind or "plugin") end
  return type(plugin)
end

--- Normalize a scope into a stable, serializable form.
---@param scope table  Raw scope
---@return table  Normalized scope
function helpers.normalized_scope(scope)
  scope = scope or {}
  local chain = {}
  for _, item in ipairs(scope.chain or {}) do
    chain[#chain + 1] = { id = tostring(item.id or "root"), path_prefix = tostring(item.path_prefix or "") }
  end
  local plugins = {}
  for _, plugin in ipairs(scope.plugins or {}) do plugins[#plugins + 1] = helpers.scope_plugin_ref(plugin) end
  local context = {}
  for _, key in ipairs(helpers.sorted_keys(scope.context or {})) do context[#context + 1] = { key = tostring(key), value = helpers.scope_value(scope.context[key]) } end
  return {
    id = tostring(scope.id or "root"),
    parent = tostring(scope.parent or ""),
    path_prefix = tostring(scope.path_prefix or ""),
    chain = chain,
    plugins = plugins,
    context = context,
  }
end

-- Project root detection from output path
--- Detect project root from an output path.
---@param output string  Output path (e.g. .meteorite/graph/current)
---@return string  Project root ("." if not found)
function helpers.project_root_from_output(output)
  local marker = output:find("%.meteorite/", 1)
  if marker then
    if marker <= 2 then return "." end
    local root = output:sub(1, marker - 2)
    return root ~= "" and root or "."
  end
  return "."
end

-- Lua version detection from Moonstone env
--- Detect Lua version from Moonstone env.toml.
---@param root string  Project root
---@return string  Lua version (e.g. "5.4")
function helpers.detect_lua_version(root)
  local env = helpers.read_file(helpers.path_join(root, ".moonstone/env/env.toml")) or ""
  local abi = env:match('abi%s*=%s*"([^"]+)"') or env:match("abi%s*=%s*'([^']+)'") or "5.4"
  local major, minor = abi:match("lua(%d)(%d)")
  if major and minor then return major .. "." .. minor end
  major, minor = abi:match("(%d)%.(%d)")
  if major and minor then return major .. "." .. minor end
  return "5.4"
end

return helpers
