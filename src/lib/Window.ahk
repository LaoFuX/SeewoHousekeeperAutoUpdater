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

    Logger_Log("INFO", "Waiting for window: " . winSpec)
    hwnd := WaitForUsableSeewoWindow(winSpec, waitSeconds)
    activeSpec := "ahk_id " . hwnd

    WinActivate, %activeSpec%
    WinWaitActive, %activeSpec%,, 10
    if (ErrorLevel) {
        Logger_Fail(4, "Target window could not be activated.")
    }

    ValidateWindowSize(activeSpec)
    readyDelay := Config_ReadInt("Timing", "WindowReadyDelayMs", 2500)
    Logger_Log("INFO", "Window ready delay: " . readyDelay . " ms")
    Sleep, %readyDelay%
    return activeSpec
}

StartSeewoLauncher(reason := "") {
    launcher := Config_Read("Freeze", "LauncherPath", "")
    args := Config_ReadRaw("Freeze", "LauncherArgs", "/runmode=launcher")
    if (launcher = "") {
        Logger_Fail(3, "LauncherPath is empty in config.")
    }
    if (!FileExist(launcher)) {
        Logger_Fail(3, "Launcher was not found: " . launcher)
    }

    reasonText := reason = "" ? "" : " reason=" . reason
    Logger_Log("INFO", "Starting launcher:" . reasonText . " path=" . launcher . " args=" . args)
    Run, "%launcher%" %args%,, UseErrorLevel
    if (ErrorLevel) {
        Logger_Fail(3, "Failed to start launcher. ErrorLevel=" . ErrorLevel)
    }
}

WaitForUsableSeewoWindow(winSpec, waitSeconds) {
    minW := Config_ReadInt("Validation", "MinWindowWidth", 500)
    minH := Config_ReadInt("Validation", "MinWindowHeight", 350)
    pollMs := Config_ReadInt("Timing", "WindowPollMs", 500)
    repairDelayMs := Config_ReadInt("Timing", "WindowRepairDelayMs", 1500)
    deadline := A_TickCount + (waitSeconds * 1000)
    launcherStarted := false
    repairTried := false
    lastHwnd := 0
    lastW := 0
    lastH := 0
    logCandidates := true

    Loop
    {
        hwnd := FindBestSeewoWindow(winSpec, x, y, w, h, logCandidates)
        logCandidates := false

        if (hwnd) {
            lastHwnd := hwnd
            lastW := w
            lastH := h

            if (w >= minW and h >= minH) {
                Logger_Log("INFO", "Selected target window hwnd=" . hwnd . " rect x=" . x . " y=" . y . " w=" . w . " h=" . h)
                return hwnd
            }

            Logger_Log("WARN", "Best target window is too small. hwnd=" . hwnd . " x=" . x . " y=" . y . " w=" . w . " h=" . h)

            if (!launcherStarted and Config_ReadBool("Freeze", "LaunchWhenWindowTooSmall", true)) {
                launcherStarted := true
                StartSeewoLauncher("target window too small")
                Sleep, %repairDelayMs%
                logCandidates := true
                continue
            }

            if (!repairTried and Config_ReadBool("Validation", "RepairSmallWindow", true)) {
                repairTried := true
                RepairSmallSeewoWindow(hwnd)
                Sleep, %repairDelayMs%
                logCandidates := true
                continue
            }
        } else if (!launcherStarted) {
            launcherStarted := true
            StartSeewoLauncher("target window not found")
            Sleep, %repairDelayMs%
            logCandidates := true
            continue
        }

        if (A_TickCount >= deadline) {
            break
        }
        Sleep, %pollMs%
    }

    if (lastHwnd) {
        Logger_Fail(4, "Target window is too small after launcher/repair. w=" . lastW . " h=" . lastH)
    }
    Logger_Fail(4, "Target window was not found: " . winSpec)
}

FindBestSeewoWindow(winSpec, ByRef outX, ByRef outY, ByRef outW, ByRef outH, logCandidates := false) {
    outX := 0
    outY := 0
    outW := 0
    outH := 0
    bestHwnd := 0
    bestArea := -1

    WinGet, hwndList, List, %winSpec%
    if (logCandidates) {
        Logger_Log("INFO", "Window candidate count: " . hwndList)
    }

    Loop, %hwndList%
    {
        hwnd := hwndList%A_Index%
        thisSpec := "ahk_id " . hwnd
        WinGetPos, x, y, w, h, %thisSpec%
        WinGet, minMax, MinMax, %thisSpec%
        WinGetTitle, title, %thisSpec%
        area := w * h

        if (logCandidates) {
            Logger_Log("INFO", "Candidate window hwnd=" . hwnd . " minmax=" . minMax . " rect x=" . x . " y=" . y . " w=" . w . " h=" . h . " title=" . title)
        }

        if (w <= 0 or h <= 0) {
            continue
        }

        if (area > bestArea) {
            bestArea := area
            bestHwnd := hwnd
            outX := x
            outY := y
            outW := w
            outH := h
        }
    }

    return bestHwnd
}

RepairSmallSeewoWindow(hwnd) {
    thisSpec := "ahk_id " . hwnd
    minW := Config_ReadInt("Validation", "MinWindowWidth", 500)
    minH := Config_ReadInt("Validation", "MinWindowHeight", 350)
    repairX := Config_ReadInt("Validation", "RepairWindowX", 100)
    repairY := Config_ReadInt("Validation", "RepairWindowY", 60)
    repairW := Config_ReadInt("Validation", "RepairWindowWidth", 984)
    repairH := Config_ReadInt("Validation", "RepairWindowHeight", 683)

    if (repairW < minW) {
        repairW := minW
    }
    if (repairH < minH) {
        repairH := minH
    }
    if (repairW > A_ScreenWidth - 20) {
        repairW := A_ScreenWidth - 20
    }
    if (repairH > A_ScreenHeight - 60) {
        repairH := A_ScreenHeight - 60
    }
    if (repairX < 0 or repairX + repairW > A_ScreenWidth) {
        repairX := 10
    }
    if (repairY < 0 or repairY + repairH > A_ScreenHeight) {
        repairY := 10
    }

    Logger_Log("INFO", "Repairing small target window hwnd=" . hwnd . " to x=" . repairX . " y=" . repairY . " w=" . repairW . " h=" . repairH)
    WinRestore, %thisSpec%
    Sleep, 200
    WinMove, %thisSpec%,, %repairX%, %repairY%, %repairW%, %repairH%
    if (Config_ReadBool("Validation", "MaximizeRepairedWindow", false)) {
        Sleep, 200
        WinMaximize, %thisSpec%
    }
    WinActivate, %thisSpec%
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

TypeText(text) {
    SendInput, ^a
    Sleep, 80
    SendInput, {Text}%text%
    Sleep, 120
}

InputPasswordText(text) {
    method := Config_Read("Keyboard", "PasswordInputMethod", "Text")
    StringLower, method, method
    if (method = "clipboard") {
        PasteText(text)
        Logger_Log("INFO", "Password was entered by clipboard paste. length=" . StrLen(text))
        return
    }

    TypeText(text)
    Logger_Log("INFO", "Password was entered by text input. length=" . StrLen(text))
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
