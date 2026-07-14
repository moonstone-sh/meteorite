--- Public Meteorite utility exports that do not depend on app internals.

local profile_mod = require("core.profile")

local utility_exports = {}

utility_exports.profiles = profile_mod.profiles

function utility_exports.profile(name_or_table, opts)
  return profile_mod.define(name_or_table, opts)
end

function utility_exports.validation_error(message)
  return { kind = "validation_error", message = message }
end

function utility_exports.context(map)
  map = map or {}
  map.__meteorite_context = true
  return map
end

function utility_exports.enum(value)
  return { __meteorite_enum = true, value = value }
end

function utility_exports.install(target)
  target.profiles = utility_exports.profiles
  target.profile = utility_exports.profile
  target.validation_error = utility_exports.validation_error
  target.context = utility_exports.context
  target._enum = utility_exports.enum
  return target
end

return utility_exports
