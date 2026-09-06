local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local script_dir = source:match("^(.*[/\\])") or "src/cli/"
local module_root = script_dir:gsub("cli[/\\]$", "")
local install_root = module_root:gsub("src[/\\]$", ""):gsub("meteorite[/\\]$", "")
package.path = "src/?.lua;src/?/init.lua;" .. module_root .. "?.lua;" .. module_root .. "?/init.lua;" .. install_root .. "?.lua;" .. install_root .. "?/init.lua;" .. package.path

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
  version = "0.2.1",
  description = "Moonstone-zig service compiler prototype",

  c.root(c.node({
    c.inherit(
      c.flag("-h", "--help")
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
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("init"); return 0 end
        require("cli.init").run(arg or {}, cli_deps.init(print_help))
        return 0
      end),
    }, { description = "Initialize a new Meteorite project" }),

    build = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("build"); return 0 end
        require("cli.build").run(arg or {}, cli_deps.build(print_help))
        return 0
      end),
    }, { description = "Build a Meteorite service" }),

    check = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("check"); return 0 end
        require("cli.check").run(arg or {}, cli_deps.check(print_help))
        return 0
      end),
    }, { description = "Check service graph and contracts" }),

    dev = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("dev"); return 0 end
        require("cli.dev_command").run(arg or {}, cli_deps.dev())
        return 0
      end),
    }, { description = "Run service in development mode" }),

    doctor = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("doctor"); return 0 end
        require("cli.doctor").run(cli_deps.doctor())
        return 0
      end),
    }, { description = "Diagnose toolchain and environment" }),

    client = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("client"); return 0 end
        require("cli.client").run(arg or {})
        return 0
      end),
    }, { description = "Generate Lua client" }),

    openapi = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("openapi"); return 0 end
        require("cli.openapi").run(arg or {})
        return 0
      end),
    }, { description = "Export OpenAPI schema" }),

    ipc = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("ipc"); return 0 end
        require("cli.ipc").run(arg or {})
        return 0
      end),
    }, { description = "Inspect IPC transports" }),

    routes = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("routes"); return 0 end
        require("cli.routes").run(arg or {})
        return 0
      end),
    }, { description = "List service routes" }),

    graph = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("graph"); return 0 end
        require("cli.graph").run(arg or {}, cli_deps.graph())
        return 0
      end),
    }, { description = "Generate service graph" }),

    sync = c.node({
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("sync"); return 0 end
        require("cli.sync").run(arg or {}, cli_deps.graph())
        return 0
      end),
    }, { description = "Sync handler interfaces" }),

    invoke = c.node({
      c.flag("--json"),
      c.flag("--headers"),
      c.repeated(c.option("-H", "--header", v.string())),
      c.option("--body", v.string()),
      c.repeated(c.optional(c.arg("args", v.string()))),
      c.passthrough("argv"),
      c.run(function(ctx)
        if ctx.args.help then print_help("invoke"); return 0 end
        require("cli.invoke_command").run(arg or {})
        return 0
      end),
    }, { description = "Invoke a route directly" }),

    help = c.node({
      c.optional(c.arg("topic", v.string())),
      c.run(function(ctx)
        print_help(ctx.args.topic)
        return 0
      end),
    }, { description = "Show help information" }),
  })),
})

local argv = {}
for i, a in ipairs(arg or {}) do argv[i] = a end
if argv[1] == "--" then
  table.remove(argv, 1)
end

local exit_code = app:run(argv)
if exit_code and exit_code ~= 0 then
  os.exit(exit_code)
end

