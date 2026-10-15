local build_context = require("meteorite.build_context")
local app_loader = {}

function app_loader.load(input, mode)
  input = input or "src/main.lua"
  local input_dir = input:match("^(.*[/\\])") or ""
  if input_dir ~= "" then
    package.path = input_dir .. "?.lua;" .. input_dir .. "?/init.lua;" .. package.path
  end
  local chunk, err = loadfile(input)
  if not chunk then error(err) end
  local app = build_context.with(build_context.create(mode), chunk)
  if type(app) ~= "table" or not app.__meteorite_app then
    error(input .. " must return a Meteorite app")
  end
  return app
end

return app_loader
