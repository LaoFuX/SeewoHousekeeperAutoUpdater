@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1
cd /d "%~dp0"

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

set "INTERNAL_DIR="
for /d %%D in ("%~dp0*") do (
    if exist "%%~fD\workflow\update-lock-restart.bat" set "INTERNAL_DIR=%%~fD"
)

if not defined INTERNAL_DIR (
    echo ERROR: Internal program folder was not found.
    pause
    exit /b 2
)

set "WORKFLOW=%INTERNAL_DIR%\workflow\update-lock-restart.bat"

if not exist "%WORKFLOW%" (
    echo ERROR: Internal workflow was not found.
    echo %WORKFLOW%
    pause
    exit /b 2
)

call "%WORKFLOW%"
exit /b %ERRORLEVEL%

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges...
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
