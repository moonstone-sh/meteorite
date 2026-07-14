--- Public Meteorite handler factory and site macro exports.

local handler_factories = require("core.handler_factories")
local site_macro = require("core.site")

local handler_exports = {}

function handler_exports.zig(path_or_symbol, opts) return handler_factories.zig(path_or_symbol, opts) end
function handler_exports.lua(module_ref) return handler_factories.lua(module_ref) end
function handler_exports.file(path, opts) return handler_factories.file(path, opts) end
function handler_exports.dir(root, opts) return handler_factories.dir(root, opts) end
function handler_exports.site(app, opts) return site_macro.apply(app, opts, handler_factories) end
function handler_exports.handler(kind, ref, opts) return handler_factories.handler(kind, ref, opts) end

function handler_exports.install(target)
  target.zig = handler_exports.zig
  target.lua = handler_exports.lua
  target.file = handler_exports.file
  target.dir = handler_exports.dir
  target.site = handler_exports.site
  target.handler = handler_exports.handler
  return target
end

return handler_exports
