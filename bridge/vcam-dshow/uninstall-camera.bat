@echo off
REM Removes the LensLink virtual camera from Windows.
REM Run this BEFORE deleting the folder: once the DLL is gone, Windows
REM cannot unregister it and the camera lingers as a broken entry in
REM every app's list.

setlocal
cd /d "%~dp0"

net session >nul 2>&1
if errorlevel 1 (
    echo This must be run as administrator.
    echo Right-click uninstall-camera.bat and choose "Run as administrator".
    pause
    exit /b 1
)

if exist "x64\lenslink-vcam.dll" (
    echo Removing the 64-bit camera...
    %SystemRoot%\System32\regsvr32.exe /s /u "%CD%\x64\lenslink-vcam.dll"
)

if exist "x86\lenslink-vcam.dll" (
    if exist "%SystemRoot%\SysWOW64\regsvr32.exe" (
        echo Removing the 32-bit camera...
        %SystemRoot%\SysWOW64\regsvr32.exe /s /u "%CD%\x86\lenslink-vcam.dll"
    )
)

echo.
echo Done.
pause
