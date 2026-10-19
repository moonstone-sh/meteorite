local shell=require("cli.shell")
local ps=require("clingy.windows_powershell")
local supervisor=require("clingy.supervisor")
local M={}
-- PID reuse cannot confer ownership. Keep each guardian's creation time and
-- terminate its exact Process handle; its Job Object reaps the server tree.
local owned={}
local function capture(script)
  return shell.capture(ps.command("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); " .. script))
end
function M.sleep(seconds)
  return os.execute(ps.command("Start-Sleep -Milliseconds " .. math.floor(seconds*1000)))
end
function M.pid_running(pid)
  if not pid or not owned[pid] then return false end
  local output=capture("$p=Get-Process -Id " .. pid .. " -ErrorAction SilentlyContinue; if($p -and $p.StartTime.ToUniversalTime().Ticks -eq " .. owned[pid] .. ") { 'alive' }")
  return output:find("alive",1,true)~=nil
end
function M.stop(pid)
  if not pid or not owned[pid] then return end
  capture("$p=Get-Process -Id " .. pid .. " -ErrorAction SilentlyContinue; if($p -and $p.StartTime.ToUniversalTime().Ticks -eq " .. owned[pid] .. ") { $p.Kill(); $p.WaitForExit() }")
  owned[pid]=nil
end
function M.spawn(server, log_file)
  local script_file=log_file .. ".guardian.ps1"
  local script=supervisor.script({argv={server},grace_ms=2000})
  local file=assert(io.open(script_file,"wb")); file:write("\239\187\191",script); file:close()
  -- The guardian stays in the enclosing Clingy job. It owns a nested job so
  -- a rebuild can retire only this server and its descendants.
  local output=capture("$p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('\"'+" .. ps.literal(script_file) .. "+'\"')) -PassThru -NoNewWindow -RedirectStandardOutput " .. ps.literal(log_file) .. " -RedirectStandardError " .. ps.literal(log_file .. ".err") .. "; Write-Output ($p.Id.ToString()+'|'+$p.StartTime.ToUniversalTime().Ticks.ToString())")
  local pid,ticks=output:match("(%d+)|(%d+)")
  assert(pid,"server guardian did not start: " .. output)
  owned[pid]=ticks
  return pid
end
function M.fingerprint(paths, exclude)
  if #paths==0 then return "" end
  local roots,excluded={},{}
  for _,path in ipairs(paths) do roots[#roots+1]=ps.literal(path) end
  for _,path in ipairs(exclude or {}) do excluded[#excluded+1]=ps.literal(path) end
  return capture("$excluded=@(" .. table.concat(excluded,",") .. ") | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\\') }; " ..
    "$files=@(" .. table.concat(roots,",") .. ") | ForEach-Object { if(Test-Path -LiteralPath $_) { Get-ChildItem -LiteralPath $_ -File -Recurse -ErrorAction Stop } }; " ..
    "$files | Sort-Object -Property FullName -Unique | ForEach-Object { $f=$_; $skip=$false; foreach($x in $excluded) { if($f.FullName.Equals($x,[StringComparison]::OrdinalIgnoreCase) -or $f.FullName.StartsWith($x+'\\',[StringComparison]::OrdinalIgnoreCase)) { $skip=$true } }; if(-not $skip) { $hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash; Write-Output ($f.FullName+'|'+$hash) } }")
end
return M
