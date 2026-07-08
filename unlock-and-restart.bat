@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
cd /d "%~dp0"

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

echo.
echo ========================================
echo  Unlock / unfreeze, then reboot
echo ========================================
echo.
echo This workflow will unlock / unfreeze the selected disk.
echo The computer may reboot immediately after the automation finishes.
echo.

call :run_unlock_automation
set "UNLOCK_EXIT_CODE=%ERRORLEVEL%"

echo.
echo Unlock automation finished with exit code %UNLOCK_EXIT_CODE%.
if not "%UNLOCK_EXIT_CODE%"=="0" (
    echo See logs\freeze for details.
    pause
)
exit /b %UNLOCK_EXIT_CODE%

:run_unlock_automation
if exist "%~dp0unlock.exe" (
    "%~dp0unlock.exe"
    exit /b %ERRORLEVEL%
)

where AutoHotkey.exe >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    if exist "%~dp0src\unlock.ahk" (
        AutoHotkey.exe "%~dp0src\unlock.ahk"
        exit /b %ERRORLEVEL%
    )
)

echo ERROR: unlock.exe was not found.
echo Development fallback also failed: AutoHotkey.exe or src\unlock.ahk was not found.
exit /b 2

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges...
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
