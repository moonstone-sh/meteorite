local M = {}
function M.lua_task(script_root, source, output, target, optimize)
  return "sh", { script_root .. "/scripts/build-target-lua.sh", source, output, target, optimize }
end
function M.cmodule_task(script_root, source, rockspec, lua_root, output, target, name)
  return "sh", { script_root .. "/scripts/build-lua-cmodule.sh", source, rockspec, lua_root, output, target, name }
end
return M
