--- Template renderer for Zig code generation.
--- Reads .tpl files and substitutes {{key}} placeholders with values.
---
--- @class TemplateRenderer
--- @field render fun(tpl: string, vars: table): string  Render a template string by replacing {{key}} placeholders
--- @field render_file fun(path: string, vars: table): string|nil, string|nil  Render a template file

---@type TemplateRenderer
local template = {}

--- Render a template string by replacing {{key}} placeholders.
--- Supports {{key}} for simple substitution.
--- @param tpl string  Template text with {{key}} placeholders
--- @param vars table  Key-value table of substitutions
--- @return string  Rendered text
--- Render a template string by replacing {{key}} placeholders.
---@param tpl string  Template text with {{key}} placeholders
---@param vars table  Key-value table of substitutions
---@return string  Rendered text
function template.render(tpl, vars)
  return (tpl:gsub("{{(%w+)}}", function(key)
    local value = vars[key]
    if value == nil then return "" end
    return tostring(value)
  end))
end

--- Render a template file by reading it and substituting placeholders.
--- @param path string  Path to the .tpl file
--- @param vars table  Key-value table of substitutions
--- @return string|nil  Rendered text, or nil if file not found
--- @return string|nil  Error message on failure
--- Render a template file by reading it and substituting placeholders.
---@param path string  Path to the .tpl file
---@param vars table  Key-value table of substitutions
---@return string|nil  Rendered text, or nil if file not found
---@return string|nil  Error message on failure
function template.render_file(path, vars)
  local file = io.open(path, "rb")
  if not file then return nil, "template file not found: " .. path end
  local content = file:read("*a")
  file:close()
  return template.render(content, vars or {})
end

return template
