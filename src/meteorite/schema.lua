local schema = {}

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
