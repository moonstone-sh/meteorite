package.path = "src/?.lua;src/?/init.lua;tests/?.lua;;"

local test = require("test")
local swagger_ui = require("codegen.swagger_ui")

test "swagger ui emits static html shell" (function()
  local html = swagger_ui.emit({ title = "My API", spec_url = "./openapi.json" })
  test.assert_true(html:find("<!doctype html>", 1, true), "doctype")
  test.assert_true(html:find("swagger-ui-dist@5/swagger-ui.css", 1, true), "css")
  test.assert_true(html:find("url: './openapi.json'", 1, true), "spec url")
end)

test "swagger ui escapes title and javascript spec url" (function()
  local html = swagger_ui.emit({ title = "<API>", spec_url = "./it's</script>.json" })
  test.assert_true(html:find("&lt;API&gt;", 1, true), "escaped title")
  test.assert_true(html:find("./it\\'s\\x3C/script>.json", 1, true), "escaped script url")
end)

test.run()
