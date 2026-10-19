-- Native-host PUC Lua materialization: no make, Bash or host C compiler.
local variants = require("moonstone.variants")
variants.install()
local fs = require("ballad.fs")
local process = require("ballad.process")
local path = require("ballad.path")
local source, output, target, optimize = arg[1], arg[2], arg[3], arg[4] or "ReleaseFast"
assert(source and output and target, "usage: build-target-lua.lua <source> <output> <target> [optimize]")
local work = path.join(output,".build")
fs.remove_tree(output)
fs.mkdir(work)
fs.mkdir(path.join(output,"include")); fs.mkdir(path.join(output,"lib")); fs.mkdir(path.join(output,"bin"))
local function run(tool, args)
  local result=process.run({tool=tool,args=args})
  assert(result.exit_code==0,"target Lua tool failed (" .. result.exit_code .. "): " .. tool)
end
run("tar", {"-xf",source,"-C",work})
local root
for _, file in ipairs(fs.list_files(work)) do
  if file:match("/src/lua%.c$") then
    assert(not root,"ambiguous PUC Lua source roots")
    root=path.dirname(file)
  end
end
assert(root,"PUC Lua source archive lacks src/lua.c")
local windows=target:find("windows",1,true) ~= nil
local flags={"-target",target,optimize=="Debug" and "-O0" or optimize=="ReleaseSmall" and "-Os" or "-O2"}
if not windows then flags[#flags+1]="-DLUA_USE_POSIX" end
if not windows then flags[#flags+1]="-fPIC" end
local function args(prefix, extras)
  local result={prefix}
  for _, value in ipairs(flags) do result[#result+1]=value end
  for _, value in ipairs(extras) do result[#result+1]=value end
  return result
end
local objects={}
for _, file in ipairs(fs.list_files(root)) do
  local name=path.basename(file)
  if name:match("%.c$") and name~="lua.c" and name~="luac.c" and name~="onelua.c" then
    local object=path.join(work,name .. ".o")
    run("zig",args("cc",{"-c",file,"-o",object}))
    objects[#objects+1]=object
  end
end
assert(#objects>0,"PUC Lua source archive contains no library sources")
local archive=path.join(output,"lib/liblua.a")
local archive_args={"ar","rcs",archive}
for _, object in ipairs(objects) do archive_args[#archive_args+1]=object end
run("zig",archive_args)
for _, program in ipairs({"lua","luac"}) do
  local file=path.join(root,program .. ".c")
  if fs.is_file(file) then
    local bin=path.join(output,"bin/" .. program .. (windows and ".exe" or ""))
    local extras={file,archive,"-o",bin}
    if not windows then extras[#extras+1]="-lm" end
    run("zig",args("cc",extras))
  end
end
for _, header in ipairs({"lua.h","luaconf.h","lualib.h","lauxlib.h","lua.hpp"}) do
  if fs.is_file(path.join(root,header)) then fs.copy_file(path.join(root,header),path.join(output,"include/" .. header)) end
end
fs.write_file(path.join(output,"runtime.json"),require("dkjson").encode({
  format="meteorite.target_lua.v0",target=target,source_payload=source,
  lib="lib/liblua.a",include="include",bin="bin/lua" .. (windows and ".exe" or ""),
}))
fs.remove_tree(work)
