@echo off
setlocal
chcp 65001 >nul 2>&1
cd /d "%~dp0.."

set "AHK2EXE="

if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
if exist "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe"
if exist "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"

if "%AHK2EXE%"=="" (
    echo ERROR: Ahk2Exe.exe was not found.
    echo Install AutoHotkey v1.1 on the development computer, then run this script again.
    exit /b 2
)

echo Using compiler:
echo %AHK2EXE%
echo.

if not exist "%CD%\bin" mkdir "%CD%\bin"

"%AHK2EXE%" /in "%CD%\src\unlock.ahk" /out "%CD%\bin\unlock.exe"
if errorlevel 1 exit /b %errorlevel%

"%AHK2EXE%" /in "%CD%\src\lock.ahk" /out "%CD%\bin\lock.exe"
if errorlevel 1 exit /b %errorlevel%

echo.
echo Build complete:
echo   bin\unlock.exe
echo   bin\lock.exe
exit /b 0
