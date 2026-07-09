@echo off
:: ============================================================
:: Seewo Auto-Update -- Main Orchestrator
::
:: Called by: update-seewo.bat (root entry, already elevated)
::
:: Steps:
::   0. Auto-deploy WinPE files to D:\WinPE\ if missing
::   1. Deploy D:\SeewoHelper\ (post-thaw-update.bat, seewo-update.ps1, lock.exe, marker)
::   2. Run unlock.exe to unfreeze Deep Freeze for next boot
::   3. Run setup-winpe-boot.ps1 to create one-shot WinPE boot entry
::   4. Reboot -> WinPE (inject RunOnce) -> Windows (update + re-freeze)
:: ============================================================
setlocal EnableExtensions DisableDelayedExpansion

:: APP_ROOT = the program folder (parent of this script's workflow\ directory)
for %%I in ("%~dp0..") do set "APP_ROOT=%%~fI"
cd /d "%APP_ROOT%"

echo.
echo ========================================================
echo  Seewo Auto-Update -- Unlock + WinPE boot setup
echo ========================================================
echo.

:: - Step 0: Ensure WinPE files are on D:\ (auto-deploy on first run) -
set "WINPE_DEST=D:\WinPE"
for %%I in ("%APP_ROOT%\winpe") do set "WINPE_SRC=%%~fI"

if not exist "%WINPE_DEST%\boot.wim" (
    echo [0/5] D:\WinPE\boot.wim not found. Deploying from project folder ...
    echo        Source: %WINPE_SRC%
    echo.

    if not exist "%WINPE_SRC%\boot.wim" (
        echo ERROR: boot.wim not found in project WinPE folder:
        echo   %WINPE_SRC%\boot.wim
        echo.
        echo Build it first: winpe-builder\build-winpe.ps1
        pause
        exit /b 2
    )
    if not exist "%WINPE_SRC%\boot.sdi" (
        echo ERROR: boot.sdi not found in project WinPE folder:
        echo   %WINPE_SRC%\boot.sdi
        pause
        exit /b 2
    )

    if not exist "%WINPE_DEST%" mkdir "%WINPE_DEST%"
    echo  Copying boot.wim, approx 300 MB, please wait ...
    copy /y "%WINPE_SRC%\boot.wim" "%WINPE_DEST%\boot.wim" >nul
    if errorlevel 1 (
        echo ERROR: Failed to copy boot.wim.
        pause
        exit /b 2
    )
    copy /y "%WINPE_SRC%\boot.sdi" "%WINPE_DEST%\boot.sdi" >nul
    if errorlevel 1 (
        echo ERROR: Failed to copy boot.sdi.
        pause
        exit /b 2
    )
    echo [0/5] WinPE files deployed to %WINPE_DEST%.
) else (
    echo [0/5] D:\WinPE already exists. Skipping copy.
)

:: - Step 1: Deploy D:\SeewoHelper\ -
echo [1/5] Deploying D:\SeewoHelper\ ...
set "SEEWO_HELPER=D:\SeewoHelper"
if not exist "%SEEWO_HELPER%" mkdir "%SEEWO_HELPER%"
if not exist "%SEEWO_HELPER%\logs" mkdir "%SEEWO_HELPER%\logs"

:: post-thaw-update.bat -- runs in Windows after Deep Freeze thaws
set "PHASE3_SRC=%APP_ROOT%\workflow\post-thaw-update.bat"
for %%F in ("%PHASE3_SRC%") do set "PHASE3_SRC=%%~fF"
if not exist "%PHASE3_SRC%" (
    echo ERROR: post-thaw-update.bat not found at %PHASE3_SRC%
    pause
    exit /b 2
)
copy /y "%PHASE3_SRC%" "%SEEWO_HELPER%\post-thaw-update.bat" >nul

:: seewo-update.ps1 -- update logic
set "UPDATE_PS1=%APP_ROOT%\update\scripts\seewo-update.ps1"
if not exist "%UPDATE_PS1%" (
    echo ERROR: seewo-update.ps1 not found at %UPDATE_PS1%
    pause
    exit /b 2
)
copy /y "%UPDATE_PS1%" "%SEEWO_HELPER%\seewo-update.ps1" >nul

:: lock.exe -- Deep Freeze re-freeze automation
set "LOCK_EXE=%APP_ROOT%\bin\lock.exe"
if not exist "%LOCK_EXE%" (
    echo ERROR: lock.exe not found at %LOCK_EXE%
    pause
    exit /b 2
)
copy /y "%LOCK_EXE%" "%SEEWO_HELPER%\lock.exe" >nul

:: app.ini -- lock.exe and seewo-update.ps1 both read config from a sibling
:: config\app.ini. lock.exe (running from D:\SeewoHelper) resolves it as
:: D:\SeewoHelper\config\app.ini, so deploy the config there. Without this the
:: freeze password and LauncherPath are empty (phase 3 lock prompts for a
:: password and cannot find the Seewo window).
set "APP_INI=%APP_ROOT%\config\app.ini"
if not exist "%APP_INI%" (
    echo ERROR: config\app.ini not found at %APP_INI%
    pause
    exit /b 2
)
if not exist "%SEEWO_HELPER%\config" mkdir "%SEEWO_HELPER%\config"
copy /y "%APP_INI%" "%SEEWO_HELPER%\config\app.ini" >nul

:: Marker file -- Phase 2 (WinPE) uses this to detect the SeewoHelper drive
echo SeewoAutoUpdate deployment marker > "%SEEWO_HELPER%\_seewo_marker.txt"

echo [1/5] D:\SeewoHelper deployed.

:: - Step 2: Run unlock.exe -
echo [2/5] Running unlock automation ...
echo.

:: Run unlock.exe or fall back to AutoHotkey source.
:: NOTE: set "UNLOCK_CODE=..." must be OUTSIDE the if-block to capture
::       the correct ERRORLEVEL with DisableDelayedExpansion.
if exist "%APP_ROOT%\bin\unlock.exe" (
    "%APP_ROOT%\bin\unlock.exe"
) else (
    where AutoHotkey.exe >nul 2>&1
    if not errorlevel 1 (
        if exist "%APP_ROOT%\src\unlock.ahk" (
            AutoHotkey.exe "%APP_ROOT%\src\unlock.ahk"
        ) else (
            echo ERROR: src\unlock.ahk not found.
            pause
            exit /b 2
        )
    ) else (
        echo ERROR: bin\unlock.exe not found and AutoHotkey.exe is not in PATH.
        pause
        exit /b 2
    )
)
set "UNLOCK_CODE=%ERRORLEVEL%"

echo.
if not "%UNLOCK_CODE%"=="0" (
    echo ERROR: unlock.exe failed with code %UNLOCK_CODE%.
    echo See logs for details.
    pause
    exit /b %UNLOCK_CODE%
)
echo [2/5] Unlock automation succeeded.

:: - Step 3: BCD setup -
echo [3/5] Creating WinPE BCD entry ...
echo.

set "BCD_SCRIPT=%APP_ROOT%\workflow\setup-winpe-boot.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BCD_SCRIPT%" ^
    -WinPEDir "D:\WinPE" ^
    -SeewoHelperDir "D:\SeewoHelper"

if errorlevel 1 (
    echo.
    echo ERROR: BCD setup failed. Reboot cancelled.
    echo Deep Freeze has been unlocked but WinPE will NOT boot next.
    echo Manually run lock.exe to re-freeze, or reboot now.
    pause
    exit /b 1
)
echo.
echo [3/5] BCD entry created.

:: - Step 4: Reboot -
echo [4/5] All steps complete. Rebooting into WinPE ...
echo.
echo  Sequence after this reboot:
echo    WinPE boots  -^>  injects RunOnce  -^>  reboots into Windows (unfrozen)
echo    Windows starts  -^>  RunOnce triggers post-thaw-update.bat
echo    post-thaw-update.bat: updates Seewo  -^>  re-freezes Deep Freeze  -^>  reboots
echo.
echo  The machine will manage itself from here. No further action needed.
echo.

shutdown /r /t 10 /c "SeewoAutoUpdate: booting into WinPE..."
exit /b 0
