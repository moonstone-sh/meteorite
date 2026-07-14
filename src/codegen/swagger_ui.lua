local swagger_ui = {}

local function html_escape(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
end

local function js_string(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("<", "\\x3C")
  return "'" .. value .. "'"
end

function swagger_ui.emit(opts)
  opts = opts or {}
  local title = opts.title or "Meteorite API Docs"
  local spec_url = opts.spec_url or "./openapi.json"
  return table.concat({
    "<!doctype html>",
    "<html lang=\"en\">",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "  <title>" .. html_escape(title) .. "</title>",
    "  <link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui.css\">",
    "  <style>body{margin:0;background:#fafafa}.topbar{display:none}</style>",
    "</head>",
    "<body>",
    "  <div id=\"swagger-ui\"></div>",
    "  <script src=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>",
    "  <script>",
    "    window.addEventListener('load', function() {",
    "      SwaggerUIBundle({",
    "        url: " .. js_string(spec_url) .. ",",
    "        dom_id: '#swagger-ui',",
    "        deepLinking: true,",
    "        presets: [SwaggerUIBundle.presets.apis],",
    "        layout: 'BaseLayout'",
    "      });",
    "    });",
    "  </script>",
    "</body>",
    "</html>",
    "",
  }, "\n")
end

return swagger_ui
