package.path = "src/?.lua;src/?/init.lua;tests/?.lua;" .. package.path

local init = require("cli.init")
local test = require("test")

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

local function remove_tree(path)
  os.execute("rm -rf " .. string.format("%q", path))
end

test "meteorite init augments an empty Moonstone host with canonical tools" (function()
  local target = os.tmpname()
  os.remove(target)
  assert(os.execute("mkdir -p " .. string.format("%q", target)))
  local manifest_path = target .. "/moonstone.toml"
  local manifest = assert(io.open(manifest_path, "wb"))
  manifest:write(table.concat({
    "[package]",
    'name = "service"',
    'version = "0.1.0"',
    'kind = "script"',
    "",
    "[interpreter]",
    'name = "lua"',
    'version = "5.4"',
    'abi = "5.4"',
    "",
  }, "\n"))
  manifest:close()

  init.run({ "init", target, "--no-sync" }, {
    print_help = function() end,
    roots = {
      install_root = "./",
      module_root = "src/",
    },
  })

  local updated = read_file(manifest_path)
  test.assert_true(updated:find('name = "moonstone/meteorite"', 1, true) ~= nil)
  test.assert_true(updated:find('constraint = "^0.1.13"', 1, true) ~= nil)
  test.assert_true(updated:find('name = "moonstone/ballad"', 1, true) ~= nil)
  test.assert_true(updated:find('constraint = "^0.2.32"', 1, true) ~= nil)
  test.assert_true(updated:find('[dependencies.tool]', 1, true) == nil)
  test.assert_true(updated:find('role = "tool"', 1, true) ~= nil)

  remove_tree(target)
end)

test.run()
