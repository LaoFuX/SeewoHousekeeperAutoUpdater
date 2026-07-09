@echo off
:: ============================================================
:: Phase 3 - Final automation step (runs as RunOnce after login)
::
:: Triggered by: HKLM\...\RunOnce\SeewoAutoUpdate
:: Location:     D:\SeewoHelper\post-thaw-update.bat
::
:: What this script does:
::   1. Request admin elevation if not already elevated
::   2. Run the Seewo update (seewo-update.ps1)
::   3. On success, run lock.exe to re-freeze Deep Freeze
::   4. Reboot
:: ============================================================
setlocal EnableExtensions

:: - Prevent double-execution -
set "LOCK_FILE=%~dp0_phase3_running.lock"
if exist "%LOCK_FILE%" (
    echo Phase 3 is already running. Exiting.
    exit /b 0
)
echo %DATE% %TIME% > "%LOCK_FILE%"

:: - Ensure admin -
net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator privileges ...
    powershell -NoProfile -WindowStyle Hidden -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs"
    del /f /q "%LOCK_FILE%" >nul 2>&1
    exit /b 0
)

:: - Set up logging -
set "LOG_DIR=%~dp0logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "LOG=%LOG_DIR%\phase3_%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log"
set "LOG=%LOG: =0%"

call :log "========================================="
call :log " Phase 3 started"
call :log "========================================="

:: - Run Seewo update -
call :log "Running Seewo update ..."
set "UPDATE_SCRIPT=%~dp0seewo-update.ps1"

if not exist "%UPDATE_SCRIPT%" (
    call :log "ERROR: seewo-update.ps1 not found at %UPDATE_SCRIPT%"
    goto :fail
)

:: seewo-update.ps1 writes its own log file under D:\SeewoHelper\logs\update\.
:: We do NOT redirect its output here, so its live colored progress (download
:: percentage, install step) stays visible on screen instead of vanishing into
:: a file. Phase 3's own step markers still go to %LOG% via :log.
powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_SCRIPT%" -Source Auto
set "UPDATE_CODE=%ERRORLEVEL%"
call :log "Update exit code: %UPDATE_CODE%"

:: Exit codes 0 and 3010 both mean success (3010 = needs reboot, handled below)
if "%UPDATE_CODE%"=="0"    goto :run_lock
if "%UPDATE_CODE%"=="3010" goto :run_lock

call :log "ERROR: Update failed with code %UPDATE_CODE%. Lock step skipped."
goto :fail

:: - Run lock.exe -
:run_lock
call :log "Running lock.exe to re-freeze Deep Freeze ..."
set "LOCK_EXE=%~dp0lock.exe"

if not exist "%LOCK_EXE%" (
    call :log "ERROR: lock.exe not found at %LOCK_EXE%"
    goto :fail
)

"%LOCK_EXE%"
set "LOCK_CODE=%ERRORLEVEL%"
call :log "lock.exe exit code: %LOCK_CODE%"

if not "%LOCK_CODE%"=="0" (
    call :log "WARNING: lock.exe returned non-zero. Proceeding with reboot anyway."
)

:: - Reboot -
call :log "Phase 3 complete. Rebooting ..."
call :wipe_config
del /f /q "%LOCK_FILE%" >nul 2>&1
shutdown /r /t 10 /c "SeewoAutoUpdate Phase 3 complete. Rebooting in 10 seconds."
exit /b 0

:: - Failure path -
:fail
call :log "Phase 3 FAILED. See log: %LOG%"
call :wipe_config
del /f /q "%LOCK_FILE%" >nul 2>&1
echo.
echo Phase 3 failed. Log saved to:
echo   %LOG%
echo.
pause
exit /b 1

:: - Remove the deployed config (contains the freeze password) -
:: The password lives on the USB drive and is copied to D:\SeewoHelper\config
:: only for the duration of the run. Delete it here so the plaintext password
:: never persists on this machine's internal D: drive after use.
:wipe_config
if exist "%~dp0config\app.ini" del /f /q "%~dp0config\app.ini" >nul 2>&1
if exist "%~dp0config" rd /s /q "%~dp0config" >nul 2>&1
call :log "Deployed config (password) removed from D:\SeewoHelper\config."
exit /b 0

:: - Logging helper -
:log
echo [%DATE% %TIME%] %~1
echo [%DATE% %TIME%] %~1 >> "%LOG%"
exit /b 0
