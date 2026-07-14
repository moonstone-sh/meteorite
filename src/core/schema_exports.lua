--- Public Meteorite schema and pattern exports.

local schema = require("core.schema")
local patterns = require("core.patterns")

local schema_exports = {}

function schema_exports.string(opts) return schema.scalar("string", opts) end
function schema_exports.slug(opts) return schema.scalar("slug", opts) end
function schema_exports.u64(opts) return schema.scalar("u64", opts) end
function schema_exports.i32(opts) return schema.scalar("i32", opts) end
function schema_exports.uuid(opts) return schema.scalar("uuid", opts) end
function schema_exports.hex(opts) return schema.scalar("hex", opts) end
function schema_exports.email(opts) return schema.scalar("email", opts) end
function schema_exports.token(opts) return schema.scalar("token", opts) end
function schema_exports.bool(opts) return schema.scalar("bool", opts) end

function schema_exports.pattern(name_or_source, source_or_opts, opts)
  if type(source_or_opts) == "table" or source_or_opts == nil then
    return patterns.define(nil, name_or_source, source_or_opts)
  end
  return patterns.define(name_or_source, source_or_opts, opts)
end

schema_exports.patterns = patterns

function schema_exports.install(target)
  target.string = schema_exports.string
  target.slug = schema_exports.slug
  target.u64 = schema_exports.u64
  target.i32 = schema_exports.i32
  target.uuid = schema_exports.uuid
  target.hex = schema_exports.hex
  target.email = schema_exports.email
  target.token = schema_exports.token
  target.bool = schema_exports.bool
  target.pattern = schema_exports.pattern
  target.patterns = schema_exports.patterns
  return target
end

return schema_exports
