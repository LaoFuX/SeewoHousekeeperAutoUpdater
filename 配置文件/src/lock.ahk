; AutoHotkey v1 script. Compile this file to lock.exe for deployment.
#NoEnv
#SingleInstance Force
SetBatchLines, -1
SetTitleMatchMode, 2
DetectHiddenWindows, Off
SendMode, Input
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen

#Include %A_ScriptDir%\lib\Config.ahk
#Include %A_ScriptDir%\lib\Logger.ahk
#Include %A_ScriptDir%\lib\Keyboard.ahk
#Include %A_ScriptDir%\lib\Window.ahk
#Include %A_ScriptDir%\lib\FreezeAutomation.ahk

if (A_IsCompiled) {
    if (FileExist(A_ScriptDir . "\..\config\app.ini")) {
        repoRoot := A_ScriptDir . "\.."
    } else {
        repoRoot := A_ScriptDir
    }
} else {
    repoRoot := A_ScriptDir . "\.."
}

Config_Init(repoRoot . "\config\app.ini")
logDir := Config_Read("Log", "FreezeLogDir", "logs\freeze")
if (!RegExMatch(logDir, "i)^[a-z]:\\|^\\\\")) {
    logDir := repoRoot . "\" . logDir
}

Logger_Init(logDir, "lock")
RunFreezeAutomation("LOCK")
