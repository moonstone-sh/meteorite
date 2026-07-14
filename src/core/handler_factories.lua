local factories = {}

local function lua_handler_path(module_ref)
  if tostring(module_ref):find("/", 1, true) or tostring(module_ref):match("%.lua$") then return module_ref end
  return "src/" .. tostring(module_ref):gsub("%.", "/") .. ".lua"
end

function factories.zig(path_or_symbol, opts)
  opts = opts or {}
  if tostring(path_or_symbol):match("%.zig$") or tostring(path_or_symbol):find("/") then
    return { kind = "zig_file", path = path_or_symbol, decl = opts.decl or "handle" }
  end
  return { kind = "zig", symbol = path_or_symbol }
end

function factories.lua(module_ref)
  return { kind = "lua", module = module_ref, path = lua_handler_path(module_ref) }
end

function factories.file(path, opts)
  opts = opts or {}
  assert(type(path) == "string" and path ~= "", "m.file path must be a non-empty string")
  return {
    kind = "file",
    path = path,
    content_type = opts.content_type,
    cache = opts.cache or opts.cache_control or "no-cache",
    only = opts.only,
    name = opts.name,
  }
end

function factories.dir(root, opts)
  opts = opts or {}
  assert(type(root) == "string" and root ~= "", "m.dir root must be a non-empty string")
  assert(type(opts.param) == "string" and opts.param ~= "", "m.dir requires opts.param")
  assert(opts.index == nil or opts.index == false, "m.dir index files are not supported in the current release; declare explicit m.file routes")
  return {
    kind = "dir",
    root = root,
    param = opts.param,
    cache = opts.cache or opts.cache_control or (opts.immutable and "public, max-age=31536000, immutable" or "no-cache"),
    immutable = opts.immutable == true,
    types = opts.types,
    compressed = opts.compressed,
    index = opts.index or false,
    name = opts.name,
  }
end

function factories.handler(kind, ref, opts)
  opts = opts or {}
  if kind == "zig" then return { kind = "zig", symbol = ref } end
  if kind == "zig_file" then return { kind = "zig_file", path = ref, decl = opts.decl or "handle" } end
  if kind == "lua" then return { kind = "lua", module = ref, path = opts.path or lua_handler_path(ref) } end
  error("unsupported handler kind: " .. tostring(kind))
end

return factories
