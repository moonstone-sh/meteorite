local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/cli/"
local module_root = script_dir:gsub("cli[/\\]$", "")
local package_root = module_root:gsub("src[/\\]$", "")
local install_root = package_root:gsub("meteorite[/\\]$", "")
local lua_v = _VERSION:match("%d+%.%d+") or "5.4"
package.path = "src/?.lua;src/?/init.lua;" .. module_root .. "?.lua;" .. module_root .. "?/init.lua;" .. package_root .. ".moonstone/env/share/lua/" .. lua_v .. "/?.lua;" .. package_root .. ".moonstone/env/share/lua/" .. lua_v .. "/?/init.lua;" .. package_root .. "?.lua;" .. package_root .. "?/init.lua;" .. install_root .. "?.lua;" .. install_root .. "?/init.lua;" .. install_root .. ".moonstone/env/share/lua/" .. lua_v .. "/?.lua;" .. install_root .. ".moonstone/env/share/lua/" .. lua_v .. "/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")
local cli_deps = require("cli.deps").new(source)
local help_text = require("cli.help_text")

local function print_help(topic)
  topic = topic or "main"
  topic = ({ ["--help"] = "main", ["-h"] = "main", help = "main" })[topic] or topic
  local page = help_text[topic]
  if not page then
    io.stderr:write("unknown help topic: " .. tostring(topic) .. "\n\n")
    page = help_text.main
  end
  print(page)
end

local app
app = c.create({
  name = "meteorite",
  version = "0.2.4",
  description = "Moonstone-zig service compiler prototype",

  root = c.node({
    c.inherit(
      c.flag({ key = "help", aliases = { "-h", "--help" } })
    ),

    c.run(function(ctx)
      if ctx.args.help then
        print_help("main")
        return 0
      end
      require("cli.graph").run(arg or {}, cli_deps.graph())
      return 0
    end),

    init = c.node({
      c.flag({ key = "force", aliases = { "--force" } }),
      c.flag({ key = "with_zig", aliases = { "--with-zig" } }),
      c.flag({ key = "minimal", aliases = { "--minimal" } }),
      c.flag({ key = "crud", aliases = { "--crud" } }),
      c.flag({ key = "static", aliases = { "--static" } }),
      c.flag({ key = "hybrid", aliases = { "--hybrid" } }),
      c.flag({ key = "no_sync", aliases = { "--no-sync" } }),
      c.option({ key = "template", aliases = { "--template" }, value = { schema = v.string() } }),
      c.option({ key = "name", aliases = { "--name" }, value = { schema = v.string() } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("init"); return 0 end
        require("cli.init").run(arg or {}, cli_deps.init(print_help))
        return 0
      end),
    }, { description = "Initialize a new Meteorite project" }),

    build = c.node({
      -- These flags are parsed here only so Clingy forwards the original
      -- argv to build_request below.  Meteorite deliberately owns their
      -- semantics there rather than duplicating defaults in its CLI schema.
      c.option({ key = "mode", aliases = { "--mode" }, value = { schema = v.string() } }),
      c.option({ key = "backend", aliases = { "--backend" }, value = { schema = v.string() } }),
      c.option({ key = "lua_root", aliases = { "--lua-root" }, value = { schema = v.string() } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("build"); return 0 end
        require("cli.build").run(arg or {}, cli_deps.build(print_help))
        return 0
      end),
    }, { description = "Build a Meteorite service" }),

    check = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("check"); return 0 end
        require("cli.check").run(arg or {}, cli_deps.check(print_help))
        return 0
      end),
    }, { description = "Check service graph and contracts" }),

    dev = c.node({
      -- See build above.  Without declaring these, Clingy rejects the
      -- explicit behavior contract before dev_command can validate it.
      c.option({ key = "mode", aliases = { "--mode" }, value = { schema = v.string() } }),
      c.option({ key = "backend", aliases = { "--backend" }, value = { schema = v.string() } }),
      c.option({ key = "lua_root", aliases = { "--lua-root" }, value = { schema = v.string() } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("dev"); return 0 end
        require("cli.dev_command").run(arg or {}, cli_deps.dev())
        return 0
      end),
    }, { description = "Run service in development mode" }),

    doctor = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("doctor"); return 0 end
        require("cli.doctor").run(cli_deps.doctor())
        return 0
      end),
    }, { description = "Diagnose toolchain and environment" }),

    client = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("client"); return 0 end
        require("cli.client").run(arg or {})
        return 0
      end),
    }, { description = "Generate Lua client" }),

    openapi = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("openapi"); return 0 end
        require("cli.openapi").run(arg or {})
        return 0
      end),
    }, { description = "Export OpenAPI schema" }),

    ipc = c.node({
      c.flag({ key = "json", aliases = { "--json" } }),
      c.option({ key = "socket", aliases = { "--socket" }, value = { schema = v.string() } }),
      c.option({ key = "message", aliases = { "--message" }, value = { schema = v.string() } }),
      c.option({ key = "route", aliases = { "--route" }, value = { schema = v.string() } }),
      c.option({ key = "method", aliases = { "--method" }, value = { schema = v.string() } }),
      c.option({ key = "path", aliases = { "--path" }, value = { schema = v.string() } }),
      c.option({ key = "body", aliases = { "--body" }, value = { schema = v.string() } }),
      c.option({ key = "body_file", aliases = { "--body-file" }, value = { schema = v.string() } }),
      c.option({ key = "content_type", aliases = { "--content-type" }, value = { schema = v.string() } }),
      c.option({ key = "metadata", aliases = { "--metadata" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("ipc"); return 0 end
        require("cli.ipc").run(arg or {})
        return 0
      end),
    }, { description = "Inspect IPC transports" }),

    routes = c.node({
      c.flag({ key = "graph", aliases = { "--graph" } }),
      c.flag({ key = "json", aliases = { "--json" } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("routes"); return 0 end
        require("cli.routes").run(arg or {})
        return 0
      end),
    }, { description = "List service routes" }),

    graph = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("graph"); return 0 end
        require("cli.graph").run(arg or {}, cli_deps.graph())
        return 0
      end),
    }, { description = "Generate service graph" }),

    sync = c.node({
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("sync"); return 0 end
        require("cli.sync").run(arg or {}, cli_deps.graph())
        return 0
      end),
    }, { description = "Sync handler interfaces" }),

    invoke = c.node({
      c.flag({ key = "json", aliases = { "--json" } }),
      c.flag({ key = "headers", aliases = { "--headers" } }),
      c.option({ key = "header", aliases = { "-H", "--header" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      c.option({ key = "body", aliases = { "--body" }, value = { schema = v.string() } }),
      c.arg({ key = "args", schema = v.string(), occurs = { min = 0, max = "many" } }),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("invoke"); return 0 end
        require("cli.invoke_command").run(arg or {})
        return 0
      end),
    }, { description = "Invoke a route directly" }),

    help = c.node({
      c.arg({ key = "topic", schema = v.string(), occurs = { min = 0, max = 1 } }),
      c.run(function(ctx)
        print_help(ctx.args.topic)
        return 0
      end),
    }, { description = "Show help information" }),
  }),
})

local argv = {}
for i, a in ipairs(arg or {}) do argv[i] = a end
if argv[1] == "--" then
  table.remove(argv, 1)
end

local exit_code = app:run(argv, { composer_mode = "plain" })
if exit_code and exit_code ~= 0 then
  os.exit(exit_code)
end
