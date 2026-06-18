local schema = {}

---@class MeteoriteSchemaBase
---@field type string
---@field optional boolean
---@field decode boolean
---@field max_len? integer
---@field exact_len? integer
---@field min? integer
---@field max? integer
---@field pattern? any
---@field validator? any

---@param kind string
---@param opts? table
---@return MeteoriteSchemaBase
function schema.scalar(kind, opts)
  opts = opts or {}
  local out = {
    type = kind,
    optional = opts.optional == true,
    decode = opts.decode == true,
  }
  if opts.max then out.max_len = opts.max end
  if opts.max_len then out.max_len = opts.max_len end
  if opts.len then out.exact_len = opts.len end
  if opts.min then out.min = opts.min end
  if opts.pattern then out.pattern = opts.pattern end
  if opts.validate then
    if type(opts.validate) == "string" then
      out.validator = { kind = "zig", symbol = opts.validate }
    elseif type(opts.validate) == "table" then
      out.validator = opts.validate
    elseif type(opts.validate) == "function" then
      out.validator = { kind = "inline_lua", value = opts.validate }
    end
  end
  return out
end

return schema
