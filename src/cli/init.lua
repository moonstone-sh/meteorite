--- Meteorite project initialization command.

local cli_templates = require("cli.templates")

local init = {}

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function write_file(path, content, force)
  local existing = read_file(path)
  if existing ~= nil and not force then return false end
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then os.execute("mkdir -p " .. string.format("%q", parent)) end
  local file, err = io.open(path, "wb")
  if not file then error("cannot write " .. path .. ": " .. tostring(err)) end
  file:write(content)
  file:close()
  return true
end

local function path_join(a, b)
  if a == "." or a == "" then return b end
  return a .. "/" .. b
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function render_template(text, name, lua_ver)
  return (text:gsub("{{name}}", name):gsub("{{lua_ver}}", lua_ver))
end

local function project_name_from_path(path)
  path = tostring(path or "."):gsub("/+$", "")
  local name = path:match("([^/]+)$") or "meteorite-app"
  if name == "." or name == "" then name = "meteorite-app" end
  return name:gsub("[^%w_.-]", "-")
end

local function template_root(name, roots)
  name = name or "project"
  for _, candidate in ipairs({
    roots.install_root .. "templates/" .. name,
    roots.install_root .. "../templates/" .. name,
    roots.module_root .. "../templates/" .. name,
  }) do
    if read_file(path_join(candidate, "src/main.lua")) then return candidate end
  end
  error("Meteorite template files not found near " .. tostring(roots.install_root))
end

local function parse_args(argv, print_help)
  local opts = { target = ".", name = nil, force = false, with_zig = false, no_sync = false, template = "project" }
  local i = 2
  while i <= #argv do
    local value = argv[i]
    if value == "--help" or value == "-h" then print_help("init"); os.exit(0)
    end
    if value == "--force" then opts.force = true
    elseif value == "--with-zig" then opts.with_zig = true
    elseif value == "--minimal" then opts.with_zig = false
    elseif value == "--crud" then error("`meteorite init --crud` was removed; see docs/examples.md for the CRUD example")
    elseif value == "--static" then opts.template = "static"
    elseif value == "--hybrid" then opts.template = "hybrid"
    elseif value == "--no-sync" then opts.no_sync = true
    elseif value == "--template" then
      i = i + 1
      opts.template = argv[i]
    elseif value and value:match("^%-%-template=") then opts.template = value:match("^%-%-template=(.*)$")
    elseif value == "--name" then
      i = i + 1
      opts.name = argv[i]
    elseif value and value:match("^%-%-name=") then opts.name = value:match("^%-%-name=(.*)$")
    elseif value and value:sub(1, 1) == "-" then error("unknown meteorite init flag: " .. tostring(value))
    else opts.target = value end
    i = i + 1
  end
  return opts
end

local function moonstone_manifest(name)
  local build_mode = _G.METEORITE_INIT_BUILD_MODE or "hybrid"
  local dev_script = build_mode == "release-static" and "meteorite build --mode release-static && ./dist/server" or "meteorite dev"
  return cli_templates.moonstone_manifest(name, build_mode, dev_script)
end

local function release_partiture()
  local build_mode = _G.METEORITE_INIT_BUILD_MODE or "hybrid"
  local release_mode = build_mode == "release-static" and "static" or "hybrid"
  return cli_templates.release_partiture(release_mode)
end

local function ensure_tool_dependencies(path)
  local content = read_file(path)
  if not content then return false end
  local deps = {}
  if not content:find('"moonstone/meteorite"', 1, true) then deps[#deps + 1] = '"moonstone/meteorite" = "^0.1.0"' end
  if not content:find('"moonstone/ballad"', 1, true) then deps[#deps + 1] = '"moonstone/ballad" = "^0.2.0"' end
  if #deps == 0 then return false end
  local block = table.concat(deps, "\n") .. "\n"
  local updated, count = content:gsub("(\n%[dependencies%.tool%]\n)", "%1" .. block, 1)
  if count == 0 then updated = content:gsub("%s*$", "\n\n[dependencies.tool]\n" .. block) end
  return write_file(path, updated, true)
end

function init.run(argv, config)
  config = config or {}
  local opts = parse_args(argv, assert(config.print_help, "init command requires print_help"))
  local roots = assert(config.roots, "init command requires roots")
  local target = opts.target or "."
  local name = opts.name or project_name_from_path(target)
  local lua_ver = "5.4"
  local template_name = ({ minimal = "project" })[opts.template] or opts.template or "project"
  local known_templates = {
    project = true,
    static = true,
    hybrid = true,
    middleware = true,
    cors = true,
    ["json-api"] = true,
    ["static-site"] = true,
  }
  if not known_templates[template_name] then
    error("unknown Meteorite template `" .. tostring(opts.template) .. "`; expected minimal, static, hybrid, middleware, cors, json-api, or static-site")
  end
  _G.METEORITE_INIT_BUILD_MODE = template_name == "static" and "release-static" or "hybrid"
  local root = template_root(template_name, roots)
  local files = {}
  local pipe = io.popen("cd " .. shell_quote(root) .. " && find . -type f | sort", "r")
  if pipe then
    for line in pipe:lines() do files[#files + 1] = line:gsub("^%./", "") end
    pipe:close()
  end
  if opts.with_zig then
    files[#files + 1] = "zig/handlers.zig"
    files[#files + 1] = "zig/validators.zig"
  end
  os.execute("mkdir -p " .. string.format("%q", target))
  for _, rel in ipairs(files) do
    local source_path = path_join(root, rel)
    local content = read_file(source_path)
    if not content then error("missing Meteorite template file: " .. source_path) end
    write_file(path_join(target, rel), render_template(content, name, lua_ver), opts.force)
  end
  local manifest_path = path_join(target, "moonstone.toml")
  if not read_file(manifest_path) then
    write_file(manifest_path, moonstone_manifest(name), opts.force)
  else
    ensure_tool_dependencies(manifest_path)
  end
  local partiture_path = path_join(target, "partiture.lua")
  if not read_file(partiture_path) then
    write_file(partiture_path, release_partiture(), opts.force)
  end
  if not opts.no_sync then os.execute("cd " .. shell_quote(target) .. " && moon sync") end
  print("Meteorite project initialized: " .. target .. " (template: " .. template_name .. ")" .. (opts.with_zig and " (with Zig scaffolding)" or ""))
end

return init
