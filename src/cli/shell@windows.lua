local platform = require("clingy.platform")
local compat = require("clingy.compat")
local shell = { windows = true, null = "NUL", executable_suffix = ".exe", quote = platform.quote }
function shell.run(command)
  return compat.exit_status(os.execute(command)) == 0
end
function shell.capture(command)
  local pipe = assert(io.popen(command, "r"))
  local output = pipe:read("*a") or ""
  local ok, how, code = pipe:close()
  assert(compat.exit_status(ok, how, code) == 0, "command failed: " .. command)
  return output
end
function shell.current_dir()
  return (shell.capture("cd"):gsub("[\r\n]+$", ""):gsub("\\", "/"))
end
function shell.mkdir(path)
  assert(shell.run("if not exist " .. shell.quote(path) .. " mkdir " .. shell.quote(path)), "cannot create directory " .. path)
end
function shell.files(root)
  local files = {}
  for file in shell.capture("cd /d " .. shell.quote(root) .. " && dir /b /s /a:-d"):gmatch("[^\r\n]+") do
    local normalized = file:gsub("\\", "/")
    local base = root:gsub("\\", "/")
    if not base:match("^[A-Za-z]:/") then base = shell.current_dir() .. "/" .. base end
    base = base:gsub("/%.$", ""):gsub("/+$", "")
    assert(normalized:sub(1, #base):lower() == base:lower(), "directory escaped template root")
    files[#files + 1] = normalized:sub(#base + 2)
  end
  table.sort(files)
  return files
end
function shell.is_dir(path)
  return shell.run("if exist " .. shell.quote(path .. "/NUL") .. " (exit /b 0) else (exit /b 1)")
end
function shell.symlinks(root)
  local result = {}
  local pipe = assert(io.popen("cd /d " .. shell.quote(root) .. " && dir /b /s /a:l 2>NUL", "r"))
  for line in pipe:lines() do result[#result + 1] = line end
  pipe:close()
  return result
end
return shell
