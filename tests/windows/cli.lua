local root=assert(os.getenv("METEORITE_TEST_ROOT"))
local clingy=assert(os.getenv("CLINGY_TEST_ROOT"))
local ballad=assert(os.getenv("BALLAD_TEST_ROOT"))
package.path=clingy .. "/src/?.lua;" .. clingy .. "/src/?/init.lua;" .. ballad .. "/src/?.lua;" .. ballad .. "/src/?/init.lua;" .. root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
require("moonstone.variants").install()
if arg[1]=="build-lua" then
  table.remove(arg,1)
  dofile(root .. "/scripts/build-target-lua.lua")
else
  dofile(root .. "/src/cli/main.lua")
end
