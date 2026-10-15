--- Build-time facts, owned by the loader and captured separately by each app.
--- This module does not read environment variables or process globals.
local M = {}
local active = nil
local modes = {dev=true, hybrid_dev=true, hybrid=true, static=true, ['release-hybrid']=true, ['release-static']=true}
function M.create(mode)
  mode = mode or 'dev'
  if not modes[mode] then error('meteorite build context: unsupported mode '..tostring(mode), 2) end
  return {mode=mode, release=mode=='release-hybrid' or mode=='release-static'}
end
function M.current()
  return M.create(active and active.mode or 'dev')
end
--- Execute synchronous graph declaration in a scoped build context. Nested
--- loads restore the outer context, including when declaration fails.
function M.with(context, declare)
  if type(context)~='table' then error('meteorite build context: expected context table',2) end
  local next_context=M.create(context.mode)
  if type(declare)~='function' then error('meteorite build context: expected declaration function',2) end
  local previous=active
  active=next_context
  local ok,value=pcall(declare,M.current())
  active=previous
  if not ok then error(value,0) end
  return value
end
return M
