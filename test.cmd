@echo off
setlocal EnableDelayedExpansion EnableExtensions
set __DBG=
set __ME=%~dp0

:arg
if x%1x == x?x goto :usage
if x%1x == x/?x goto :usage
if x%1x == x-?x goto :usage
if x%1x == x/hx goto :usage
if x%1x == x-hx goto :usage
if x%1x == x/helpx goto :usage
if x%1x == x--helpx goto :usage
if x%1x == xhelpx goto :usage
if x%1x == x/dbgx set __DBG=call devenv /debugexe
if x%1x == x/dbgx shift & goto :arg

set "_exe="
if not exist "!_exe!" set "_exe=%__ME%.build\vs2022\bin\release\clink_test_x64.exe"
if not exist "!_exe!" set "_exe=%__ME%.build\vs2019\bin\debug\clink_test_x64.exe"
if not exist "!_exe!" set "_exe=%__ME%.build\vs2022\bin\debug\clink_test_x64.exe"

%__DBG% "!_exe!" %1 %2 %3
goto :eof

:usage
echo Usage:  test [/? /dbg] [test name prefix]
echo.
echo   Run clink_test_x64.exe.
echo.
echo.  /?        Show usage info.
echo   /dbg      Run test under the debugger.
echo   -d        Load Lua debugger.
echo   -t        Show execution time.
echo.
echo If [test name prefix] is included, then it only runs tests whose name begins
echo with the specified prefix.
goto :eof
