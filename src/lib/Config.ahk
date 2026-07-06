global CFG_FILE := ""

Config_Init(path) {
    global CFG_FILE
    CFG_FILE := path
}

Config_Read(section, key, defaultValue := "") {
    global CFG_FILE
    IniRead, value, %CFG_FILE%, %section%, %key%, %A_Space%
    if (ErrorLevel) {
        return defaultValue
    }
    value := Trim(value)
    if (value = "") {
        return defaultValue
    }
    return value
}

Config_ReadRaw(section, key, defaultValue := "") {
    global CFG_FILE
    IniRead, value, %CFG_FILE%, %section%, %key%, %A_Space%
    if (ErrorLevel) {
        return defaultValue
    }
    return value
}

Config_ReadInt(section, key, defaultValue := 0) {
    value := Config_Read(section, key, defaultValue)
    return value + 0
}

Config_ReadFloat(section, key, defaultValue := 0.0) {
    value := Config_Read(section, key, defaultValue)
    return value + 0.0
}

Config_ReadBool(section, key, defaultValue := true) {
    value := Config_Read(section, key, defaultValue ? "1" : "0")
    StringLower, lowered, value
    if (lowered = "1" or lowered = "true" or lowered = "yes" or lowered = "on") {
        return true
    }
    if (lowered = "0" or lowered = "false" or lowered = "no" or lowered = "off") {
        return false
    }
    return defaultValue
}
