#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)
Persistent()

; ============================================================
; StayAwake v8.1 - Startup Fix
; ============================================================
; v8.1 CHANGES:
; - Settings > Startup radio buttons now reflect the *actual* file system state on load, not just the saved INI setting.
;
; v8.0 CHANGES:
; - Added "Power Center" submenu to the tray menu (Force Shutdown, Force Restart, Abort).
; - Power actions use AHK v2 MsgBox for confirmation.
; - Power actions run silently using `Run('cmd.exe /c ...', , "Hide")`.
; - Added toast notification after confirming a shutdown/restart.
; - Reordered Settings buttons to: Save | Cancel | Schedule...
;
; v7.9 CHANGES:
; - Replaced dropdowns with Edit+UpDown controls (spinners)
; - ... (v7.9 changes truncated for brevity)
; ============================================================

; --------------------------
; Globals / configuration
; --------------------------
global timerIntervalMinutes := 5
global isPaused := false
global preventionMethod := "mouse"
global iniFile := A_ScriptDir "\stayawake.ini"
global startEnabled := true
global scheduleMode := "disabled"
global scheduleData := Map()
global startupDefaultActive := true

global g_dueAtTick := 0
global g_watcherPeriodMs := 250
global g_keepAwakeTimerArmed := false

global GUI_MAX_WIDTH      := 460
global INTRO_WIDTH        := 440
global BODY_LINE_WIDTH    := 440
global HINT_LINE_WIDTH    := 440
global INPUT_WIDTH_NARROW := 70
global HEADER_GAP_Y       := 14
global SMALL_GAP_Y        := 6
global CTRL_GAP_X         := 18

LoadSettings()

; ============================================================
; Core: prevent sleep
; ============================================================
KeepAwake() {
    global preventionMethod
    if (preventionMethod = "mouse") {
        MouseMove(1, 0, 1, "R")
        MouseMove(-1, 0, 1, "R")
    } else {
        Send("{F15}")
    }
}

; ============================================================
; Time helpers
; ============================================================
FormatTime2Digits(num) {
    return Format("{:02}", num)
}

; Format Edit field whenever UpDown value changes
FormatEditField(editCtrl, upDownCtrl, *) {
    editCtrl.Value := FormatTime2Digits(upDownCtrl.Value)
}

IsTimeInRange(current, start, end) {
    currentNum := Integer(StrReplace(current, ":"))
    startNum   := Integer(StrReplace(start,   ":"))
    endNum     := Integer(StrReplace(end,     ":"))
    if (startNum = endNum)
        return false
    if (startNum < endNum)
        return (currentNum >= startNum && currentNum < endNum)
    else
        return (currentNum >= startNum || currentNum < endNum)
}

GetScheduleTooltip() {
    global scheduleMode, scheduleData, isPaused
    if (scheduleMode = "disabled")
        return ""
    currentDay := FormatTime(, "dddd")
    if (scheduleMode = "simple") {
        return isPaused
            ? " (Schedule: On at " scheduleData["SimpleOnTime"] ")"
            : " (Schedule: Off at " scheduleData["SimpleOffTime"] ")"
    }
    if (scheduleMode = "advanced" && scheduleData[currentDay "Enabled"]) {
        return isPaused
            ? " (Schedule: On at " scheduleData[currentDay "On"] ")"
            : " (Schedule: Off at " scheduleData[currentDay "Off"] ")"
    }
    return ""
}

; ============================================================
; Intelligent Mode
; ============================================================
ArmIntelligentTimer() {
    global timerIntervalMinutes, g_dueAtTick, g_keepAwakeTimerArmed, isPaused
    if (isPaused)
        return
    local intervalMs := timerIntervalMinutes * 60000
    local sinceLastInput := A_TimeIdle
    if (sinceLastInput < 0)
        sinceLastInput := 0
    local delay := intervalMs - sinceLastInput
    if (delay < 0)
        delay := 0
    g_dueAtTick := A_TickCount + delay
    g_keepAwakeTimerArmed := true
    SetTimer(DoKeepAwake, -delay)
}

DoKeepAwake() {
    global g_keepAwakeTimerArmed, isPaused
    g_keepAwakeTimerArmed := false
    if (isPaused)
        return
    KeepAwake()
    ArmIntelligentTimer()
}

WatchUserActivity() {
    global g_dueAtTick, g_watcherPeriodMs, isPaused, g_keepAwakeTimerArmed, timerIntervalMinutes
    if (isPaused)
        return
    local intervalMs := timerIntervalMinutes * 60000
    local sinceLastInput := A_TimeIdle
    if (sinceLastInput < 0)
        sinceLastInput := 0
    local newDelay := intervalMs - sinceLastInput
    if (newDelay < 0)
        newDelay := 0
    local newDue := A_TickCount + newDelay
    local threshold := 150
    if (!g_keepAwakeTimerArmed) {
        ArmIntelligentTimer()
        return
    }
    if (Abs(newDue - g_dueAtTick) > threshold) {
        SetTimer(DoKeepAwake, 0)
        ArmIntelligentTimer()
    }
}

