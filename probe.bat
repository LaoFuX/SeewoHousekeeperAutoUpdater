@echo off
setlocal

cd /d "%~dp0"

if not exist "tools\probe_env.ps1" (
    echo ERROR: tools\probe_env.ps1 was not found.
    pause
    exit /b 2
)

if not exist "logs\probe" (
    mkdir "logs\probe" >nul 2>&1
)

echo.
echo ========================================
echo  Environment Probe
echo ========================================
echo.
echo This script is read-only.
echo It collects Windows, app, window, and UI Automation data.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\probe_env.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo Probe completed.
) else (
    echo Probe failed with exit code %EXIT_CODE%.
)
echo.
pause
exit /b %EXIT_CODE%
