@echo off
setlocal EnableDelayedExpansion

set "clink_batch_vs2019=%~dp0.build\vs2019\bin\debug\clink.bat"
set "clink_batch_vs2022=%~dp0.build\vs2022\bin\debug\clink.bat"
set "clink_batch_vs2022_release=%~dp0.build\vs2022\bin\release\clink.bat"

if exist "%clink_batch_vs2019%" (
    echo call "%clink_batch_vs2019%"
    call "%clink_batch_vs2019%"
) else if exist "%clink_batch_vs2022%" (
    echo call "%clink_batch_vs2022%"
    call "%clink_batch_vs2022%"
) else if exist "%clink_batch_vs2022_release%" (
    echo call "%clink_batch_vs2022_release%"
    call "%clink_batch_vs2022_release%"
) else (
    echo "Failed to find 'clink.bat' in build directory."
    exit /b 80
)

exit /b 0
