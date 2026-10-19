@echo off
setlocal DisableDelayedExpansion
set "ROOT=%~dp0.."
if exist "%ROOT%\src\cli\main.lua" (
  set "ENTRY=%ROOT%\src\cli\main.lua"
) else if exist "%ROOT%\meteorite\cli\main.lua" (
  set "ENTRY=%ROOT%\meteorite\cli\main.lua"
) else if exist "%ROOT%\files\meteorite\cli\main.lua" (
  set "ENTRY=%ROOT%\files\meteorite\cli\main.lua"
) else (
  echo meteorite: cannot locate cli/main.lua near %ROOT% 1>&2
  exit /b 1
)
if not defined LUA_BIN set "LUA_BIN=lua.exe"
"%LUA_BIN%" "%ENTRY%" %*
exit /b %ERRORLEVEL%
