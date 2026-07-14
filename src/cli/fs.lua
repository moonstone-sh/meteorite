local fs = {}

function fs.read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

function fs.path_join(a, b)
  if a == "." or a == "" then return b end
  return a .. "/" .. b
end

return fs
