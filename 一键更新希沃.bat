@echo off
:: ============================================================
:: Full Auto Update - Entry Point
:: Double-click this file to start the full automation.
:: Prerequisite: <program folder>\winpe\boot.wim exists
::               (auto-deployed to D:\WinPE on first run).
:: ============================================================
setlocal EnableExtensions

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

set "ORCH="
for /d %%D in ("%~dp0*") do (
    if exist "%%~fD\workflow\orchestrate.bat" set "ORCH=%%~fD\workflow\orchestrate.bat"
)
if not defined ORCH (
    echo ERROR: Cannot find the program folder ^(workflow\orchestrate.bat^).
    echo.
    echo Make sure the project folder structure is intact.
    pause
    exit /b 1
)

call "%ORCH%"
set "_EC=%ERRORLEVEL%"
if not "%_EC%"=="0" (
    echo.
    echo ERROR: Orchestrator exited with code %_EC%.
    pause
)
exit /b %_EC%

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
