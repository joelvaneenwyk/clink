@echo off
setlocal EnableDelayedExpansion

set "clink_solution=%~dp0.build\vs2019\clink.sln"
if not exist "!clink_solution!" set "clink_solution=%~dp0.build\vs2022\clink.sln"
if not exist "!clink_solution!" (
    echo Failed to find Visual Studio solution for clink: "!clink_solution!"
    exit /b 90
)

cd /d "%~dp0"
echo Launching Clink solution in Visual Studio: "!clink_solution!"
start "" "!clink_solution!"
