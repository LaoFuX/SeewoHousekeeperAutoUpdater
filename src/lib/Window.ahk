BuildSeewoWinSpec() {
    title := Config_ReadRaw("Freeze", "WindowTitle", "")
    className := Config_Read("Freeze", "WindowClass", "Chrome_WidgetWin_0")
    processName := Config_Read("Freeze", "ProcessName", "SeewoServiceAssistant.exe")

    spec := ""
    if (title != "") {
        spec .= title . " "
    }
    if (className != "") {
        spec .= "ahk_class " . className . " "
    }
    if (processName != "") {
        spec .= "ahk_exe " . processName
    }
    return Trim(spec)
}

EnsureSeewoWindow() {
    winSpec := BuildSeewoWinSpec()
    waitSeconds := Config_ReadInt("Timing", "WindowWaitSeconds", 30)

    if (!WinExist(winSpec)) {
        launcher := Config_Read("Freeze", "LauncherPath", "")
        args := Config_ReadRaw("Freeze", "LauncherArgs", "/runmode=launcher")
        if (launcher = "") {
            Logger_Fail(3, "LauncherPath is empty in config.")
        }
        if (!FileExist(launcher)) {
            Logger_Fail(3, "Launcher was not found: " . launcher)
        }
        Logger_Log("INFO", "Starting launcher: " . launcher . " " . args)
        Run, "%launcher%" %args%,, UseErrorLevel
        if (ErrorLevel) {
            Logger_Fail(3, "Failed to start launcher. ErrorLevel=" . ErrorLevel)
        }
    }

    Logger_Log("INFO", "Waiting for window: " . winSpec)
    WinWait, %winSpec%,, %waitSeconds%
    if (ErrorLevel) {
        Logger_Fail(4, "Target window was not found: " . winSpec)
    }

    WinActivate, %winSpec%
    WinWaitActive, %winSpec%,, 10
    if (ErrorLevel) {
        Logger_Fail(4, "Target window could not be activated.")
    }

    ValidateWindowSize(winSpec)
    readyDelay := Config_ReadInt("Timing", "WindowReadyDelayMs", 2500)
    Logger_Log("INFO", "Window ready delay: " . readyDelay . " ms")
    Sleep, %readyDelay%
    return winSpec
}

ValidateWindowSize(winSpec) {
    WinGetPos, x, y, w, h, %winSpec%
    Logger_Log("INFO", "Window rect x=" . x . " y=" . y . " w=" . w . " h=" . h)
    minW := Config_ReadInt("Validation", "MinWindowWidth", 500)
    minH := Config_ReadInt("Validation", "MinWindowHeight", 350)
    if (w < minW or h < minH) {
        Logger_Fail(4, "Target window is too small. w=" . w . " h=" . h)
    }
}

GetRatioPoint(winSpec, xRatio, yRatio, ByRef outX, ByRef outY) {
    WinGetPos, wx, wy, ww, wh, %winSpec%
    outX := Round(wx + (ww * xRatio))
    outY := Round(wy + (wh * yRatio))
}

ClickRatio(winSpec, label, xRatio, yRatio) {
    mouseDelay := Config_ReadInt("Timing", "MouseDelayMs", 120)
    GetRatioPoint(winSpec, xRatio, yRatio, x, y)
    if (CloseTouchKeyboardIfCoveringPoint(x, y, label)) {
        Sleep, %mouseDelay%
        GetRatioPoint(winSpec, xRatio, yRatio, x, y)
    }
    Logger_Log("INFO", "Click " . label . " at x=" . x . " y=" . y . " rx=" . xRatio . " ry=" . yRatio)
    MouseMove, %x%, %y%, 0
    Sleep, %mouseDelay%
    Click, %x%, %y%
    Sleep, %mouseDelay%
}

GetTouchKeyboardWindowSpecs() {
    specs := Config_ReadRaw("Keyboard", "TouchKeyboardWindowSpecs", "")
    if (specs != "") {
        return specs
    }

    titleSpec := Config_ReadRaw("Keyboard", "TouchKeyboardSpec", "Microsoft Text Input Application ahk_class Windows.UI.Core.CoreWindow")
    exeSpec := Config_ReadRaw("Keyboard", "TouchKeyboardExeSpec", "ahk_exe WindowsInternal.ComposableShell.Experiences.TextInput.InputApp.exe")
    return titleSpec . "|" . exeSpec
}

