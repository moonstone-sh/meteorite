local shell = { windows = false, null = "/dev/null", executable_suffix = "" }

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

function shell.mkdir(path)
  assert(shell.run("mkdir -p " .. shell.quote(path)), "cannot create directory " .. path)
end
function shell.files(root)
  local files = {}
  for file in shell.capture("cd " .. shell.quote(root) .. " && find . -type f | sort"):gmatch("[^\r\n]+") do
    files[#files + 1] = file:gsub("^%./", "")
  end
  return files
end
shell.execute = os.execute
return shell
