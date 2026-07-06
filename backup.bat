@echo off
setlocal
chcp 65001 >nul 2>&1
cd /d "%~dp0"

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

echo.
echo ========================================
echo  VPS Update
echo ========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\seewo-update.ps1" -Source Vps
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Module exit code: %EXIT_CODE%
exit /b %EXIT_CODE%

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges...
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