PointCoveredByWindowSpec(x, y, winSpec) {
    if (winSpec = "") {
        return false
    }

    WinGet, hwndList, List, %winSpec%
    Loop, %hwndList%
    {
        hwnd := hwndList%A_Index%
        thisSpec := "ahk_id " . hwnd
        WinGetPos, wx, wy, ww, wh, %thisSpec%
        if (ww > 0 and wh > 0 and x >= wx and x <= (wx + ww) and y >= wy and y <= (wy + wh)) {
            return true
        }
    }
    return false
}

PointCoveredByWindowSpecList(x, y, specs) {
    Loop, Parse, specs, |
    {
        winSpec := Trim(A_LoopField)
        if (PointCoveredByWindowSpec(x, y, winSpec)) {
            return true
        }
    }
    return false
}

CloseWindowsBySpec(winSpec, reason := "") {
    if (winSpec = "") {
        return 0
    }

    WinGet, hwndList, List, %winSpec%
    closed := 0
    Loop, %hwndList%
    {
        hwnd := hwndList%A_Index%
        thisSpec := "ahk_id " . hwnd
        WinGetTitle, title, %thisSpec%
        Logger_Log("INFO", "Closing touch keyboard hwnd=" . hwnd . " title=" . title . " reason=" . reason)
        WinClose, %thisSpec%
        closed++
    }
    return closed
}

CloseWindowsBySpecList(specs, reason := "") {
    closed := 0
    Loop, Parse, specs, |
    {
        winSpec := Trim(A_LoopField)
        closed += CloseWindowsBySpec(winSpec, reason)
    }
    return closed
}

CloseTouchKeyboard(reason := "") {
    if (!Config_ReadBool("Keyboard", "CloseTouchKeyboard", true)) {
        return false
    }

    waitBeforeClose := Config_ReadInt("Keyboard", "WaitBeforeCloseMs", 200)
    if (waitBeforeClose > 0) {
        Sleep, %waitBeforeClose%
    }

    specs := GetTouchKeyboardWindowSpecs()
    closed := CloseWindowsBySpecList(specs, reason)
    closed += Keyboard_KillTouchKeyboardProcesses(reason)

    if (closed > 0) {
        delay := Config_ReadInt("Keyboard", "AfterCloseDelayMs", 350)
        Sleep, %delay%
        return true
    }
    return false
}

CloseTouchKeyboardIfCoveringPoint(x, y, label := "") {
    if (!Config_ReadBool("Keyboard", "CloseTouchKeyboard", true)) {
        return false
    }

    specs := GetTouchKeyboardWindowSpecs()
    if (PointCoveredByWindowSpecList(x, y, specs)) {
        Logger_Log("INFO", "Touch keyboard covers click target: " . label . " x=" . x . " y=" . y)
        return CloseTouchKeyboard(label)
    }
    return false
}

PasteText(text) {
    saved := ClipboardAll
    Clipboard =
    Clipboard := text
    ClipWait, 2
    if (ErrorLevel) {
        Clipboard := saved
        saved =
        Logger_Fail(5, "Clipboard was not ready for password paste.")
    }
    SendInput, ^a
    Sleep, 80
    SendInput, ^v
    Sleep, 120
    Clipboard := saved
    saved =
}

IsGreenAtRatio(winSpec, xRatio, yRatio) {
    GetRatioPoint(winSpec, xRatio, yRatio, x, y)
    PixelGetColor, color, %x%, %y%, RGB
    hex := SubStr(color, 3)
    r := ("0x" . SubStr(hex, 1, 2)) + 0
    g := ("0x" . SubStr(hex, 3, 2)) + 0
    b := ("0x" . SubStr(hex, 5, 2)) + 0
    minG := Config_ReadInt("Validation", "GreenMin", 120)
    gap := Config_ReadInt("Validation", "GreenGap", 35)
    Logger_Log("INFO", "Pixel check RGB=" . r . "," . g . "," . b . " at x=" . x . " y=" . y)
    return (g >= minG and (g - r) >= gap and (g - b) >= gap)
}
