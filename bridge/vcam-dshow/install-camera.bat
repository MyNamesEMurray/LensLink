@echo off
REM Registers the LensLink virtual camera with Windows.
REM
REM Needs administrator rights: a DirectShow filter lives in the
REM machine-wide COM registry, which is what lets every app find it.
REM This is the only step in driverless mode that needs elevation, and
REM it happens once.
REM
REM Both architectures are registered when present. A 32-bit app can
REM only load a 32-bit filter, and each regsvr32 writes to its own
REM registry view -- so the 64-bit DLL must be registered by the 64-bit
REM regsvr32 in System32, and the 32-bit one by the copy in SysWOW64.

setlocal
cd /d "%~dp0"

net session >nul 2>&1
if errorlevel 1 (
    echo This must be run as administrator.
    echo Right-click install-camera.bat and choose "Run as administrator".
    pause
    exit /b 1
)

set FAILED=0

if exist "x64\lenslink-vcam.dll" (
    echo Registering the 64-bit camera...
    %SystemRoot%\System32\regsvr32.exe /s "%CD%\x64\lenslink-vcam.dll"
    if errorlevel 1 set FAILED=1
)

if exist "x86\lenslink-vcam.dll" (
    if exist "%SystemRoot%\SysWOW64\regsvr32.exe" (
        echo Registering the 32-bit camera ^(for 32-bit apps^)...
        %SystemRoot%\SysWOW64\regsvr32.exe /s "%CD%\x86\lenslink-vcam.dll"
        if errorlevel 1 set FAILED=1
    )
)

if %FAILED%==1 (
    echo.
    echo Registration failed.
    pause
    exit /b 1
)

echo.
echo Done. "LensLink Camera" is now in the camera list.
echo Start lenslink-bridge.exe and point it at your phone, then pick
echo LensLink Camera in Zoom, Discord or any other app.
echo.
echo Note: apps already running will not see it until they restart.
pause
