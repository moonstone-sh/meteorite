local platform = require("clingy.platform")
local compat = require("clingy.compat")
local ps = require("clingy.windows_powershell")
local shell = { windows = true, null = "NUL", executable_suffix = ".exe", quote = platform.quote }
local function command_processor(command)
  -- system()/popen enter cmd.exe, which strips a leading quoted program
  -- differently from an argv launcher. Own the complete /s /c payload.
  return 'cmd /d /v:off /s /c "' .. command .. '"'
end
function shell.run(command)
  return compat.exit_status(os.execute(command_processor(command))) == 0
end
function shell.capture(command)
  local pipe = assert(io.popen(command_processor(command), "r"))
  local output = pipe:read("*a") or ""
  local ok, how, code = pipe:close()
  assert(compat.exit_status(ok, how, code) == 0, "command failed: " .. command)
  return output
end
local function query(script)
  return shell.capture(ps.command("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); " .. script))
end
function shell.current_dir()
  return (query("(Get-Location).ProviderPath"):gsub("[\r\n]+$", ""):gsub("\\", "/"))
end
function shell.mkdir(path)
  assert(shell.run(ps.command("$ErrorActionPreference='Stop'; [void][IO.Directory]::CreateDirectory(" .. ps.literal(path) .. ")")), "cannot create directory " .. path)
end
function shell.is_dir(path)
  return query("if([IO.Directory]::Exists(" .. ps.literal(path) .. ")) { 'yes' }"):find("yes",1,true) ~= nil
end
local function walk(root, links)
  -- Explicitly stop at reparse points. Static-root validation can report them
  -- separately, and a junction must never silently expand the source closure.
  local script="$root=[IO.Path]::GetFullPath(" .. ps.literal(root) .. ").TrimEnd('\\'); function Walk($dir) { foreach($file in [IO.Directory]::EnumerateFileSystemEntries($dir)) { $a=[IO.File]::GetAttributes($file); "
  script=script .. "if(($a -band 1024) -ne 0) { " .. (links and "Write-Output $file; " or "") .. "continue }; if(($a -band 16) -ne 0) { Walk $file } " .. (links and "" or "else { Write-Output $file }") .. " } }; Walk $root"
  local result={}
  local prefix=(root:gsub("\\","/")):gsub("/+$", "")
  if not prefix:match("^[A-Za-z]:/") and prefix:sub(1,2)~="//" then prefix=shell.current_dir() .. "/" .. prefix end
  prefix=prefix:gsub("/%.$", "")
  for file in query(script):gmatch("[^\r\n]+") do
    local normalized=file:gsub("\\", "/")
    assert(normalized:sub(1,#prefix):lower()==prefix:lower(),"directory escaped source root")
    result[#result+1]=normalized:sub(#prefix+2)
  end
  table.sort(result)
  return result
end
function shell.files(root) return walk(root,false) end
function shell.symlinks(root) return walk(root,true) end
return shell
