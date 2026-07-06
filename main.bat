@echo off
setlocal EnableExtensions
cd /d "%~dp0"

call :ensure_admin
if errorlevel 1 exit /b %errorlevel%

:menu
cls
echo.
echo ==========================
echo   Seewo Housekeeper Tool
echo ==========================
echo.
echo 1. Unlock / unfreeze - reboot immediately
echo.
echo 2. Official update
echo.
echo 3. VPS update
echo.
echo 4. Lock / freeze - reboot immediately
echo.
echo 0. Exit
echo.
echo ==========================
echo.
set /p "CHOICE=Select option: "

if "%CHOICE%"=="1" call :run_automation "unlock.exe" "src\unlock.ahk" "Unlock / unfreeze"
if "%CHOICE%"=="2" call :run_batch "download.bat" "Official update"
if "%CHOICE%"=="3" call :run_batch "backup.bat" "VPS update"
if "%CHOICE%"=="4" call :run_automation "lock.exe" "src\lock.ahk" "Lock / freeze"
if "%CHOICE%"=="0" exit /b 0

echo.
echo Invalid option.
pause
goto :menu

:run_batch
set "MODULE=%~1"
set "TITLE=%~2"
echo.
echo Running: %TITLE%
echo.
if not exist "%~dp0%MODULE%" (
    echo ERROR: %MODULE% was not found.
    pause
    goto :menu
)
call "%~dp0%MODULE%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo %TITLE% finished with exit code %EXIT_CODE%.
if "%EXIT_CODE%"=="3010" echo Reboot is required to finish the update.
pause
goto :menu

:run_automation
set "EXE=%~1"
set "AHK=%~2"
set "TITLE=%~3"
echo.
echo Running: %TITLE%
echo WARNING: This action may reboot the computer immediately.
echo.

if exist "%~dp0%EXE%" (
    "%~dp0%EXE%"
    set "EXIT_CODE=%ERRORLEVEL%"
    goto :automation_done
)

where AutoHotkey.exe >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    if exist "%~dp0%AHK%" (
        AutoHotkey.exe "%~dp0%AHK%"
        set "EXIT_CODE=%ERRORLEVEL%"
        goto :automation_done
    )
)

echo ERROR: %EXE% was not found.
echo Development fallback also failed: AutoHotkey.exe or %AHK% was not found.
set "EXIT_CODE=2"

:automation_done
echo.
echo %TITLE% finished with exit code %EXIT_CODE%.
if not "%EXIT_CODE%"=="0" (
    echo See logs\freeze for details.
    pause
)
goto :menu

:ensure_admin
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0
echo Requesting administrator privileges...
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 1
