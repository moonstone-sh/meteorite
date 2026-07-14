local shell = {}

function shell.quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function shell.run(command)
  local ok, _, code = os.execute(command)
  return ok == true or ok == 0 or code == 0
end

function shell.capture(command)
  local pipe = io.popen(command, "r")
  if not pipe then return "" end
  local data = pipe:read("*a") or ""
  pipe:close()
  return data
end

function shell.current_dir()
  local pipe = io.popen("pwd", "r")
  if not pipe then return "." end
  local value = (pipe:read("*l") or "."):gsub("/+$", "")
  pipe:close()
  return value ~= "" and value or "."
end

return shell
