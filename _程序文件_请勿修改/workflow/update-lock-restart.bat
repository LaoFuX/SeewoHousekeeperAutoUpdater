@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
for %%I in ("%~dp0..") do set "APP_ROOT=%%~fI"
cd /d "%APP_ROOT%"

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

echo.
echo ========================================
echo  Update Seewo, then lock and reboot
echo ========================================
echo.
echo This workflow will:
echo   1. Run the official update module
echo   2. Lock / freeze the selected disk
echo   3. Reboot the computer immediately
echo.
echo If the update fails, locking will NOT start.
echo.

if not exist "%APP_ROOT%\update\download.bat" (
    echo ERROR: update\download.bat was not found.
    pause
    exit /b 2
)

call "%APP_ROOT%\update\download.bat"
set "UPDATE_EXIT_CODE=%ERRORLEVEL%"

echo.
echo Update module finished with exit code %UPDATE_EXIT_CODE%.

if "%UPDATE_EXIT_CODE%"=="0" goto :run_lock
if "%UPDATE_EXIT_CODE%"=="3010" goto :run_lock

echo.
echo ERROR: Update failed. Lock step was skipped.
echo See "%APP_ROOT%\logs\update" for details.
pause
exit /b %UPDATE_EXIT_CODE%

:run_lock
echo.
echo Starting lock / freeze automation.
echo WARNING: This action may reboot the computer immediately.
echo.

call :run_lock_automation
set "LOCK_EXIT_CODE=%ERRORLEVEL%"

echo.
echo Lock automation finished with exit code %LOCK_EXIT_CODE%.
if not "%LOCK_EXIT_CODE%"=="0" (
    echo See "%APP_ROOT%\logs\freeze" for details.
    pause
)
exit /b %LOCK_EXIT_CODE%

:run_lock_automation
if exist "%APP_ROOT%\bin\lock.exe" (
    "%APP_ROOT%\bin\lock.exe"
    exit /b %ERRORLEVEL%
)

where AutoHotkey.exe >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    if exist "%APP_ROOT%\src\lock.ahk" (
        AutoHotkey.exe "%APP_ROOT%\src\lock.ahk"
        exit /b %ERRORLEVEL%
    )
)

echo ERROR: bin\lock.exe was not found.
echo Development fallback also failed: AutoHotkey.exe or src\lock.ahk was not found.
exit /b 2

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges...
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
