--- Small dependency-free string template helper.
---
--- This is intentionally not an HTML template engine: it only substitutes
--- `{{name}}` placeholders with values from a table. Escaping and control flow
--- belong to app-selected libraries such as etlua.

local template = {}

--- Render a template string by replacing {{key}} placeholders.
---@param tpl string  Template text with {{key}} placeholders
---@param vars table  Key-value table of substitutions
---@return string  Rendered text
function template.render(tpl, vars)
  vars = vars or {}
  return (tostring(tpl or ""):gsub("{{(%w+)}}", function(key)
    local value = vars[key]
    if value == nil then return "" end
    return tostring(value)
  end))
end

--- Render a template file by reading it and substituting placeholders.
---@param path string  Path to the template file
---@param vars table  Key-value table of substitutions
---@return string|nil  Rendered text, or nil if file not found
---@return string|nil  Error message on failure
function template.render_file(path, vars)
  local file = io.open(path, "rb")
  if not file then return nil, "template file not found: " .. tostring(path) end
  local content = file:read("*a")
  file:close()
  return template.render(content, vars or {})
end

return template
