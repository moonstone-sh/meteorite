-- POSIX dev-loop operations. The state machine stays in cli/dev.lua.
local M = {}
local shell=require("cli.shell")
function M.sleep(seconds) return os.execute("sleep " .. tostring(seconds)) end
function M.pid_running(pid)
  return pid~=nil and shell.run("kill -0 " .. tostring(pid) .. " >/dev/null 2>&1")
end
function M.stop(pid)
  if not M.pid_running(pid) then return end
  shell.run("kill -TERM " .. tostring(pid) .. " >/dev/null 2>&1")
  for _=1,20 do if not M.pid_running(pid) then return end; M.sleep(.1) end
  shell.run("kill -9 " .. tostring(pid) .. " >/dev/null 2>&1 || true")
end
function M.spawn(server, log_file)
  return shell.capture("(trap - INT TERM HUP; exec " .. shell.quote(server) .. ") >" .. shell.quote(log_file) .. " 2>&1 & echo $!"):match("%d+")
end
function M.fingerprint(paths, exclude)
  if #paths==0 then return "" end
  local quoted,prune={},{}
  for _,path in ipairs(paths) do quoted[#quoted+1]=shell.quote(path) end
  for _,path in ipairs(exclude or {}) do
    prune[#prune+1]="-path " .. shell.quote(path)
    prune[#prune+1]="-path " .. shell.quote(path .. "/*")
  end
  local find="find " .. table.concat(quoted," ")
  if #prune>0 then find=find .. " \\( " .. table.concat(prune," -o ") .. " \\) -prune -o" end
  return shell.capture(find .. " -type f -print 2>/dev/null | sort | while IFS= read -r f; do stat -f '%m %z %N' \"$f\" 2>/dev/null || stat -c '%Y %s %n' \"$f\" 2>/dev/null; done")
end
return M
