local openapi = {}

local function usage()
  return [[Meteorite OpenAPI

Usage:
  meteorite openapi swagger-ui [output] [spec-url]

Examples:
  meteorite openapi swagger-ui public/docs.html ./openapi.json]]
end

local function write_file(path, content)
  local dir = path:match("^(.*[/\\])")
  if dir and dir ~= "" then os.execute("mkdir -p " .. string.format("%q", dir)) end
  local file, err = io.open(path, "wb")
  if not file then error(err) end
  file:write(content)
  file:close()
end

function openapi.run(args)
  local command = args[2]
  if command == "--help" or command == "-h" or not command then
    print(usage())
    return
  end
  if command ~= "swagger-ui" then error("unknown openapi command `" .. tostring(command) .. "`; expected swagger-ui") end
  local output = args[3] or ".meteorite/swagger-ui.html"
  local spec_url = args[4] or "./openapi.json"
  local html = require("codegen.swagger_ui").emit({ spec_url = spec_url })
  write_file(output, html)
  print("Meteorite Swagger UI asset written: " .. output)
end

return openapi
