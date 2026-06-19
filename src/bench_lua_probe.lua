local M = {}
M.count = 0
function M.hit()
  M.count = M.count + 1
  return tostring(M.count)
end
return M
