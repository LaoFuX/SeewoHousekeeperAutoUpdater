@echo off
:: ============================================================
:: Phase 2 - WinPE Auto-Start Script
:: Runs automatically when WinPE boots via startnet.cmd.
::
:: What this script does:
::   1. Initialise WinPE (wpeinit)
::   2. Detect the Windows partition (C:) and the SeewoHelper
::      partition (D:) by scanning for known marker files
::   3. Load the offline SOFTWARE hive from the Windows partition
::   4. Inject a RunOnce entry pointing to phase3.bat on D:\
::   5. Unload the hive
::   6. Delete the temporary WinPE BCD boot entry
::   7. Reboot into Windows (now unfrozen by Phase 1)
:: ============================================================
setlocal EnableExtensions EnableDelayedExpansion

wpeinit

:: - Logging -
:: WinPE X: ramdisk is writable; use it for temporary log only.
set "LOG=X:\seewo_phase2.log"
echo [%DATE% %TIME%] Phase 2 started >> "%LOG%"

:: - Detect drives -
:: Find Windows drive: look for the offline SOFTWARE hive
set "WIN_DRIVE="
for %%D in (C D E F G H I) do (
    if exist "%%D:\Windows\System32\config\SOFTWARE" (
        set "WIN_DRIVE=%%D:"
        echo [%DATE% %TIME%] Windows drive detected: %%D: >> "%LOG%"
        goto :found_win
    )
)
echo [%DATE% %TIME%] ERROR: Could not find Windows partition. >> "%LOG%"
echo ERROR: Cannot find Windows partition (no SOFTWARE hive found).
pause
goto :reboot
:found_win

:: Find SeewoHelper drive: Phase 1 writes a marker file there
set "SEEWO_DRIVE="
for %%D in (C D E F G H I) do (
    if exist "%%D:\SeewoHelper\_seewo_marker.txt" (
        set "SEEWO_DRIVE=%%D:"
        echo [%DATE% %TIME%] SeewoHelper drive detected: %%D: >> "%LOG%"
        goto :found_seewo
    )
)
echo [%DATE% %TIME%] ERROR: Could not find SeewoHelper drive (marker missing). >> "%LOG%"
echo ERROR: Cannot find SeewoHelper drive (_seewo_marker.txt not found).
pause
goto :reboot
:found_seewo

:: - Offline registry edit -
echo [%DATE% %TIME%] Loading offline SOFTWARE hive ... >> "%LOG%"
reg load HKLM\OfflineSW "%WIN_DRIVE%\Windows\System32\config\SOFTWARE"
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] ERROR: reg load failed, code %ERRORLEVEL%. >> "%LOG%"
    echo ERROR: Failed to load offline SOFTWARE hive.
    pause
    goto :cleanup_bcd
)

:: Inject RunOnce entry - cmd /c ensures .bat is executed correctly
set "PHASE3_CMD=cmd /c \"%SEEWO_DRIVE%\SeewoHelper\post-thaw-update.bat\""
reg add "HKLM\OfflineSW\Microsoft\Windows\CurrentVersion\RunOnce" ^
    /v "SeewoAutoUpdate" ^
    /t REG_SZ ^
    /d "%PHASE3_CMD%" ^
    /f
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] ERROR: Failed to write RunOnce key, code %ERRORLEVEL%. >> "%LOG%"
    echo ERROR: Failed to write RunOnce key.
)

:: Unload hive - must be done before reboot
reg unload HKLM\OfflineSW
echo [%DATE% %TIME%] RunOnce injected. Hive unloaded. >> "%LOG%"

:: - Delete temporary WinPE BCD entry -
:cleanup_bcd
set "GUID_FILE=%SEEWO_DRIVE%\SeewoHelper\_winpe_guid.txt"
if exist "%GUID_FILE%" (
    set /p WINPE_GUID=<"%GUID_FILE%"
    echo [%DATE% %TIME%] Deleting WinPE BCD entry: !WINPE_GUID! >> "%LOG%"
    bcdedit /delete !WINPE_GUID! /f >nul 2>&1
    del /f /q "%GUID_FILE%" >nul 2>&1
    echo [%DATE% %TIME%] BCD entry deleted. >> "%LOG%"
) else (
    echo [%DATE% %TIME%] WARNING: WinPE GUID file not found, skipping BCD cleanup. >> "%LOG%"
)

:: - Delete temporary ramdisk options BCD entry -
set "RD_GUID_FILE=%SEEWO_DRIVE%\SeewoHelper\_ramdisk_guid.txt"
if exist "%RD_GUID_FILE%" (
    set /p RAMDISK_GUID=<"%RD_GUID_FILE%"
    echo [%DATE% %TIME%] Deleting ramdisk options BCD entry: !RAMDISK_GUID! >> "%LOG%"
    bcdedit /delete !RAMDISK_GUID! /f >nul 2>&1
    del /f /q "%RD_GUID_FILE%" >nul 2>&1
    echo [%DATE% %TIME%] Ramdisk BCD entry deleted. >> "%LOG%"
)

:: - Reboot into Windows -
:reboot
echo [%DATE% %TIME%] Phase 2 complete. Rebooting ... >> "%LOG%"
echo.
echo Phase 2 complete. Rebooting into Windows ...
timeout /t 3 /nobreak >nul
wpeutil reboot
