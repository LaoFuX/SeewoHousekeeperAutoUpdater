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
    Logger_Log("INFO", "Click " . label . " at x=" . x . " y=" . y . " rx=" . xRatio . " ry=" . yRatio)
    MouseMove, %x%, %y%, 0
    Sleep, %mouseDelay%
    Click, %x%, %y%
    Sleep, %mouseDelay%
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
