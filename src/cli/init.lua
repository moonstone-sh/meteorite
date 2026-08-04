--- Meteorite project initialization command.

local cli_templates = require("cli.templates")
local json = require("utils.json")

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
  return cli_templates.moonstone_manifest(name, build_mode)
end

local function release_partiture()
  return cli_templates.release_partiture()
end

local function capture(command)
  local pipe = assert(io.popen(command, "r"))
  local output = pipe:read("*a") or ""
  local ok, _, code = pipe:close()
  if ok == true or code == 0 then return output end
  error("Moonstone command failed: " .. command)
end

local function json_string_pattern(value)
  return '"' .. tostring(value):gsub("([^%w])", "%%%1") .. '"'
end

local function manifest_has_named_entry(document, section, name)
  local section_start = document:find('"' .. section .. '":[', 1, true)
  if not section_start then return false end
  local section_end = document:find("]", section_start, true) or #document
  local section_json = document:sub(section_start, section_end)
  return section_json:find('"name":' .. json_string_pattern(name)) ~= nil
end

local function apply_manifest_operations(target, build_mode, moon_bin)
  local export = capture(shell_quote(moon_bin) .. " -C " .. shell_quote(target) .. " manifest export --json 2>/dev/null")
  local revision = export:match('"storage_revision":"([^"]+)"')
  if not revision then error("Moonstone manifest export did not return a storage revision") end

  local operations = {}
  for _, dependency in ipairs({
    { name = "moonstone/meteorite", constraint = "^0.1.41" },
    { name = "moonstone/ballad", constraint = "^0.2.41" },
  }) do
    if not manifest_has_named_entry(export, "dependencies", dependency.name) then
      operations[#operations + 1] = {
        kind = "add_dependency",
        dependency = { name = dependency.name, constraint = dependency.constraint, role = "tool" },
      }
    end
  end

  for _, script in ipairs(cli_templates.moonstone_scripts(build_mode)) do
    if not manifest_has_named_entry(export, "scripts", script.key) then
      operations[#operations + 1] = { kind = "set_script", name = script.key, command = script.command }
    else
      print("Meteorite left user-owned Moonstone script `" .. script.key .. "` unchanged.")
    end
  end

  if #operations == 0 then return false end
  local request_path = os.tmpname()
  local request = assert(io.open(request_path, "wb"))
  request:write(json.encode({
    contract = "moonstone:manifest-edit:v1",
    expected_revision = revision,
    operations = operations,
  }))
  request:close()
  local ok, _, code = os.execute(shell_quote(moon_bin) .. " -C " .. shell_quote(target) .. " manifest apply --json --force < " .. shell_quote(request_path))
  os.remove(request_path)
  if not (ok == true or ok == 0 or code == 0) then error("Moonstone rejected Meteorite's manifest adoption transaction") end
  return true
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
    apply_manifest_operations(target, _G.METEORITE_INIT_BUILD_MODE, config.moon_bin or os.getenv("MOONSTONE_BIN") or "moon")
  end
  local partiture_path = path_join(target, "partiture.lua")
  if not read_file(partiture_path) then
    write_file(partiture_path, release_partiture(), opts.force)
  end
  local build_path = path_join(target, "build.zig")
  local generated_build = not read_file(build_path)
  if generated_build and not read_file(path_join(target, "build.zig.zon")) then
    os.execute("cd " .. shell_quote(target) .. " && zig init --minimal >/dev/null 2>&1")
  end
  local generated_partitures = {
    ["build.zig"] = cli_templates.project_build_zig(),
    ["partiture_common.lua"] = cli_templates.partiture_common(),
    ["Dev_partiture.lua"] = cli_templates.dev_partiture(),
    ["Watch_partiture.lua"] = cli_templates.watch_partiture(),
    ["Check_partiture.lua"] = cli_templates.check_partiture(),
  }
  for relative_path, content in pairs(generated_partitures) do
    local path = path_join(target, relative_path)
    if relative_path == "build.zig" and generated_build then
      write_file(path, content, true)
    elseif not read_file(path) then
      write_file(path, content, opts.force)
    end
  end
  if not opts.no_sync then os.execute("cd " .. shell_quote(target) .. " && moon sync") end
  print("Meteorite project initialized: " .. target .. " (template: " .. template_name .. ")" .. (opts.with_zig and " (with Zig scaffolding)" or ""))
end

return init
