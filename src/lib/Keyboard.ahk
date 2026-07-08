global TK_AUTO_INVOKE_WAS_SAVED := false
global TK_AUTO_INVOKE_EXISTS := false
global TK_AUTO_INVOKE_VALUE := ""
global TK_AUTO_INVOKE_CHANGED := false
global TK_CLEANUP_REGISTERED := false

Keyboard_RegisterCleanup() {
    global TK_CLEANUP_REGISTERED
    if (!TK_CLEANUP_REGISTERED) {
        OnExit("Keyboard_OnExit")
        TK_CLEANUP_REGISTERED := true
    }
}

Keyboard_OnExit(exitReason, exitCode) {
    Keyboard_RestoreAutomationState("script exit: " . exitReason)
}

Keyboard_PrepareForAutomation() {
    if (!Config_ReadBool("Keyboard", "SuppressTouchKeyboard", true)) {
        Logger_Log("INFO", "Touch keyboard suppression is disabled.")
        return
    }

    Keyboard_RegisterCleanup()

    if (Config_ReadBool("Keyboard", "DisableDesktopAutoInvoke", true)) {
        Keyboard_DisableDesktopAutoInvoke()
    }

    Keyboard_KillTouchKeyboardProcesses("automation start")
}

Keyboard_DisableDesktopAutoInvoke() {
    global TK_AUTO_INVOKE_WAS_SAVED, TK_AUTO_INVOKE_EXISTS, TK_AUTO_INVOKE_VALUE, TK_AUTO_INVOKE_CHANGED

    root := Config_Read("Keyboard", "AutoInvokeRoot", "HKEY_CURRENT_USER")
    subKey := Config_ReadRaw("Keyboard", "AutoInvokeSubKey", "Software\Microsoft\TabletTip\1.7")
    valueName := Config_Read("Keyboard", "AutoInvokeValue", "EnableDesktopModeAutoInvoke")

    RegRead, currentValue, %root%, %subKey%, %valueName%
    readFailed := ErrorLevel

    if (!TK_AUTO_INVOKE_WAS_SAVED) {
        TK_AUTO_INVOKE_EXISTS := !readFailed
        if (readFailed) {
            TK_AUTO_INVOKE_VALUE := ""
        } else {
            TK_AUTO_INVOKE_VALUE := currentValue
        }
        TK_AUTO_INVOKE_WAS_SAVED := true
        Logger_Log("INFO", "Saved touch keyboard auto-invoke registry state. exists=" . TK_AUTO_INVOKE_EXISTS . " value=" . TK_AUTO_INVOKE_VALUE)
    }

    if (!readFailed and currentValue = 0) {
        Logger_Log("INFO", "Touch keyboard desktop auto-invoke is already disabled.")
        return true
    }

    RegWrite, REG_DWORD, %root%, %subKey%, %valueName%, 0
    if (ErrorLevel) {
        Logger_Log("WARN", "Failed to disable touch keyboard desktop auto-invoke.")
        return false
    }

    TK_AUTO_INVOKE_CHANGED := true
    Logger_Log("INFO", "Disabled touch keyboard desktop auto-invoke for this automation run.")
    return true
}

Keyboard_RestoreAutomationState(reason := "") {
    global TK_AUTO_INVOKE_WAS_SAVED, TK_AUTO_INVOKE_EXISTS, TK_AUTO_INVOKE_VALUE, TK_AUTO_INVOKE_CHANGED

    if (!TK_AUTO_INVOKE_CHANGED) {
        return true
    }

    if (!Config_ReadBool("Keyboard", "RestoreDesktopAutoInvoke", true)) {
        Logger_Log("INFO", "Keeping touch keyboard desktop auto-invoke disabled. reason=" . reason)
        TK_AUTO_INVOKE_CHANGED := false
        return true
    }

    root := Config_Read("Keyboard", "AutoInvokeRoot", "HKEY_CURRENT_USER")
    subKey := Config_ReadRaw("Keyboard", "AutoInvokeSubKey", "Software\Microsoft\TabletTip\1.7")
    valueName := Config_Read("Keyboard", "AutoInvokeValue", "EnableDesktopModeAutoInvoke")

    if (TK_AUTO_INVOKE_EXISTS) {
        RegWrite, REG_DWORD, %root%, %subKey%, %valueName%, %TK_AUTO_INVOKE_VALUE%
        if (ErrorLevel) {
            Logger_Log("WARN", "Failed to restore touch keyboard desktop auto-invoke. reason=" . reason)
            return false
        }
        Logger_Log("INFO", "Restored touch keyboard desktop auto-invoke to value=" . TK_AUTO_INVOKE_VALUE . ". reason=" . reason)
    } else {
        RegDelete, %root%, %subKey%, %valueName%
        if (ErrorLevel) {
            Logger_Log("WARN", "Failed to delete temporary touch keyboard auto-invoke value. reason=" . reason)
            return false
        }
        Logger_Log("INFO", "Removed temporary touch keyboard auto-invoke value. reason=" . reason)
    }

    TK_AUTO_INVOKE_CHANGED := false
    return true
}

Keyboard_KillTouchKeyboardProcesses(reason := "") {
    if (!Config_ReadBool("Keyboard", "KillTouchKeyboardProcesses", true)) {
        return 0
    }

    processes := Config_ReadRaw("Keyboard", "TouchKeyboardProcesses", "TabTip.exe,TextInputHost.exe,WindowsInternal.ComposableShell.Experiences.TextInput.InputApp.exe")
    attempts := Config_ReadInt("Keyboard", "KillAttempts", 3)
    delay := Config_ReadInt("Keyboard", "KillDelayMs", 250)
    closed := 0

    Loop, Parse, processes, `,
    {
        processName := Trim(A_LoopField)
        if (processName = "") {
            continue
        }

        Loop, %attempts%
        {
            Process, Exist, %processName%
            pid := ErrorLevel
            if (!pid) {
                break
            }

            Logger_Log("INFO", "Stopping touch keyboard process: " . processName . " pid=" . pid . " reason=" . reason)
            Process, Close, %pid%
            Sleep, %delay%

            Process, Exist, %pid%
            if (!ErrorLevel) {
                closed++
            }
        }
    }

    return closed
}
