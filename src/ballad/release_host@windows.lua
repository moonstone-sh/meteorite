local M = {}
function M.lua_task(script_root, source, output, target, optimize)
  return "lua", { script_root .. "/scripts/build-target-lua.lua", source, output, target, optimize }
end
function M.cmodule_task()
  error("Meteorite Windows-host C-module rebuilding needs a native rockspec toolchain; supply target-built C modules or build the release on a supported POSIX host", 0)
end
return M
