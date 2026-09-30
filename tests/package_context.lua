package.path = "src/?.lua;src/?/init.lua;" .. package.path

-- Meteorite finds its own build.zig/CLI through the consuming project's
-- Moonstone environment. Moonstone 0.5.9+ mounts it at
-- libexec/moonstone/meteorite (namespaced); the flat libexec/meteorite path
-- is only an alias and is absent when another package (hydronium/meteorite)
-- shares the name. A virtual file system stands in for the environment.
local package_context = require("cli.package_context")

local function context_for(files)
  local read = function(path) return files[path] end
  -- A projected CLI module inside the project's env share tree.
  return package_context.new("/app/.moonstone/env/share/lua/5.4/cli/package_context.lua", read)
end

-- Namespaced mount only (the flat alias is contested and therefore absent).
local ctx = context_for({
  ["/app/.moonstone/env/libexec/moonstone/meteorite/meteorite/build.zig"] = "zig",
  ["/app/.moonstone/env/libexec/moonstone/meteorite/meteorite/cli/main.lua"] = "lua",
})
assert(ctx:package_build_file() == "/app/.moonstone/env/libexec/moonstone/meteorite/meteorite/build.zig", ctx:package_build_file())
assert(ctx:package_cli_file() == "/app/.moonstone/env/libexec/moonstone/meteorite/meteorite/cli/main.lua")

-- Older Moonstone: only the flat mount exists.
ctx = context_for({
  ["/app/.moonstone/env/libexec/meteorite/files/build.zig"] = "zig",
})
assert(ctx:package_build_file() == "/app/.moonstone/env/libexec/meteorite/files/build.zig", ctx:package_build_file())

print("package_context: ok")
