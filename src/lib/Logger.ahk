global LOG_FILE := ""

Logger_Init(logDir, prefix) {
    global LOG_FILE
    FileCreateDir, %logDir%
    FormatTime, stamp,, yyyyMMdd_HHmmss
    LOG_FILE := logDir . "\" . prefix . "_" . stamp . ".log"
    Logger_Log("INFO", "Log started: " . LOG_FILE)
}

Logger_Log(level, message) {
    global LOG_FILE
    FormatTime, ts,, yyyy-MM-dd HH:mm:ss
    line := "[" . ts . "][" . level . "] " . message
    if (LOG_FILE != "") {
        FileAppend, %line%`r`n, %LOG_FILE%, UTF-8
    }
}

Logger_Fail(exitCode, message, showMessage := true) {
    Logger_Log("ERROR", message)
    if (showMessage) {
        MsgBox, 16, Freeze Automation, %message%`n`nSee logs\freeze for details.
    }
    ExitApp, %exitCode%
}
