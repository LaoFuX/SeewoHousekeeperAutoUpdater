GetAutomationPassword() {
    pwd := Config_ReadRaw("Freeze", "Password", "")
    if (pwd != "") {
        return pwd
    }

    InputBox, pwd, Password Required, Enter admin password:, HIDE, 420, 140
    if (ErrorLevel) {
        Logger_Fail(2, "Password input was canceled.", false)
    }
    if (pwd = "") {
        Logger_Fail(2, "Password is empty.")
    }
    return pwd
}

SleepCfg(section, key, defaultMs) {
    ms := Config_ReadInt(section, key, defaultMs)
    Sleep, %ms%
}

ClickConfiguredDrive(winSpec, driveLetter) {
    StringUpper, driveLetter, driveLetter
    key := "Disk" . driveLetter . "_X"
    xRatio := Config_ReadFloat("Coords", key, -1)
    yRatio := Config_ReadFloat("Coords", "DiskY", 0.26)
    if (xRatio < 0) {
        Logger_Fail(2, "Unsupported drive in config: " . driveLetter)
    }
    ClickRatio(winSpec, "drive " . driveLetter, xRatio, yRatio)
}

ClickConfiguredDrives(winSpec) {
    drives := Config_Read("Freeze", "Drives", "C")
    Logger_Log("INFO", "Target drives: " . drives)
    Loop, Parse, drives, `,
    {
        drive := Trim(A_LoopField)
        if (drive != "") {
            ClickConfiguredDrive(winSpec, drive)
            SleepCfg("Timing", "MouseDelayMs", 120)
        }
    }
}

OpenFreezePage(winSpec) {
    x := Config_ReadFloat("Coords", "NavFreezeX", 0.50)
    y := Config_ReadFloat("Coords", "NavFreezeY", 0.94)
    count := Config_ReadInt("Timing", "NavClickCount", 3)
    interval := Config_ReadInt("Timing", "NavClickIntervalMs", 600)
    Loop, %count%
    {
        ClickRatio(winSpec, "bottom freeze tab #" . A_Index, x, y)
        Sleep, %interval%
    }
    SleepCfg("Timing", "PageDelayMs", 1200)
}

OpenPasswordDialog(winSpec) {
    x := Config_ReadFloat("Coords", "MainActionX", 0.22)
    y := Config_ReadFloat("Coords", "MainActionY", 0.50)
    ClickRatio(winSpec, "main freeze action", x, y)
    SleepCfg("Timing", "ModalDelayMs", 800)
}

SubmitPassword(winSpec, pwd) {
    x := Config_ReadFloat("Coords", "PasswordTabX", 0.59)
    y := Config_ReadFloat("Coords", "PasswordTabY", 0.34)
    ClickRatio(winSpec, "password tab", x, y)
    SleepCfg("Timing", "MouseDelayMs", 120)

    x := Config_ReadFloat("Coords", "PasswordInputX", 0.50)
    y := Config_ReadFloat("Coords", "PasswordInputY", 0.49)
    Keyboard_KillTouchKeyboardProcesses("before password input")
    ClickRatio(winSpec, "password input", x, y)
    SleepCfg("Keyboard", "AfterPasswordInputClickDelayMs", 500)
    CloseTouchKeyboard("after password input click")
    if (Config_ReadBool("Keyboard", "RefocusPasswordInputAfterKeyboardClose", true)) {
        ClickRatio(winSpec, "password input refocus", x, y)
        SleepCfg("Keyboard", "AfterPasswordInputRefocusDelayMs", 150)
    }
    InputPasswordText(pwd)
    Keyboard_KillTouchKeyboardProcesses("after password input")
    SleepCfg("Keyboard", "AfterPasswordInputDelayMs", 250)
    CloseTouchKeyboard("before password next")

    x := Config_ReadFloat("Coords", "PasswordNextX", 0.50)
    y := Config_ReadFloat("Coords", "PasswordNextY", 0.64)
    ClickRatio(winSpec, "password next", x, y)
    SleepCfg("Timing", "AfterPasswordDelayMs", 1800)
}

ClickFreezeOrUnfreeze(winSpec, action) {
    if (action = "LOCK") {
        label := "freeze button"
        x := Config_ReadFloat("Coords", "FreezeButtonX", 0.40)
        y := Config_ReadFloat("Coords", "FreezeButtonY", 0.75)
    } else {
        label := "unfreeze button"
        x := Config_ReadFloat("Coords", "UnfreezeButtonX", 0.60)
        y := Config_ReadFloat("Coords", "UnfreezeButtonY", 0.75)
    }

    if (Config_ReadBool("Validation", "CheckGreenButton", false)) {
        if (!IsGreenAtRatio(winSpec, x, y)) {
            Logger_Fail(6, label . " does not look enabled. Check selected drives or current freeze state.")
        }
    }

    ClickRatio(winSpec, label, x, y)
    SleepCfg("Timing", "ConfirmDelayMs", 900)
}

ConfirmOperation(winSpec) {
    x := Config_ReadFloat("Coords", "ConfirmOkX", 0.61)
    y := Config_ReadFloat("Coords", "ConfirmOkY", 0.65)
    ClickRatio(winSpec, "confirm ok", x, y)
    SleepCfg("Timing", "RestartDialogDelayMs", 1500)
}

ClickRestartNowIfNeeded(winSpec) {
    if (!Config_ReadBool("Freeze", "AutoRestart", true)) {
        Logger_Log("INFO", "AutoRestart is disabled.")
        return
    }

    x := Config_ReadFloat("Coords", "RestartNowX", 0.61)
    y := Config_ReadFloat("Coords", "RestartNowY", 0.63)
    ClickRatio(winSpec, "restart now", x, y)
}

RunFreezeAutomation(action) {
    Logger_Log("INFO", "Automation action: " . action)
    pwd := GetAutomationPassword()
    Keyboard_PrepareForAutomation()
    winSpec := EnsureSeewoWindow()

    OpenFreezePage(winSpec)
    OpenPasswordDialog(winSpec)
    SubmitPassword(winSpec, pwd)
    ClickConfiguredDrives(winSpec)
    ClickFreezeOrUnfreeze(winSpec, action)
    ConfirmOperation(winSpec)
    Keyboard_RestoreAutomationState("before restart step")
    ClickRestartNowIfNeeded(winSpec)

    Logger_Log("OK", "Automation flow completed.")
    ExitApp, 0
}