StartIntelligentTimers() {
    global g_watcherPeriodMs
    SetTimer(WatchUserActivity, g_watcherPeriodMs)
    ArmIntelligentTimer()
}

StopIntelligentTimers() {
    SetTimer(WatchUserActivity, 0)
    SetTimer(DoKeepAwake, 0)
}

; ============================================================
; Schedule Settings GUI - OPTIMIZED WITH EDIT+UPDOWN
; ============================================================
OpenScheduleSettings(*) {
    global scheduleMode, scheduleData
    static guiSchedule := ""

    try if (IsObject(guiSchedule))
        guiSchedule.Destroy()

    guiSchedule := Gui("+AlwaysOnTop -Resize", "Schedule Settings")
    guiSchedule.MarginX := 16
    guiSchedule.MarginY := 16
    guiSchedule.SetFont("s10 c000000")

    guiSchedule.AddText("w" GUI_MAX_WIDTH, "Configure when StayAwake should automatically turn on and off.")
    guiSchedule.AddText("w" GUI_MAX_WIDTH " y+16", "Schedule Mode:")

    radioDisabled := guiSchedule.AddRadio("vScheduleDisabled y+6 w250 Checked" (scheduleMode = "disabled" ? "1" : "0"), "Disabled (no schedule)")
    radioSimple   := guiSchedule.AddRadio("vScheduleSimple   y+6 w250 Checked" (scheduleMode = "simple"   ? "1" : "0"), "Simple (same time every day)")
    radioAdvanced := guiSchedule.AddRadio("vScheduleAdvanced y+6 w280 Checked" (scheduleMode = "advanced" ? "1" : "0"), "Advanced (custom times per day)")

    ; Parse simple times
    simpleParts := StrSplit(scheduleData["SimpleOnTime"], ":")
    simpleOnH := Integer(simpleParts[1])
    simpleOnM := Integer(simpleParts[2])
    simpleParts := StrSplit(scheduleData["SimpleOffTime"], ":")
    simpleOffH := Integer(simpleParts[1])
    simpleOffM := Integer(simpleParts[2])

    ; Simple time row - ReadOnly fields with white background, users can only use arrows
    simpleOnLabel := guiSchedule.AddText("xm y+20 w80", "Turn on at:")
    simpleOnHourEdit := guiSchedule.AddEdit("x+8 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(simpleOnH))
    simpleOnHourUpDown := guiSchedule.AddUpDown("Range0-23", simpleOnH)
    simpleOnHourEdit.Value := FormatTime2Digits(simpleOnH)  ; Force format after UpDown creation
    simpleOnHourUpDown.OnEvent("Change", (*) => FormatEditField(simpleOnHourEdit, simpleOnHourUpDown))
    simpleOnColon := guiSchedule.AddText("x+4 yp+2 w10", ":")
    simpleOnMinEdit := guiSchedule.AddEdit("x+4 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(simpleOnM))
    simpleOnMinUpDown := guiSchedule.AddUpDown("Range0-59", simpleOnM)
    simpleOnMinEdit.Value := FormatTime2Digits(simpleOnM)  ; Force format after UpDown creation
    simpleOnMinUpDown.OnEvent("Change", (*) => FormatEditField(simpleOnMinEdit, simpleOnMinUpDown))
    
    simpleOffLabel := guiSchedule.AddText("x+20 yp+2 w80", "Turn off at:")
    simpleOffHourEdit := guiSchedule.AddEdit("x+8 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(simpleOffH))
    simpleOffHourUpDown := guiSchedule.AddUpDown("Range0-23", simpleOffH)
    simpleOffHourEdit.Value := FormatTime2Digits(simpleOffH)  ; Force format after UpDown creation
    simpleOffHourUpDown.OnEvent("Change", (*) => FormatEditField(simpleOffHourEdit, simpleOffHourUpDown))
    simpleOffColon := guiSchedule.AddText("x+4 yp+2 w10", ":")
    simpleOffMinEdit := guiSchedule.AddEdit("x+4 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(simpleOffM))
    simpleOffMinUpDown := guiSchedule.AddUpDown("Range0-59", simpleOffM)
    simpleOffMinEdit.Value := FormatTime2Digits(simpleOffM)  ; Force format after UpDown creation
    simpleOffMinUpDown.OnEvent("Change", (*) => FormatEditField(simpleOffMinEdit, simpleOffMinUpDown))

    ; Get the Y position of Simple controls to reuse for Advanced (eliminates gap)
    simpleOnLabel.GetPos(&simpleX, &simpleY, &simpleW, &simpleH)

    ; Advanced table headers - Use same Y position as Simple to eliminate gap
    advHeader1 := guiSchedule.AddText("xm y" simpleY " w100", "Day")
    advHeader2 := guiSchedule.AddText("x+8 yp w60 Center", "Enabled")
    advHeader3 := guiSchedule.AddText("x+50 yp w100 Center", "Turn On")
    advHeader4 := guiSchedule.AddText("x+40 yp w100 Center", "Turn Off")
    
    ; Divider line under headers for visual separation
    advDivider := guiSchedule.AddText("xm y+4 w480 h2 0x10")

    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    dayControls := Map()
    advancedColons := []

    for day in days {
        onParts := StrSplit(scheduleData[day "On"], ":")
        onH := Integer(onParts[1])
        onM := Integer(onParts[2])
        offParts := StrSplit(scheduleData[day "Off"], ":")
        offH := Integer(offParts[1])
        offM := Integer(offParts[2])
        
        dayText  := guiSchedule.AddText("xm y+6 w100", day)
        dayCheck := guiSchedule.AddCheckbox("x+33 yp h20 Checked" (scheduleData[day "Enabled"] ? "1" : "0"))
        
        onHourEdit := guiSchedule.AddEdit("x+25 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(onH))
        onHourUpDown := guiSchedule.AddUpDown("Range0-23", onH)
        onHourEdit.Value := FormatTime2Digits(onH)  ; Force format after UpDown creation
        onHourUpDown.OnEvent("Change", (*) => FormatEditField(onHourEdit, onHourUpDown))
        onColon := guiSchedule.AddText("x+4 yp+2 w10", ":")
        onMinEdit := guiSchedule.AddEdit("x+4 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(onM))
        onMinUpDown := guiSchedule.AddUpDown("Range0-59", onM)
        onMinEdit.Value := FormatTime2Digits(onM)  ; Force format after UpDown creation
        onMinUpDown.OnEvent("Change", (*) => FormatEditField(onMinEdit, onMinUpDown))
        
        offHourEdit := guiSchedule.AddEdit("x+10 yp w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(offH))
        offHourUpDown := guiSchedule.AddUpDown("Range0-23", offH)
        offHourEdit.Value := FormatTime2Digits(offH)  ; Force format after UpDown creation
        offHourUpDown.OnEvent("Change", (*) => FormatEditField(offHourEdit, offHourUpDown))
        offColon := guiSchedule.AddText("x+4 yp+2 w10", ":")
        offMinEdit := guiSchedule.AddEdit("x+4 yp-2 w55 Center ReadOnly BackgroundWhite", FormatTime2Digits(offM))
        offMinUpDown := guiSchedule.AddUpDown("Range0-59", offM)
        offMinEdit.Value := FormatTime2Digits(offM)  ; Force format after UpDown creation
        offMinUpDown.OnEvent("Change", (*) => FormatEditField(offMinEdit, offMinUpDown))

        dayControls[day] := Map(
            "text", dayText,
            "check", dayCheck,
            "onHourEdit", onHourEdit,
            "onMinEdit", onMinEdit,
            "offHourEdit", offHourEdit,
            "offMinEdit", offMinEdit,
            "onHourUpDown", onHourUpDown,
            "onMinUpDown", onMinUpDown,
            "offHourUpDown", offHourUpDown,
            "offMinUpDown", offMinUpDown,
            "onColon", onColon,
            "offColon", offColon
        )
        advancedColons.Push(onColon)
        advancedColons.Push(offColon)
    }

    ; Store all simple controls including UpDowns
    simpleControls := [
        simpleOnLabel, simpleOnHourEdit, simpleOnHourUpDown, simpleOnColon, simpleOnMinEdit, simpleOnMinUpDown,
        simpleOffLabel, simpleOffHourEdit, simpleOffHourUpDown, simpleOffColon, simpleOffMinEdit, simpleOffMinUpDown
    ]
    
    ; Store all advanced controls including UpDowns and colons
    advancedControls := [advHeader1, advHeader2, advHeader3, advHeader4, advDivider]
    for day in days {
        advancedControls.Push(dayControls[day]["text"])
        advancedControls.Push(dayControls[day]["check"])
        advancedControls.Push(dayControls[day]["onHourEdit"])
        advancedControls.Push(dayControls[day]["onHourUpDown"])
        advancedControls.Push(dayControls[day]["onColon"])
        advancedControls.Push(dayControls[day]["onMinEdit"])
        advancedControls.Push(dayControls[day]["onMinUpDown"])
        advancedControls.Push(dayControls[day]["offHourEdit"])
        advancedControls.Push(dayControls[day]["offHourUpDown"])
        advancedControls.Push(dayControls[day]["offColon"])
        advancedControls.Push(dayControls[day]["offMinEdit"])
        advancedControls.Push(dayControls[day]["offMinUpDown"])
    }

    UpdateScheduleVisibility(mode) {
        for ctrl in simpleControls
            ctrl.Visible := (mode = "simple")
        for ctrl in advancedControls
            ctrl.Visible := (mode = "advanced")
    }
    
    ; Function to reset all times to defaults
    ResetToDefaults() {
        ; Set Simple times to defaults
        simpleOnHourUpDown.Value := 7
        simpleOnHourEdit.Value := "07"
        simpleOnMinUpDown.Value := 0
        simpleOnMinEdit.Value := "00"
        simpleOffHourUpDown.Value := 18
        simpleOffHourEdit.Value := "18"
        simpleOffMinUpDown.Value := 0
        simpleOffMinEdit.Value := "00"
        
        ; Set Advanced times to defaults and enable all days
        for day in days {
            dayControls[day]["check"].Value := 1
            dayControls[day]["onHourUpDown"].Value := 7
            dayControls[day]["onHourEdit"].Value := "07"
            dayControls[day]["onMinUpDown"].Value := 0
            dayControls[day]["onMinEdit"].Value := "00"
            dayControls[day]["offHourUpDown"].Value := 18
            dayControls[day]["offHourEdit"].Value := "18"
            dayControls[day]["offMinUpDown"].Value := 0
            dayControls[day]["offMinEdit"].Value := "00"
        }
        
        ; Switch to Disabled mode
        radioDisabled.Value := 1
        UpdateScheduleVisibility("disabled")
    }
    
    UpdateScheduleVisibility(scheduleMode)
    radioDisabled.OnEvent("Click", (*) => UpdateScheduleVisibility("disabled"))
    radioSimple  .OnEvent("Click", (*) => UpdateScheduleVisibility("simple"))
    radioAdvanced.OnEvent("Click", (*) => UpdateScheduleVisibility("advanced"))

    btnSave    := guiSchedule.AddButton("xm y+20 w90 Default", "Save")
    btnCancel  := guiSchedule.AddButton("x+12 w90", "Cancel")
    btnDefault := guiSchedule.AddButton("x+12 w90", "Default")

    btnSave.OnEvent("Click", (*) => SaveScheduleHandler(
        guiSchedule, radioDisabled, radioSimple, simpleOnHourUpDown, simpleOnMinUpDown, simpleOffHourUpDown, simpleOffMinUpDown, dayControls, days
    ))
    btnCancel.OnEvent("Click", (*) => guiSchedule.Destroy())
    btnDefault.OnEvent("Click", (*) => ResetToDefaults())

    guiSchedule.Show("AutoSize Center")
}

SaveScheduleHandler(guiObj, radioDisabled, radioSimple, simpleOnHourUD, simpleOnMinUD, simpleOffHourUD, simpleOffMinUD, dayControls, days) {
    global scheduleMode, scheduleData, isPaused

    if (radioDisabled.Value = 1)
        scheduleMode := "disabled"
    else if (radioSimple.Value = 1)
        scheduleMode := "simple"
    else
        scheduleMode := "advanced"

    scheduleData["SimpleOnTime"]  := FormatTime2Digits(simpleOnHourUD.Value) ":" FormatTime2Digits(simpleOnMinUD.Value)
    scheduleData["SimpleOffTime"] := FormatTime2Digits(simpleOffHourUD.Value) ":" FormatTime2Digits(simpleOffMinUD.Value)

    for day in days {
        scheduleData[day "Enabled"] := dayControls[day]["check"].Value
        scheduleData[day "On"]  := FormatTime2Digits(dayControls[day]["onHourUpDown"].Value) ":" FormatTime2Digits(dayControls[day]["onMinUpDown"].Value)
        scheduleData[day "Off"] := FormatTime2Digits(dayControls[day]["offHourUpDown"].Value) ":" FormatTime2Digits(dayControls[day]["offMinUpDown"].Value)
    }

    SaveScheduleSettings()
    ShowCustomTooltip("Schedule settings saved!", isPaused ? "paused" : "active")
    UpdateTray(isPaused ? "paused" : "active")
    guiObj.Destroy()
}

; ============================================================
; Settings GUI (narrower, explicit fonts, inline radios, hints below headers)
; ============================================================
OpenSettings(*) {
    global timerIntervalMinutes, preventionMethod, startEnabled, iniFile, startupDefaultActive
    global GUI_MAX_WIDTH, INTRO_WIDTH, BODY_LINE_WIDTH, HINT_LINE_WIDTH
    global HEADER_GAP_Y, SMALL_GAP_Y, INPUT_WIDTH_NARROW, CTRL_GAP_X
    static guiSettings := ""

    try if (IsObject(guiSettings))
        guiSettings.Destroy()

    guiSettings := Gui("+AlwaysOnTop -Resize", "StayAwake Settings")
    guiSettings.MarginX := 16
    guiSettings.MarginY := 16

    ; Intro (s10 regular). Width kept narrow so it wraps after "one pixel".
    guiSettings.SetFont("s10 c000000")
    introText := guiSettings.AddText("xm w" INTRO_WIDTH, GetIntroText(preventionMethod, timerIntervalMinutes))

    ; ===== Activity =====
    guiSettings.SetFont("s11 c000000")
    headerActivity := guiSettings.AddText("xm y+" HEADER_GAP_Y " w" BODY_LINE_WIDTH, "⏱ Activity")

    guiSettings.SetFont("s9 c000000")
    activityHint := guiSettings.AddText("xm y+2 w" HINT_LINE_WIDTH, "Recommended: 5–10 minutes.")

    guiSettings.SetFont("s10 c000000")
    lblInterval := guiSettings.AddText("xm y+" SMALL_GAP_Y " w260", "Activity Interval (Minutes):")
    inputInterval := guiSettings.AddEdit("x+6 yp-2 w100 Number", timerIntervalMinutes)
    inputInterval.Name := "IntervalMinutes"
    inputInterval.OnEvent("Change", (*) => OnIntervalChange(inputInterval))

    ; ===== Prevention Method =====
    guiSettings.SetFont("s11 c000000")
    headerMethod := guiSettings.AddText("xm y+" HEADER_GAP_Y " w" BODY_LINE_WIDTH, "🛡 Prevention Method")

    guiSettings.SetFont("s9 c000000")
    methodHint := guiSettings.AddText("xm y+2 w" HINT_LINE_WIDTH, "Pick how the app keeps your session awake.")

    guiSettings.SetFont("s10 c000000")
    ; Side-by-side radios (same group).
    radioMouse     := guiSettings.AddRadio("xm y+" SMALL_GAP_Y " w200 Checked" (preventionMethod = "mouse" ? "1" : "0"), "Move Mouse Slightly")
    radioKeystroke := guiSettings.AddRadio("x+" CTRL_GAP_X " yp w220 Checked" (preventionMethod = "keystroke" ? "1" : "0"), "Press Harmless Key (F15)")

    ; --- Align Activity Interval field to the same left edge as the Keystroke radio & reduce width ---
    inputInterval.GetPos(&iiX, &iiY, &iiW, &iiH)
    radioKeystroke.GetPos(&rkX, &rkY, &rkW, &rkH)
    inputInterval.Move(rkX, iiY, INPUT_WIDTH_NARROW, iiH)

    ; Keep intro synchronized with radio/interval
    radioMouse    .OnEvent("Click", (*) => (preventionMethod := "mouse",     UpdateIntroMouse(introText, inputInterval.Value)))
    radioKeystroke.OnEvent("Click", (*) => (preventionMethod := "keystroke", UpdateIntroKeystroke(introText, inputInterval.Value)))
    inputInterval .OnEvent("Change", (*) => (
        radioMouse.Value = 1
            ? UpdateIntroMouse(introText, inputInterval.Value)
            : UpdateIntroKeystroke(introText, inputInterval.Value)
    ))

    ; ===== Startup =====
    guiSettings.SetFont("s11 c000000")
    headerStartup := guiSettings.AddText("xm y+" HEADER_GAP_Y " w" BODY_LINE_WIDTH, "🚀 Startup")

    guiSettings.SetFont("s9 c000000")
    startupHint := guiSettings.AddText("xm y+2 w" HINT_LINE_WIDTH, "Manage whether the app launches automatically at Windows startup.")

    guiSettings.SetFont("s10 c000000")
    guiSettings.AddText("xm y+" SMALL_GAP_Y " w" BODY_LINE_WIDTH, "Launch at Windows startup:")

    startupFolder := A_Startup "\"
    shortcutName  := "StayAwake.lnk"
    shortcutPath  := startupFolder . shortcutName
    alreadyExists := FileExist(shortcutPath) ? true : false

    ; v8.1: Sync the 'startEnabled' var with the *actual* file state *before* creating controls.
    startEnabled := alreadyExists

    radioStartupYes := guiSettings.AddRadio("xm y+3 w160 Checked" (startEnabled ? "1" : "0"), "Yes")
    radioStartupNo  := guiSettings.AddRadio("x+" CTRL_GAP_X " yp w160 Checked" (!startEnabled ? "1" : "0"), "No")

    guiSettings.SetFont("s9 c666666")
    statusText := guiSettings.AddText("xm y+6 w" BODY_LINE_WIDTH, "")
    if (startEnabled)
        UpdateStatusYes(statusText, alreadyExists)
    else
        UpdateStatusNo(statusText)

    radioStartupYes.OnEvent("Click", (*) => (startEnabled := true, UpdateStatusYes(statusText, alreadyExists)))
    radioStartupNo .OnEvent("Click", (*) => (startEnabled := false, UpdateStatusNo(statusText)))

    ; ===== Auto-Start Behavior =====
    guiSettings.SetFont("s11 c000000")
    headerBehavior := guiSettings.AddText("xm y+" HEADER_GAP_Y " w" BODY_LINE_WIDTH, "▶ Auto-Start Behavior")

    guiSettings.SetFont("s9 c000000")
    behaviorHint := guiSettings.AddText("xm y+2 w" HINT_LINE_WIDTH, "Decide if StayAwake runs actively or paused at launch (when no schedule is active).")

    guiSettings.SetFont("s10 c000000")
    radioActive := guiSettings.AddRadio("xm y+" SMALL_GAP_Y " w160 Checked" (startupDefaultActive ? "1" : "0"), "Start Active")
    radioPaused := guiSettings.AddRadio("x+" CTRL_GAP_X " yp w160 Checked" (!startupDefaultActive ? "1" : "0"), "Start Paused")

    radioActive.OnEvent("Click", (*) => (startupDefaultActive := true))
    radioPaused.OnEvent("Click", (*) => (startupDefaultActive := false))

    ; ===== Action buttons - v8.0 Button Reorder =====
    guiSettings.SetFont("s10 c000000")
    btnSave     := guiSettings.AddButton("xm y+" HEADER_GAP_Y " w90 Default", "Save")
    btnCancel   := guiSettings.AddButton("x+12 w90", "Cancel")
    btnSchedule := guiSettings.AddButton("x+12 w100", "Schedule...")

    btnSchedule.OnEvent("Click", OpenScheduleSettings)
    btnSave.OnEvent("Click", (*) => SaveSettingsHandler(
        inputInterval, radioMouse, radioKeystroke, radioStartupYes, shortcutPath, radioActive, radioPaused, guiSettings
    ))
    btnCancel.OnEvent("Click", (*) => guiSettings.Destroy())

    guiSettings.Show("AutoSize Center")
}

; --------------- Helper functions for Settings GUI ---------------

GetIntroText(method, intervalMin) {
    return (method = "mouse")
        ? "StayAwake will move your mouse by one pixel every " intervalMin " minute(s) to keep your session active."
        : "StayAwake will send a harmless key press (F15) every " intervalMin " minute(s) to keep your session active."
}

UpdateIntroMouse(textCtrl, intervalMin) {
    textCtrl.Value := "StayAwake will move your mouse by one pixel every " intervalMin " minute(s) to keep your session active."
}

UpdateIntroKeystroke(textCtrl, intervalMin) {
    textCtrl.Value := "StayAwake will send a harmless key press (F15) every " intervalMin " minute(s) to keep your session active."
}

OnIntervalChange(inputCtrl) {
    val := inputCtrl.Value
    if (val < 1 || val > 600)
        return
}

SaveSettingsHandler(intervalCtrl, radioMouse, radioKeystroke, radioStartupYes, shortcutPath, radioActive, radioPaused, guiSettings) {
    global timerIntervalMinutes, preventionMethod, startEnabled, isPaused, iniFile, startupDefaultActive

    ; Update interval
    newInterval := intervalCtrl.Value
    if (newInterval < 1)
        newInterval := 1
    if (newInterval > 600)
        newInterval := 600
    timerIntervalMinutes := newInterval

    ; Update prevention method
    preventionMethod := (radioMouse.Value = 1) ? "mouse" : "keystroke"

    ; Save interval and method
    SaveSettingsToFile(timerIntervalMinutes, preventionMethod)

    ; Startup shortcut management
    startEnabled := (radioStartupYes.Value = 1)
    if (startEnabled) {
        if (!FileExist(shortcutPath))
            FileCreateShortcut(A_ScriptFullPath, shortcutPath, A_ScriptDir)
    } else {
        if (FileExist(shortcutPath))
            try FileDelete(shortcutPath)
    }

    ; Auto-start behavior
    newStartupDefaultActive := (radioActive.Value = 1)
    SaveStartupSettings(startEnabled, newStartupDefaultActive ? "active" : "paused")
    startupDefaultActive := newStartupDefaultActive

    ; Re-arm timers
    if (!isPaused) {
        StopIntelligentTimers()
        StartIntelligentTimers()
    }

    ShowCustomTooltip("Settings saved!", isPaused ? "paused" : "active")
    guiSettings.Destroy()
}

UpdateStatusYes(statusTextCtrl, alreadyExists, *) {
    if (alreadyExists) {
        statusTextCtrl.SetFont("s9 cGreen"), statusTextCtrl.Value := "✓ It is already in the startup folder."
    } else {
        statusTextCtrl.SetFont("s9 cGreen"), statusTextCtrl.Value := "Will launch automatically at startup when saved."
    }
}

UpdateStatusNo(statusTextCtrl, *) {
    statusTextCtrl.SetFont("s9 cRed"), statusTextCtrl.Value := "Will not launch at startup when saved."
}

; ============================================================
; Settings persistence (INI)
; ============================================================
LoadSettings() {
    global timerIntervalMinutes, preventionMethod, iniFile, startEnabled, scheduleMode, scheduleData, isPaused, startupDefaultActive

    ; Always initialize scheduleData with defaults first
    InitializeScheduleDataDefaults()

    if (FileExist(iniFile)) {
        timerIntervalMinutes := IniRead(iniFile, "Settings", "IntervalMinutes", 5)
        preventionMethod     := IniRead(iniFile, "Settings", "PreventionMethod", "mouse")
        startEnabled         := (IniRead(iniFile, "Startup",  "StartEnabled", "true") = "true")
        startupState         := IniRead(iniFile, "Startup",  "StartupState", "active")
        scheduleMode         := IniRead(iniFile, "Schedule", "Mode", "disabled")

        ; clamp interval
        if (timerIntervalMinutes < 1)
            timerIntervalMinutes := 1
        if (timerIntervalMinutes > 600)
            timerIntervalMinutes := 600

        ; sanitize method
        if (preventionMethod != "mouse" && preventionMethod != "keystroke")
            preventionMethod := "mouse"

        startupDefaultActive := (startupState = "active")
        if (!startupDefaultActive)
            isPaused := true

        LoadScheduleData()
    } else {
        ; First run - no INI file exists
        SaveSettingsToFile(timerIntervalMinutes, preventionMethod)
        SaveStartupSettings(startEnabled, "active")
        startupDefaultActive := true
        SaveScheduleSettings()
    }

    if (!startEnabled)
        isPaused := true
}

InitializeScheduleDataDefaults() {
    global scheduleData
    
    ; Initialize Simple schedule defaults
    scheduleData["SimpleOnTime"]  := "07:00"
    scheduleData["SimpleOffTime"] := "18:00"
    
    ; Initialize Advanced schedule defaults for all days
    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for day in days {
        scheduleData[day "Enabled"] := true
        scheduleData[day "On"]  := "07:00"
        scheduleData[day "Off"] := "18:00"
    }
}

LoadScheduleData() {
    global scheduleData, iniFile
    ; DEFAULT VALUES: 07:00 for Turn On, 18:00 for Turn Off
    scheduleData["SimpleOnTime"]  := IniRead(iniFile, "Schedule", "SimpleOnTime", "07:00")
    scheduleData["SimpleOffTime"] := IniRead(iniFile, "Schedule", "SimpleOffTime", "18:00")

    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for day in days {
        scheduleData[day "Enabled"] := (IniRead(iniFile, "Schedule", day "Enabled", "true") = "true")
        scheduleData[day "On"]  := IniRead(iniFile, "Schedule", day "On", "07:00")
        scheduleData[day "Off"] := IniRead(iniFile, "Schedule", day "Off", "18:00")
    }
}

SaveSettingsToFile(minutes, method) {
    global iniFile
    IniWrite(minutes, iniFile, "Settings", "IntervalMinutes")
    IniWrite(method,  iniFile, "Settings", "PreventionMethod")
}

SaveStartupSettings(enabled, state) {
    global iniFile, startupDefaultActive
    IniWrite(enabled ? "true" : "false", iniFile, "Startup", "StartEnabled")
    IniWrite(state,                        iniFile, "Startup", "StartupState")
    startupDefaultActive := (state = "active")
}

SaveScheduleSettings() {
    global iniFile, scheduleMode, scheduleData
    IniWrite(scheduleMode,                  iniFile, "Schedule", "Mode")
    IniWrite(scheduleData["SimpleOnTime"],  iniFile, "Schedule", "SimpleOnTime")
    IniWrite(scheduleData["SimpleOffTime"], iniFile, "Schedule", "SimpleOffTime")

    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for day in days {
        IniWrite(scheduleData[day "Enabled"] ? "true" : "false", iniFile, "Schedule", day "Enabled")
        IniWrite(scheduleData[day "On"],  iniFile, "Schedule", day "On")
        IniWrite(scheduleData[day "Off"], iniFile, "Schedule", day "Off")
    }
}

; ============================================================
; Tray actions / icon tip
; ============================================================
PauseActivity(*) {
    global isPaused
    if (isPaused)
        return
    isPaused := true
    StopIntelligentTimers()
    try ShowCustomTooltip("StayAwake Prevention Paused.", "paused")
    UpdateTray("paused")
}

ResumeActivity(*) {
    global isPaused
    if (!isPaused)
        return
    isPaused := false
    StartIntelligentTimers()
    try ShowCustomTooltip("StayAwake Prevention Active. Your computer won't go to sleep.", "active")
    UpdateTray("active")
}

UpdateTray(state) {
    scheduleInfo := GetScheduleTooltip()
    try {
        if (state = "paused") {
            TraySetIcon("imageres.dll", 101)
            A_IconTip := "StayAwake Prevention Paused" scheduleInfo
            A_TrayMenu.Disable("Pause Prevention")
            A_TrayMenu.Enable("Resume Prevention")
        } else {
            TraySetIcon("imageres.dll", 100)
            A_IconTip := "StayAwake Prevention Active" scheduleInfo
            A_TrayMenu.Enable("Pause Prevention")
            A_TrayMenu.Disable("Resume Prevention")
        }
    }
}

; ============================================================
; v8.0: Power Center Functions
; ============================================================
HandleForceShutdown(*) {
    result := MsgBox("ARE YOU SURE YOU WANT TO INITIATE A 30 SECOND SHUTDOWN?", "SHUTDOWN?!", "YesNo Icon!")
    if (result = "Yes") {
        Run('cmd.exe /c shutdown /s /f /t 30', , "Hide")
        ShowCustomTooltip("Shutdown in 30s. Use Power Center > Abort! to cancel.", "active", 3000)
    }
}

HandleForceRestart(*) {
    result := MsgBox("ARE YOU SURE YOU WANT TO INITIATE A 30 SECOND RESTART?", "RESTART?!", "YesNo Icon!")
    if (result = "Yes") {
        Run('cmd.exe /c shutdown /r /f /t 30', , "Hide")
        ShowCustomTooltip("Restart in 30s. Use Power Center > Abort! to cancel.", "active", 3000)
    }
}

HandleAbortShutdown(*) {
    Run('cmd.exe /c shutdown /a', , "Hide")
    ShowCustomTooltip("Shutdown/Restart aborted!", "active")
}

; ============================================================
; Toast-style tooltip (toasts)
; ============================================================
ShowCustomTooltip(msg, state := "active", duration := 2000) {
    static tooltipGui := ""
    if (IsObject(tooltipGui)) {
        try tooltipGui.Destroy()
    }
    tooltipGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notification")
    tooltipGui.BackColor := "0x2D2D30"
    tooltipGui.SetFont("s11 cWhite", "Segoe UI")
    tooltipGui.MarginX := 20
    tooltipGui.MarginY := 16
    iconNum := (state = "paused") ? 101 : 100
    tooltipGui.AddPicture("w32 h32 Icon" iconNum, "imageres.dll")
    tooltipGui.AddText("x+12 yp+6 w360", msg)
    tooltipGui.Show("NoActivate")
    WinGetPos(&guiX, &guiY, &guiW, &guiH, tooltipGui)
    newX := A_ScreenWidth - guiW - 10
    newY := A_ScreenHeight - guiH - 50
    tooltipGui.Show("NoActivate x" newX " y" newY)
    SetTimer(() => (IsObject(tooltipGui) ? tooltipGui.Destroy() : ""), -duration)
}

; ============================================================
; Tray Menu (UI)
; ============================================================
A_TrayMenu.Delete()
A_TrayMenu.Add("Pause Prevention", PauseActivity)
A_TrayMenu.Add("Resume Prevention", ResumeActivity)
A_TrayMenu.Add()
A_TrayMenu.Add("Settings", OpenSettings)

; --- v8.0: Add Power Center Submenu ---
powerMenu := Menu()
powerMenu.Add("Force Shutdown", HandleForceShutdown)
powerMenu.Add("Force Restart", HandleForceRestart)
powerMenu.Add()
powerMenu.Add("Abort!", HandleAbortShutdown)
A_TrayMenu.Add("Power Center", powerMenu)
; --- End v8.0 ---

A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

if (isPaused)
    A_TrayMenu.Disable("Pause Prevention")
else
    A_TrayMenu.Disable("Resume Prevention")

TraySetIcon("imageres.dll", isPaused ? 101 : 100)
UpdateTray(isPaused ? "paused" : "active")

; ============================================================
; Startup behaviour / initial timers
; ============================================================
if (!isPaused) {
    ShowCustomTooltip("StayAwake Is Now Running and Preventing Your Computer From Sleeping.", "active")
    StartIntelligentTimers()
} else {
    ShowCustomTooltip("StayAwake Started in Disabled Mode.", "paused")
}

; ============================================================
; Schedule engine (applies enabled schedules each minute)
; ============================================================
CheckSchedule() {
    global scheduleMode, scheduleData, isPaused, startupDefaultActive

    if (scheduleMode = "disabled")
        return

    currentTime := FormatTime(, "HH:mm")
    currentDay  := FormatTime(, "dddd")

    desiredActive := false

    if (scheduleMode = "simple") {
        desiredActive := IsTimeInRange(currentTime, scheduleData["SimpleOnTime"], scheduleData["SimpleOffTime"])
    } else if (scheduleMode = "advanced") {
        if (scheduleData[currentDay "Enabled"]) {
            desiredActive := IsTimeInRange(currentTime, scheduleData[currentDay "On"], scheduleData[currentDay "Off"])
        } else {
            ; Day disabled -> follow Auto-Start default
            desiredActive := startupDefaultActive
        }
    }

    ; Apply state if it changed
    if (desiredActive && isPaused) {
        isPaused := false
        StartIntelligentTimers()
        UpdateTray("active")
    } else if (!desiredActive && !isPaused) {
        isPaused := true
        StopIntelligentTimers()
        UpdateTray("paused")
    }
}

SetTimer(CheckSchedule, 60000)
CheckSchedule()

