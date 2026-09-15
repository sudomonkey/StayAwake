#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
SetWorkingDir(A_ScriptDir)
Persistent()

; ============================================================
; StayAwake - The Perfected Custom Tray Menu
; ============================================================

; ===== MODULE: THEME TOKENS =================================
global UI_FONT      := "Segoe UI"
global ICON_FONT    := "Segoe MDL2 Assets"

global CLR_BG       := 0x0F0F0F
global CLR_FOOTER   := 0x181818
global CLR_FIELD    := 0x1C1C1C
global CLR_DIVIDER  := 0x303030

global CLR_BTN_FILL   := 0x1C1C1C
global CLR_BTN_BORDER := 0x5A5A5A
global CLR_ACC_FILL   := 0x2F6FED

global CLR_TEXT     := 0xE0E0E0
global CLR_BTN_TEXT := 0xFFFFFF
global CLR_TEXT_ACC := 0xFFFFFF

global TXT_BODY := "cE0E0E0"
global TXT_OK   := "c5FE88A"
global TXT_WARN := "cFF8080"
global TXT_GHOST := "c5A5A5A"

global HEADER_HINT_GAP := 4
global HINT_CTRL_GAP   := 10
global SECTION_GAP_Y   := 22

global BODY_LINE_WIDTH    := 440
global COL_WIDTH          := 205
global COL2_X             := 259
global INPUT_WIDTH_NARROW := 72
global GUI_PAD_X          := 24
global GUI_WIDTH          := 488
global BTN_RADIUS         := 8

BgOpt(clr) {
    return "Background" Format("0x{:06X}", clr)
}
; ===== END MODULE: THEME TOKENS =============================


; ===== MODULE: APP STATE GLOBALS ============================
global APP_VERSION := "8.9"

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
global g_isLocked := false

global customCodeEnabled := false
global customCodePath := A_ScriptDir "\customcode.ahk"
global g_customCodePID := 0
global g_ahkExePath := ""

global g_shutdownPending := false

LoadSettings()
; ===== END MODULE: APP STATE GLOBALS ========================


; ===== MODULE: GDI+ LIFECYCLE & ASSETS ======================
global g_gdipToken := 0
global g_gdipModule := 0
global g_btnRefs := []

StartGdiplus() {
    global g_gdipToken, g_gdipModule
    if (g_gdipToken)
        return true
    g_gdipModule := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    if (!g_gdipModule)
        return false
    local si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)
    local token := 0
    if (DllCall("gdiplus\GdiplusStartup", "UPtr*", &token, "Ptr", si, "Ptr", 0) != 0)
        return false
    g_gdipToken := token
    return true
}

StopGdiplus() {
    global g_gdipToken, g_gdipModule
    if (g_gdipToken) {
        try DllCall("gdiplus\GdiplusShutdown", "UPtr", g_gdipToken)
        g_gdipToken := 0
    }
    if (g_gdipModule) {
        try DllCall("FreeLibrary", "Ptr", g_gdipModule)
        g_gdipModule := 0
    }
}

StartGdiplus()

; Generate Custom Tray Dots
CreateDotIcon(hexColor) {
    local pBitmap := 0, pGraphics := 0, hIcon := 0, pBrush := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 32, "Int", 32, "Int", 0, "Int", 0x26200A, "Ptr", 0, "UPtr*", &pBitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "UPtr", pBitmap, "UPtr*", &pGraphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "UPtr", pGraphics, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "UPtr", pGraphics, "UInt", 0x00000000) ; Transparent
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | hexColor, "UPtr*", &pBrush)
    DllCall("gdiplus\GdipFillEllipse", "UPtr", pGraphics, "UPtr", pBrush, "Float", 2, "Float", 2, "Float", 28, "Float", 28)
    DllCall("gdiplus\GdipDeleteBrush", "UPtr", pBrush)
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "UPtr", pBitmap, "UPtr*", &hIcon)
    DllCall("gdiplus\GdipDeleteGraphics", "UPtr", pGraphics)
    DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
    return hIcon
}

global g_IconActive := CreateDotIcon(0x5FE88A)
global g_IconPaused := CreateDotIcon(0xFF8080)

GetDpiScale(hwnd) {
    local dpi := 96
    try dpi := DllCall("user32\GetDpiForWindow", "Ptr", hwnd, "UInt")
    if (!dpi)
        dpi := 96
    return dpi / 96.0
}

DrawButtonBitmap(pxW, pxH, text, fontName, fontSize, bold, fillClr, borderClr, textClr, bgClr, radius) {
    local pBitmap := 0, pGraphics := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", pxW, "Int", pxH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "UPtr*", &pBitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "UPtr", pBitmap, "UPtr*", &pGraphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "UPtr", pGraphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "UPtr", pGraphics, "Int", 5)

    DllCall("gdiplus\GdipGraphicsClear", "UPtr", pGraphics, "UInt", 0xFF000000 | bgClr)

    local d := radius * 2
    local px := 0.5, py := 0.5, pw := pxW - 1.0, ph := pxH - 1.0
    local pPath := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "UPtr*", &pPath)
    DllCall("gdiplus\GdipAddPathArc", "UPtr", pPath, "Float", px, "Float", py, "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "UPtr", pPath, "Float", px + pw - d, "Float", py, "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "UPtr", pPath, "Float", px + pw - d, "Float", py + ph - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "UPtr", pPath, "Float", px, "Float", py + ph - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "UPtr", pPath)

    local pBrush := 0, pPen := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | fillClr, "UPtr*", &pBrush)
    DllCall("gdiplus\GdipFillPath", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", pPath)
    DllCall("gdiplus\GdipDeleteBrush", "UPtr", pBrush)

    DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFF000000 | borderClr, "Float", 1, "Int", 2, "UPtr*", &pPen)
    DllCall("gdiplus\GdipDrawPath", "UPtr", pGraphics, "UPtr", pPen, "UPtr", pPath)
    DllCall("gdiplus\GdipDeletePen", "UPtr", pPen)
    DllCall("gdiplus\GdipDeletePath", "UPtr", pPath)

    local pFamily := 0, pFont := 0, pFormat := 0, pTextBrush := 0
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "Str", fontName, "UPtr", 0, "UPtr*", &pFamily)
    DllCall("gdiplus\GdipCreateFont", "UPtr", pFamily, "Float", fontSize, "Int", (bold ? 1 : 0), "Int", 3, "UPtr*", &pFont)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "UShort", 0, "UPtr*", &pFormat)
    DllCall("gdiplus\GdipSetStringFormatAlign", "UPtr", pFormat, "Int", 1)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "UPtr", pFormat, "Int", 1)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | textClr, "UPtr*", &pTextBrush)

    local rect := Buffer(16, 0)
    NumPut("Float", 0, rect, 0), NumPut("Float", 0, rect, 4), NumPut("Float", pxW, rect, 8), NumPut("Float", pxH, rect, 12)

    DllCall("gdiplus\GdipDrawString", "UPtr", pGraphics, "Str", text, "Int", -1, "UPtr", pFont, "Ptr", rect, "UPtr", pFormat, "UPtr", pTextBrush)

    DllCall("gdiplus\GdipDeleteBrush", "UPtr", pTextBrush)
    DllCall("gdiplus\GdipDeleteStringFormat", "UPtr", pFormat)
    DllCall("gdiplus\GdipDeleteFont", "UPtr", pFont)
    DllCall("gdiplus\GdipDeleteFontFamily", "UPtr", pFamily)

    local hBitmap := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "UPtr", pBitmap, "UPtr*", &hBitmap, "UInt", 0)

    DllCall("gdiplus\GdipDeleteGraphics", "UPtr", pGraphics)
    DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)

    return hBitmap
}

MakeButton(guiObj, x, y, w, h, text, accent := false, cb := "", big := false, bgClr := "") {
    global g_btnRefs, UI_FONT, CLR_BG, CLR_BTN_FILL, CLR_BTN_BORDER, CLR_ACC_FILL, CLR_BTN_TEXT, CLR_TEXT_ACC, BTN_RADIUS
    if (bgClr = "")
        bgClr := CLR_BG
    local scale := GetDpiScale(guiObj.Hwnd)
    local pxW := Round(w * scale), pxH := Round(h * scale)
    local fillClr   := accent ? CLR_ACC_FILL : CLR_BTN_FILL
    local borderClr := accent ? CLR_ACC_FILL : CLR_BTN_BORDER
    local textClr   := accent ? CLR_TEXT_ACC : CLR_BTN_TEXT
    local fontSize  := (big ? 11 : 10) * scale
    local bold      := big ? true : false
    local radius    := BTN_RADIUS * scale

    local hBmp := DrawButtonBitmap(pxW, pxH, text, UI_FONT, fontSize, bold, fillClr, borderClr, textClr, bgClr, radius)
    local pic := guiObj.AddPicture("x" x " y" y " w" w " h" h " +0x100", "HBITMAP:*" hBmp)
    if (cb != "")
        pic.OnEvent("Click", (*) => cb())
    g_btnRefs.Push(pic)
    return pic
}
; ===== END MODULE: GDI+ LIFECYCLE & ASSETS ==================


; ===== MODULE: THEME HELPERS & UI BUILDERS ==================
ApplyDarkTitleBar(guiObj) {
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", guiObj.Hwnd, "int", 20, "int*", 1, "int", 4)
}
ApplyDarkControl(ctrl) {
    try DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)
}
AddDivider(guiObj, opts) {
    global CLR_DIVIDER
    return guiObj.AddText(opts " h1 " BgOpt(CLR_DIVIDER), "")
}
AddFooterBar(guiObj, yPos, w, h) {
    global CLR_FOOTER
    return guiObj.AddText("x0 y" yPos " w" w " h" h " " BgOpt(CLR_FOOTER), "")
}

AddThemedRadio(guiObj, opts, labelText, checked, labelWidth := 180) {
    local r := guiObj.AddRadio(opts " w16 h16 Checked" (checked ? "1" : "0"), "")
    ApplyDarkControl(r)
    local t := guiObj.AddText("x+8 yp+1 w" labelWidth, labelText)
    return { radio: r, label: t }
}
LinkRadioPair(a, b, cbA := "", cbB := "") {
    SelectA(*) {
        a.radio.Value := 1, b.radio.Value := 0
        if (cbA != "")
            cbA()
    }
    SelectB(*) {
        b.radio.Value := 1, a.radio.Value := 0
        if (cbB != "")
            cbB()
    }
    a.radio.OnEvent("Click", SelectA), a.label.OnEvent("Click", SelectA)
    b.radio.OnEvent("Click", SelectB), b.label.OnEvent("Click", SelectB)
}
AddStatusLine(guiObj, opts, glyphWidth := 16, textWidth := 240) {
    global ICON_FONT, UI_FONT
    guiObj.SetFont("s9 w400", ICON_FONT)
    local ico := guiObj.AddText(opts " w" glyphWidth, "")
    guiObj.SetFont("s10 w400", UI_FONT)
    local txt := guiObj.AddText("x+6 yp-1 w" textWidth, "")
    return { icon: ico, text: txt }
}
SetStatusLine(line, glyph, msg, colorOpt) {
    global ICON_FONT, UI_FONT
    line.icon.SetFont("s9 w400 " colorOpt, ICON_FONT)
    line.icon.Value := glyph
    line.text.SetFont("s10 w400 " colorOpt, UI_FONT)
    line.text.Value := msg
}

MakeDayPill(guiObj, x, y, size, letter, checked, cb := "") {
    global g_btnRefs, UI_FONT, CLR_BG, CLR_BTN_FILL, CLR_BTN_BORDER, CLR_ACC_FILL, CLR_TEXT, CLR_TEXT_ACC
    local scale := GetDpiScale(guiObj.Hwnd)
    local px := Round(size * scale), fontSize := 10 * scale, radius := px / 2
    local hOff := DrawButtonBitmap(px, px, letter, UI_FONT, fontSize, false, CLR_BG, CLR_BTN_BORDER, 0x8A8A8A, CLR_BG, radius)
    local hOn := DrawButtonBitmap(px, px, letter, UI_FONT, fontSize, true, CLR_ACC_FILL, CLR_ACC_FILL, CLR_TEXT_ACC, CLR_BG, radius)
    local picOff := guiObj.AddPicture("x" x " y" y " w" size " h" size " +0x100", "HBITMAP:*" hOff)
    local picOn := guiObj.AddPicture("x" x " y" y " w" size " h" size " +0x100", "HBITMAP:*" hOn)
    local pill := { on: picOn, off: picOff, enabled: checked }
    pill.Refresh := (self) => (self.on.Visible := self.enabled, self.off.Visible := !self.enabled)
    Toggle(*) {
        pill.enabled := !pill.enabled
        pill.Refresh()
        if (cb != "")
            cb()
    }
    picOn.OnEvent("Click", Toggle), picOff.OnEvent("Click", Toggle)
    pill.Refresh()
    g_btnRefs.Push(picOn), g_btnRefs.Push(picOff)
    return pill
}

MakeTimeChip(guiObj, x, y, hourVal, minVal) {
    global g_btnRefs, UI_FONT, CLR_FIELD, CLR_BTN_BORDER, CLR_BG, TXT_BODY
    local w := 92, h := 32
    local scale := GetDpiScale(guiObj.Hwnd)
    local hPlate := DrawButtonBitmap(Round(w * scale), Round(h * scale), ":", UI_FONT, 11 * scale, false, CLR_FIELD, CLR_BTN_BORDER, 0x8A8A8A, CLR_BG, 6 * scale)
    local plate := guiObj.AddPicture("x" x " y" y " w" w " h" h, "HBITMAP:*" hPlate)
    g_btnRefs.Push(plate)

    guiObj.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    local hourEdit := guiObj.AddEdit("x" (x + 11) " y" (y + 6) " w28 h20 Center Number Limit2 -E0x200 -Border " . BgOpt(CLR_FIELD), Format("{:02}", hourVal))
    local minEdit := guiObj.AddEdit("x" (x + 53) " y" (y + 6) " w28 h20 Center Number Limit2 -E0x200 -Border " . BgOpt(CLR_FIELD), Format("{:02}", minVal))

    hourEdit.OnEvent("Change", (ctrl, *) => (IsInteger(ctrl.Value) && Integer(ctrl.Value) > 23) ? (ctrl.Value := "23") : "")
    minEdit.OnEvent("Change", (ctrl, *) => (IsInteger(ctrl.Value) && Integer(ctrl.Value) > 59) ? (ctrl.Value := "59") : "")
    hourEdit.OnEvent("LoseFocus", (ctrl, *) => (ctrl.Value != "" && IsInteger(ctrl.Value)) ? (ctrl.Value := Format("{:02}", Integer(ctrl.Value))) : (ctrl.Value := "00"))
    minEdit.OnEvent("LoseFocus", (ctrl, *) => (ctrl.Value != "" && IsInteger(ctrl.Value)) ? (ctrl.Value := Format("{:02}", Integer(ctrl.Value))) : (ctrl.Value := "00"))
    return { plate: plate, hour: hourEdit, min: minEdit }
}
ReadTimeChip(chip, maxHour := 23) {
    local hv := Integer(chip.hour.Value = "" ? 0 : chip.hour.Value)
    local mv := Integer(chip.min.Value = "" ? 0 : chip.min.Value)
    if (hv < 0)
        hv := 0
    if (hv > maxHour)
        hv := maxHour
    if (mv < 0)
        mv := 0
    if (mv > 59)
        mv := 59
    return Format("{:02}", hv) ":" Format("{:02}", mv)
}
SetTimeChip(chip, hourVal, minVal) {
    chip.hour.Value := Format("{:02}", hourVal), chip.min.Value := Format("{:02}", minVal)
}
SetChipVisible(chip, state) {
    chip.plate.Visible := state, chip.hour.Visible := state, chip.min.Visible := state
}

; Safely parses INI time strings (e.g. "07:00") and prevents crashes if empty
ParseTimeStr(timeStr, defaultH := 7, defaultM := 0) {
    local parts := StrSplit(timeStr, ":")
    local h := (parts.Length >= 1 && IsInteger(parts[1])) ? Integer(parts[1]) : defaultH
    local m := (parts.Length >= 2 && IsInteger(parts[2])) ? Integer(parts[2]) : defaultM
    return {h: h, m: m}
}
; ===== END MODULE: THEME HELPERS & UI BUILDERS ==============


; ===== MODULE: CORE & TIMERS & SESSION HOOKS ================
SetPowerRequest(enable) {
    if (enable) {
        ; ES_CONTINUOUS (0x80000000) | ES_DISPLAY_REQUIRED (0x00000002) | ES_SYSTEM_REQUIRED (0x00000001)
        DllCall("Kernel32.dll\SetThreadExecutionState", "UInt", 0x80000003)
    } else {
        ; Clears flags: ES_CONTINUOUS
        DllCall("Kernel32.dll\SetThreadExecutionState", "UInt", 0x80000000)
    }
}
RefreshPowerState() {
    global isPaused, g_isLocked
    if (!isPaused && !g_isLocked) {
        SetPowerRequest(true)
    } else {
        SetPowerRequest(false)
    }
}

KeepAwake() {
    global preventionMethod
    if (preventionMethod = "mouse") {
        MouseMove(1, 0, 1, "R")
        MouseMove(-1, 0, 1, "R")
    } else {
        Send("{F15}")
    }
}
IsTimeInRange(current, start, end) {
    currentNum := Integer(StrReplace(current, ":")), startNum := Integer(StrReplace(start, ":")), endNum := Integer(StrReplace(end, ":"))
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
    if (scheduleData.Get("SameTime", true))
        return isPaused ? " (Schedule: On at " scheduleData.Get("SimpleOnTime", "07:00") ")" : " (Schedule: Off at " scheduleData.Get("SimpleOffTime", "18:00") ")"
    if (scheduleData.Get(currentDay "Enabled", true))
        return isPaused ? " (Schedule: On at " scheduleData.Get(currentDay "On", "07:00") ")" : " (Schedule: Off at " scheduleData.Get(currentDay "Off", "18:00") ")"
    return ""
}
ArmIntelligentTimer() {
    global timerIntervalMinutes, g_dueAtTick, g_keepAwakeTimerArmed, isPaused, g_isLocked
    if (isPaused || g_isLocked)
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
    global g_keepAwakeTimerArmed, isPaused, g_isLocked
    g_keepAwakeTimerArmed := false
    if (isPaused || g_isLocked)
        return
    KeepAwake()
    ArmIntelligentTimer()
}
WatchUserActivity() {
    global g_dueAtTick, g_watcherPeriodMs, isPaused, g_keepAwakeTimerArmed, timerIntervalMinutes, g_isLocked
    if (isPaused || g_isLocked)
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
    global g_watcherPeriodMs, g_isLocked
    if (g_isLocked)
        return
    SetTimer(WatchUserActivity, g_watcherPeriodMs)
    ArmIntelligentTimer()
}
StopIntelligentTimers() {
    SetTimer(WatchUserActivity, 0)
    SetTimer(DoKeepAwake, 0)
}

; --- Lock Screen Session Hook ---
WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
    global g_isLocked, isPaused
    if (wParam == 0x7) {        ; WTS_SESSION_LOCK
        g_isLocked := true
        StopIntelligentTimers()
        RefreshPowerState()
    } else if (wParam == 0x8) { ; WTS_SESSION_UNLOCK
        g_isLocked := false
        if (!isPaused) {
            StartIntelligentTimers()
            RefreshPowerState()
        }
    }
}
; ===== END MODULE: CORE & TIMERS & SESSION HOOKS ============


; ===== MODULE: CUSTOM CODE ==================================
FindAutoHotkeyExe() {
    global g_ahkExePath
    if (g_ahkExePath != "" && FileExist(g_ahkExePath))
        return g_ahkExePath
    local candidates := []
    local pf64 := EnvGet("ProgramW6432")
    if (pf64 != "") {
        candidates.Push(pf64 "\AutoHotkey\v2\AutoHotkey64.exe"), candidates.Push(pf64 "\AutoHotkey\v2\AutoHotkey32.exe"), candidates.Push(pf64 "\AutoHotkey\v2\AutoHotkey.exe")
    }
    candidates.Push(A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe"), candidates.Push(A_ProgramFiles "\AutoHotkey\v2\AutoHotkey.exe")
    for path in candidates {
        if (FileExist(path)) {
            g_ahkExePath := path
            return g_ahkExePath
        }
    }
    if (A_AhkPath != "" && FileExist(A_AhkPath))
        return A_AhkPath
    return ""
}
EnsureCustomCodeFile() {
    global customCodePath
    if (FileExist(customCodePath))
        return true
    
    local template := ""
    template .= "#Requires AutoHotkey v2.0`n"
    template .= "#SingleInstance Force`n"
    template .= "#NoTrayIcon`n`n"
    template .= "; ============================================================`n"
    template .= "; StayAwake - Custom Code`n"
    template .= "; ============================================================`n"
    template .= "; This file runs alongside StayAwake. Put your own hotkeys,`n"
    template .= "; hotstrings, and functions here.`n"
    template .= ";`n"
    template .= "; --- IMPORTANT RULES ---`n"
    template .= "; 1. AutoHotkey v2.0 MUST be installed on this machine.`n"
    template .= "; 2. Do NOT remove the #Requires or #SingleInstance lines above.`n"
    template .= "; 3. After editing, apply your changes via the StayAwake menu:`n"
    template .= ";    Custom Code > Reload Custom Code`n"
    template .= ";`n"
    template .= "; --- HOW TO READ & WRITE A HOTKEY ---`n"
    template .= ";`n"
    template .= "; ^+Home::                   <- 1. The keys to press (Ctrl+Shift+Home), ending in ::`n"
    template .= "; {                          <- 2. Open bracket to start the action`n"
    template .= ";     Run(`"notepad.exe`")     <- 3. The command you want to happen`n"
    template .= "; }                          <- 4. Close bracket to end the action`n"
    template .= ";`n"
    template .= "; Full official guide for hotkeys:`n"
    template .= "; https://www.autohotkey.com/docs/v2/Hotkeys.htm`n"
    template .= ";`n"
    template .= "; ============================================================`n"
    template .= "; YOUR CODE BELOW`n"
    template .= "; ============================================================`n`n"

    try {
        FileAppend(template, customCodePath, "UTF-8")
        return true
    } catch {
        return false
    }
}
IsCustomCodeRunning() {
    global g_customCodePID
    if (g_customCodePID = 0)
        return false
    return ProcessExist(g_customCodePID) ? true : false
}
LaunchCustomCode(quiet := false) {
    global customCodePath, g_customCodePID, isPaused
    if (IsCustomCodeRunning())
        return true
    if (!EnsureCustomCodeFile())
        return false
    local ahkExe := FindAutoHotkeyExe()
    if (ahkExe = "")
        return false
    try {
        Run('"' ahkExe '" "' customCodePath '"', , , &newPID)
        g_customCodePID := newPID
    } catch {
        return false
    }
    Sleep(900)
    if (!IsCustomCodeRunning())
        return false
    if (!quiet)
        ShowCustomTooltip("Custom code is running.", isPaused ? "paused" : "active")
    return true
}
StopCustomCode(quiet := false) {
    global g_customCodePID
    if (!IsCustomCodeRunning())
        return
    try ProcessClose(g_customCodePID)
    g_customCodePID := 0
    if (!quiet)
        ShowCustomTooltip("Custom code stopped.", "paused")
}
ReloadCustomCode(*) {
    global customCodeEnabled, isPaused
    if (!customCodeEnabled)
        return
    StopCustomCode(true)
    Sleep(250)
    LaunchCustomCode(true)
}
EditCustomCode(*) {
    global customCodePath
    EnsureCustomCodeFile()
    try Run('*edit "' customCodePath '"', A_ScriptDir)
    catch
        try Run('notepad.exe "' customCodePath '"', A_ScriptDir)
}
HandleEditCustomCode(*) => EditCustomCode()
HandleStopCustomCode(*) => StopCustomCode()
; ===== END MODULE: CUSTOM CODE ==============================


; ===== MODULE: SCHEDULE WINDOW ==============================
OpenScheduleSettings(*) {
    global scheduleMode, scheduleData, UI_FONT, CLR_BG, CLR_FOOTER, TXT_BODY, HEADER_HINT_GAP, HINT_CTRL_GAP, SECTION_GAP_Y, GUI_PAD_X, g_btnRefs
    static guiSchedule := ""
    try if (IsObject(guiSchedule))
        guiSchedule.Destroy()

    g_btnRefs := []
    local isWindowShown := false
    local WIN_W := 520, bodyW := WIN_W - (GUI_PAD_X * 2), rightEdge := GUI_PAD_X + bodyW

    guiSchedule := Gui("+AlwaysOnTop -Resize", "Schedule Settings")
    guiSchedule.MarginX := GUI_PAD_X, guiSchedule.MarginY := 20, guiSchedule.BackColor := CLR_BG
    ApplyDarkTitleBar(guiSchedule)

    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    letters := ["S","M","T","W","T","F","S"]

    guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSchedule.AddText("xm w" bodyW, "This schedule automatically turns StayAwake on and off. You can control the manual Active/Paused state in the main Settings window.")

    guiSchedule.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    guiSchedule.AddText("xm y+" SECTION_GAP_Y " w" bodyW, "Schedule Mode")

    guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    rOff := AddThemedRadio(guiSchedule, "xm y+" HINT_CTRL_GAP, "Disabled", (scheduleMode = "disabled"), 110)
    rOn := AddThemedRadio(guiSchedule, "x180 yp-1", "Scheduled", (scheduleMode != "disabled"), 120)

    div1 := AddDivider(guiSchedule, "xm y+" SECTION_GAP_Y " w" bodyW)

    guiSchedule.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    hdrDays := guiSchedule.AddText("xm y+" SECTION_GAP_Y " w" bodyW, "Active Days")

    guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    hintDays := guiSchedule.AddText("xm y+" HEADER_HINT_GAP " w" bodyW, "Days not selected stay on your launch behavior setting.")
    hintDays.GetPos(&hdX, &hdY, &hdW, &hdH)
    pillY := hdY + hdH + HINT_CTRL_GAP, pillSize := 34, pillGap := 8

    pills := []
    for i, letter in letters {
        pills.Push(MakeDayPill(guiSchedule, GUI_PAD_X + ((i - 1) * (pillSize + pillGap)), pillY, pillSize, letter, scheduleData.Get(days[i] "Enabled", true), (*) => RefreshRows()))
    }

    div2 := AddDivider(guiSchedule, "xm y" (pillY + pillSize + SECTION_GAP_Y) " w" bodyW)

    timesHdrY := pillY + pillSize + SECTION_GAP_Y + SECTION_GAP_Y
    guiSchedule.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    hdrTimes := guiSchedule.AddText("xm y" timesHdrY " w" bodyW, "Times (24-Hour Format)")

    guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    chkSame := guiSchedule.AddCheckbox("xm y+" HINT_CTRL_GAP " w" bodyW . " Checked" (scheduleData.Get("SameTime", true) ? "1" : "0"), "Same time on every active day")
    ApplyDarkControl(chkSame)
    chkSame.GetPos(&csX, &csY, &csW, &csH)
    rowStartY := csY + csH + 16

    sharedOn := ParseTimeStr(scheduleData.Get("SimpleOnTime", "07:00"))
    sharedOff := ParseTimeStr(scheduleData.Get("SimpleOffTime", "18:00"))
    
    guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    lblSharedOn := guiSchedule.AddText("xm y" (rowStartY + 7) " w78", "Turn on at")
    chipSharedOn := MakeTimeChip(guiSchedule, GUI_PAD_X + 86, rowStartY, sharedOn.h, sharedOn.m)
    lblSharedOff := guiSchedule.AddText("x" (GUI_PAD_X + 200) " y" (rowStartY + 7) " w78", "Turn off at")
    chipSharedOff := MakeTimeChip(guiSchedule, GUI_PAD_X + 286, rowStartY, sharedOff.h, sharedOff.m)

    rowH := 40
    dayRows := []
    for i, day in days {
        local ry := rowStartY + ((i - 1) * rowH)
        local onTime := ParseTimeStr(scheduleData.Get(day "On", "07:00"))
        local offTime := ParseTimeStr(scheduleData.Get(day "Off", "18:00"))
        guiSchedule.SetFont("s10 w400 " TXT_BODY, UI_FONT)
        local lbl := guiSchedule.AddText("xm y" (ry + 7) " w96", day)
        local chipOn := MakeTimeChip(guiSchedule, GUI_PAD_X + 104, ry, onTime.h, onTime.m)
        local lblTo := guiSchedule.AddText("x" (GUI_PAD_X + 206) " y" (ry + 7) " w22", "to")
        local chipOff := MakeTimeChip(guiSchedule, GUI_PAD_X + 234, ry, offTime.h, offTime.m)
        local offNote := guiSchedule.AddText("x" (GUI_PAD_X + 104) " y" (ry + 7) " w120", "Not active")
        dayRows.Push({ label: lbl, chipOn: chipOn, lblTo: lblTo, chipOff: chipOff, note: offNote })
    }

    ctrlFooterBar := AddFooterBar(guiSchedule, 0, WIN_W, 72)
    btnDefaults := MakeButton(guiSchedule, GUI_PAD_X, 0, 108, 36, "Defaults", false, ResetDefaults, true, CLR_FOOTER)
    btnCancel := MakeButton(guiSchedule, rightEdge - 214, 0, 102, 36, "Cancel", false, (*) => guiSchedule.Destroy(), true, CLR_FOOTER)
    btnSave := MakeButton(guiSchedule, rightEdge - 102, 0, 102, 36, "Save", true, SaveNow, true, CLR_FOOTER)
    ctrlBottomEdge := guiSchedule.AddText("x0 y0 w" WIN_W " h1 " BgOpt(CLR_FOOTER), "")

    RefreshRows(*) {
        local scheduled := (rOn.radio.Value = 1), sameTime := (chkSame.Value = 1)
        div1.Visible := scheduled, hdrDays.Visible := scheduled, hintDays.Visible := scheduled
        div2.Visible := scheduled, hdrTimes.Visible := scheduled, chkSame.Visible := scheduled

        for p in pills
            (p.on.Visible := scheduled && p.enabled, p.off.Visible := scheduled && !p.enabled)

        local showShared := scheduled && sameTime
        lblSharedOn.Visible := showShared, lblSharedOff.Visible := showShared
        SetChipVisible(chipSharedOn, showShared), SetChipVisible(chipSharedOff, showShared)

        for i, row in dayRows {
            local showRow := scheduled && !sameTime, dayOn := pills[i].enabled
            row.label.Visible := showRow, row.label.Opt(dayOn ? "cF2F2F2" : "c6E6E6E"), row.label.Redraw()
            SetChipVisible(row.chipOn, showRow && dayOn), SetChipVisible(row.chipOff, showRow && dayOn)
            row.lblTo.Visible := showRow && dayOn, row.note.Visible := showRow && !dayOn
        }

        rOn.radio.GetPos(&rx, &ry, &rw, &rh)
        local modeBottomY := ry + rh
        local activeContentY := !scheduled ? modeBottomY : (sameTime ? (rowStartY + 40) : (rowStartY + (rowH * 7)))
        local footerY := activeContentY + 14, footBtnY := footerY + 19

        ctrlFooterBar.Move( , footerY), btnDefaults.Move( , footBtnY), btnCancel.Move( , footBtnY), btnSave.Move( , footBtnY), ctrlBottomEdge.Move( , footerY + 72)
        
        guiSchedule.MarginX := 0
        if (isWindowShown)
            guiSchedule.Show("AutoSize")
    }

    ResetDefaults(*) {
        SetTimeChip(chipSharedOn, 7, 0), SetTimeChip(chipSharedOff, 18, 0)
        for i, row in dayRows {
            SetTimeChip(row.chipOn, 7, 0), SetTimeChip(row.chipOff, 18, 0), pills[i].enabled := true
        }
        chkSame.Value := 1
        RefreshRows()
    }

    SaveNow(*) {
        if (rOn.radio.Value = 1) {
            if (chkSame.Value = 1) {
                if (ReadTimeChip(chipSharedOn) >= ReadTimeChip(chipSharedOff)) {
                    ShowCustomTooltip("Turn on time must be earlier than Turn off time.", "paused", 3500)
                    return
                }
            } else {
                for i, row in dayRows {
                    if (pills[i].enabled && ReadTimeChip(row.chipOn) >= ReadTimeChip(row.chipOff)) {
                        ShowCustomTooltip(days[i] ": Turn on time must be earlier than Turn off time.", "paused", 3500)
                        return
                    }
                }
            }
        }
        SaveScheduleHandler(guiSchedule, rOn.radio, chkSame, pills, chipSharedOn, chipSharedOff, dayRows, days)
    }

    LinkRadioPair(rOff, rOn, (*) => RefreshRows(), (*) => RefreshRows())
    chkSame.OnEvent("Click", (*) => RefreshRows())
    RefreshRows()

    guiSchedule.OnEvent("Escape", (*) => guiSchedule.Destroy())
    guiSchedule.MarginY := 0
    guiSchedule.MarginX := 0
    guiSchedule.Show("AutoSize Center")
    isWindowShown := true
    ApplyDarkTitleBar(guiSchedule)
}

SaveScheduleHandler(guiObj, radioOn, chkSame, pills, chipSharedOn, chipSharedOff, dayRows, days) {
    global scheduleMode, scheduleData, isPaused
    scheduleMode := (radioOn.Value = 1) ? "scheduled" : "disabled"
    scheduleData["SameTime"] := (chkSame.Value = 1)
    scheduleData["SimpleOnTime"]  := ReadTimeChip(chipSharedOn)
    scheduleData["SimpleOffTime"] := ReadTimeChip(chipSharedOff)

    for i, day in days {
        scheduleData[day "Enabled"] := pills[i].enabled
        scheduleData[day "On"]  := ReadTimeChip(dayRows[i].chipOn)
        scheduleData[day "Off"] := ReadTimeChip(dayRows[i].chipOff)
    }
    SaveScheduleSettings()
    UpdateTray(isPaused ? "paused" : "active")
    guiObj.Destroy()
    ShowCustomTooltip("Schedule saved.", isPaused ? "paused" : "active")
}
; ===== END MODULE: SCHEDULE WINDOW ==========================


; ===== MODULE: SETTINGS WINDOW ==============================
OpenSettings(*) {
    global APP_VERSION, timerIntervalMinutes, preventionMethod, startEnabled, startupDefaultActive, customCodeEnabled, customCodePath
    global UI_FONT, CLR_BG, CLR_FOOTER, CLR_FIELD, TXT_BODY, HEADER_HINT_GAP, HINT_CTRL_GAP, SECTION_GAP_Y, BODY_LINE_WIDTH, COL_WIDTH, COL2_X, INPUT_WIDTH_NARROW, GUI_PAD_X, GUI_WIDTH, g_btnRefs
    static guiSettings := ""
    try if (IsObject(guiSettings))
        guiSettings.Destroy()

    g_btnRefs := []
    guiSettings := Gui("+AlwaysOnTop -Resize", "StayAwake Settings - v" APP_VERSION)
    guiSettings.MarginX := GUI_PAD_X, guiSettings.MarginY := 20, guiSettings.BackColor := CLR_BG
    ApplyDarkTitleBar(guiSettings)

    local rightEdge := GUI_PAD_X + BODY_LINE_WIDTH

    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    introText := guiSettings.AddText("xm w" BODY_LINE_WIDTH, GetIntroText(preventionMethod, timerIntervalMinutes))

    guiSettings.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" SECTION_GAP_Y " w" BODY_LINE_WIDTH, "Activity")
    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" HEADER_HINT_GAP " w" BODY_LINE_WIDTH, "Recommended: 5-10 minutes")
    guiSettings.AddText("xm y+" HINT_CTRL_GAP " w300", "Activity Interval (minutes)")
    inputInterval := guiSettings.AddEdit("x" (rightEdge - INPUT_WIDTH_NARROW) . " yp-5 w" INPUT_WIDTH_NARROW " h28 Center Number " BgOpt(CLR_FIELD), timerIntervalMinutes)
    ApplyDarkControl(inputInterval)

    AddDivider(guiSettings, "xm y+" SECTION_GAP_Y " w" BODY_LINE_WIDTH)

    guiSettings.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" SECTION_GAP_Y " w" BODY_LINE_WIDTH, "Prevention Method")
    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" HEADER_HINT_GAP " w" BODY_LINE_WIDTH, "How the app keeps your session awake")
    rMouse := AddThemedRadio(guiSettings, "xm y+" HINT_CTRL_GAP, "Move mouse slightly", (preventionMethod = "mouse"), 180)
    rKey := AddThemedRadio(guiSettings, "x" COL2_X " yp-1", "Press harmless key (F15)", (preventionMethod = "keystroke"), 190)

    LinkRadioPair(rMouse, rKey, (*) => (preventionMethod := "mouse", UpdateIntroMouse(introText, inputInterval.Value)), (*) => (preventionMethod := "keystroke", UpdateIntroKeystroke(introText, inputInterval.Value)))
    inputInterval.OnEvent("Change", (*) => (rMouse.radio.Value = 1 ? UpdateIntroMouse(introText, inputInterval.Value) : UpdateIntroKeystroke(introText, inputInterval.Value)))

    AddDivider(guiSettings, "xm y+" SECTION_GAP_Y " w" BODY_LINE_WIDTH)

    shortcutPath  := A_Startup "\StayAwake.lnk", alreadyExists := FileExist(shortcutPath) ? true : false, startEnabled  := alreadyExists
    guiSettings.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    hdrStartup := guiSettings.AddText("xm y+" SECTION_GAP_Y " w" COL_WIDTH, "Startup")
    hdrStartup.GetPos(&colX, &colStartY, &colW, &colH)
    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" HEADER_HINT_GAP " w" COL_WIDTH, "Launch at Windows Startup")
    rYes := AddThemedRadio(guiSettings, "xm y+" HINT_CTRL_GAP, "Yes", startEnabled, 50)
    rNo  := AddThemedRadio(guiSettings, "x+18 yp-1", "No", !startEnabled, 50)

    statusLine := AddStatusLine(guiSettings, "xm y+10", 16, 220)
    statusLine.text.GetPos(&sx, &sy, &sw, &sh)
    leftEndY := sy + sh

    LinkRadioPair(rYes, rNo, (*) => (startEnabled := true, UpdateStatusYes(statusLine, alreadyExists)), (*) => (startEnabled := false, UpdateStatusNo(statusLine)))
    if (startEnabled)
        UpdateStatusYes(statusLine, alreadyExists)
    else
        UpdateStatusNo(statusLine)

    guiSettings.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    guiSettings.AddText("x" COL2_X " y" colStartY " w" COL_WIDTH, "Launch Behavior")
    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSettings.AddText("x" COL2_X " y+" HEADER_HINT_GAP " w" COL_WIDTH, "When no schedule is active")
    rActive := AddThemedRadio(guiSettings, "x" COL2_X " y+" HINT_CTRL_GAP, "Active", startupDefaultActive, 70)
    rPaused := AddThemedRadio(guiSettings, "x+18 yp-1", "Paused", !startupDefaultActive, 70)
    LinkRadioPair(rActive, rPaused, (*) => (startupDefaultActive := true), (*) => (startupDefaultActive := false))

    AddDivider(guiSettings, "xm y" (leftEndY + SECTION_GAP_Y) " w" BODY_LINE_WIDTH)

    guiSettings.SetFont("s11 w600 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" SECTION_GAP_Y " w" BODY_LINE_WIDTH, "Custom Code")
    guiSettings.SetFont("s10 w400 " TXT_BODY, UI_FONT)
    guiSettings.AddText("xm y+" HEADER_HINT_GAP " w" BODY_LINE_WIDTH, "Run your own hotkeys from customcode.ahk. Requires AutoHotkey v2.0.")
    chkCustomCode := guiSettings.AddCheckbox("xm y+" HINT_CTRL_GAP " w" BODY_LINE_WIDTH . " Checked" (customCodeEnabled ? "1" : "0"), "Enable Custom Code")
    ApplyDarkControl(chkCustomCode)

    customLine := AddStatusLine(guiSettings, "xm y+10", 16, 400)
    UpdateCustomCodeStatus(customLine)
    customLine.text.GetPos(&clX, &clY, &clW, &clH)
    btnRowY := clY + clH + 14

    btnEdit := MakeButton(guiSettings, GUI_PAD_X, btnRowY, 92, 34, "Edit", false, (*) => EditCustomCode())
    btnReload := MakeButton(guiSettings, GUI_PAD_X + 102, btnRowY, 92, 34, "Reload", false, (*) => (ReloadCustomCode(), UpdateCustomCodeStatus(customLine)))
    
    ; Hide edit/reload buttons if not enabled
    btnEdit.Visible := customCodeEnabled
    btnReload.Visible := customCodeEnabled

    chkCustomCode.OnEvent("Click", (ctrl, *) => (
        UpdateCustomCodeStatus(customLine),
        btnEdit.Visible := ctrl.Value,
        btnReload.Visible := ctrl.Value
    ))

    footerY := btnRowY + 34 + 22
    AddFooterBar(guiSettings, footerY, GUI_WIDTH, 72)
    footBtnY := footerY + 19

    SaveNow(*) {
        SaveSettingsHandler(inputInterval, rMouse.radio, rYes.radio, shortcutPath, rActive.radio, chkCustomCode, guiSettings)
    }

    btnSchedule := MakeButton(guiSettings, GUI_PAD_X, footBtnY, 108, 36, "Schedule", false, (*) => OpenScheduleSettings(), true, CLR_FOOTER)
    btnCancel := MakeButton(guiSettings, rightEdge - 214, footBtnY, 102, 36, "Cancel", false, (*) => guiSettings.Destroy(), true, CLR_FOOTER)
    btnSave := MakeButton(guiSettings, rightEdge - 102, footBtnY, 102, 36, "Save", true, SaveNow, true, CLR_FOOTER)

    guiSettings.OnEvent("Escape", (*) => guiSettings.Destroy())
    guiSettings.AddText("x0 y" (footerY + 72) " w" GUI_WIDTH " h1 " BgOpt(CLR_FOOTER), "")
    
    guiSettings.MarginY := 0
    guiSettings.MarginX := 0
    guiSettings.Show("AutoSize Center")
    try {
        ControlFocus(chkCustomCode, guiSettings), PostMessage(0xB1, -1, 0, inputInterval)
    }
}

GetIntroText(method, intervalMin) {
    return (method = "mouse") ? "Moving your mouse by one pixel every " intervalMin " minute(s) to keep this session active." : "Sending a harmless key press (F15) every " intervalMin " minute(s) to keep this session active."
}
UpdateIntroMouse(textCtrl, intervalMin) {
    textCtrl.Value := "Moving your mouse by one pixel every " intervalMin " minute(s) to keep this session active."
}
UpdateIntroKeystroke(textCtrl, intervalMin) {
    textCtrl.Value := "Sending a harmless key press (F15) every " intervalMin " minute(s) to keep this session active."
}
UpdateStatusYes(line, alreadyExists, *) {
    global TXT_OK
    SetStatusLine(line, Chr(0xE73E), alreadyExists ? "Already in the startup folder" : "Will launch at startup when saved", TXT_OK)
}
UpdateStatusNo(line, *) {
    global TXT_WARN
    SetStatusLine(line, Chr(0xE711), "Will not launch at startup when saved", TXT_WARN)
}
UpdateCustomCodeStatus(line, *) {
    global customCodePath, TXT_OK, TXT_WARN, TXT_BODY
    if (IsCustomCodeRunning())
        return SetStatusLine(line, Chr(0xE930), "Running - customcode.ahk", TXT_OK)
    if (FindAutoHotkeyExe() = "")
        return SetStatusLine(line, Chr(0xE7BA), "AutoHotkey v2.0 not found - install it from autohotkey.com", TXT_WARN)
    if (!FileExist(customCodePath))
        return SetStatusLine(line, Chr(0xE946), "customcode.ahk will be created when you enable and save", TXT_BODY)
    SetStatusLine(line, Chr(0xE70F), "Ready - Click Edit to customize your code", TXT_BODY)
}

SaveSettingsHandler(intervalCtrl, radioMouse, radioStartupYes, shortcutPath, radioActive, chkCustomCode, guiSettings) {
    global timerIntervalMinutes, preventionMethod, startEnabled, isPaused, startupDefaultActive, customCodeEnabled
    newInterval := intervalCtrl.Value
    if (newInterval < 1)
        newInterval := 1
    if (newInterval > 600)
        newInterval := 600
    timerIntervalMinutes := newInterval
    preventionMethod := (radioMouse.Value = 1) ? "mouse" : "keystroke"
    
    SaveSettingsToFile(timerIntervalMinutes, preventionMethod)

    startEnabled := (radioStartupYes.Value = 1)
    if (startEnabled) {
        if (!FileExist(shortcutPath))
            FileCreateShortcut(A_ScriptFullPath, shortcutPath, A_ScriptDir)
    } else {
        if (FileExist(shortcutPath))
            try FileDelete(shortcutPath)
    }

    newStartupDefaultActive := (radioActive.Value = 1)
    SaveStartupSettings(startEnabled, newStartupDefaultActive ? "active" : "paused")
    startupDefaultActive := newStartupDefaultActive

    newCustomCodeEnabled := (chkCustomCode.Value = 1)
    if (newCustomCodeEnabled != customCodeEnabled) {
        customCodeEnabled := newCustomCodeEnabled
        SaveCustomCodeSettings(customCodeEnabled)
        if (customCodeEnabled) {
            EnsureCustomCodeFile()
            LaunchCustomCode(true)
        } else {
            StopCustomCode(true)
        }
    } else if (customCodeEnabled && !IsCustomCodeRunning()) {
        EnsureCustomCodeFile()
        LaunchCustomCode(true)
    }

    if (!isPaused) {
        StopIntelligentTimers()
        StartIntelligentTimers()
    }
    RefreshPowerState()
    guiSettings.Destroy()
    ShowCustomTooltip("Settings saved.", isPaused ? "paused" : "active")
}
; ===== END MODULE: SETTINGS WINDOW ==========================


; ===== MODULE: SETTINGS PERSISTENCE =========================
LoadSettings() {
    global timerIntervalMinutes, preventionMethod, iniFile, startEnabled, scheduleMode, scheduleData, isPaused, startupDefaultActive, customCodeEnabled
    InitializeScheduleDataDefaults()

    if (FileExist(iniFile)) {
        timerIntervalMinutes := IniRead(iniFile, "Settings", "IntervalMinutes", 5)
        preventionMethod     := IniRead(iniFile, "Settings", "PreventionMethod", "mouse")
        startEnabled         := (IniRead(iniFile, "Startup",  "StartEnabled", "true") = "true")
        startupState         := IniRead(iniFile, "Startup",  "StartupState", "active")
        scheduleMode         := IniRead(iniFile, "Schedule", "Mode", "disabled")
        customCodeEnabled    := (IniRead(iniFile, "CustomCode", "Enabled", "false") = "true")

        if (timerIntervalMinutes < 1)
            timerIntervalMinutes := 1
        if (timerIntervalMinutes > 600)
            timerIntervalMinutes := 600
        if (preventionMethod != "mouse" && preventionMethod != "keystroke")
            preventionMethod := "mouse"

        startupDefaultActive := (startupState = "active")
        if (!startupDefaultActive)
            isPaused := true

        LoadScheduleData()
    } else {
        SaveSettingsToFile(timerIntervalMinutes, preventionMethod)
        SaveStartupSettings(startEnabled, "active")
        startupDefaultActive := true
        customCodeEnabled := false
        SaveCustomCodeSettings(false)
        SaveScheduleSettings()
    }
    if (!startEnabled)
        isPaused := true
}

InitializeScheduleDataDefaults() {
    global scheduleData
    scheduleData["SameTime"]      := true
    scheduleData["SimpleOnTime"]  := "07:00"
    scheduleData["SimpleOffTime"] := "18:00"
    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for _, day in days {
        scheduleData[day "Enabled"] := true
        scheduleData[day "On"]  := "07:00"
        scheduleData[day "Off"] := "18:00"
    }
}

LoadScheduleData() {
    global scheduleData, iniFile, scheduleMode
    if (scheduleMode = "simple") {
        scheduleMode := "scheduled", scheduleData["SameTime"] := true
    } else if (scheduleMode = "advanced") {
        scheduleMode := "scheduled", scheduleData["SameTime"] := false
    } else if (scheduleMode = "scheduled") {
        scheduleData["SameTime"] := (IniRead(iniFile, "Schedule", "SameTime", "true") = "true")
    }

    scheduleData["SimpleOnTime"]  := IniRead(iniFile, "Schedule", "SimpleOnTime", "07:00")
    scheduleData["SimpleOffTime"] := IniRead(iniFile, "Schedule", "SimpleOffTime", "18:00")
    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for _, day in days {
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
    IniWrite(enabled ? "true" : "false", iniFile, "Startup", "StartEnabled"), IniWrite(state, iniFile, "Startup", "StartupState")
    startupDefaultActive := (state = "active")
}

SaveCustomCodeSettings(enabled) {
    global iniFile
    IniWrite(enabled ? "true" : "false", iniFile, "CustomCode", "Enabled")
}

SaveScheduleSettings() {
    global iniFile, scheduleMode, scheduleData
    IniWrite(scheduleMode, iniFile, "Schedule", "Mode")
    IniWrite(scheduleData.Get("SameTime", true) ? "true" : "false", iniFile, "Schedule", "SameTime")
    IniWrite(scheduleData.Get("SimpleOnTime", "07:00"), iniFile, "Schedule", "SimpleOnTime")
    IniWrite(scheduleData.Get("SimpleOffTime", "18:00"), iniFile, "Schedule", "SimpleOffTime")
    days := ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    for _, day in days {
        IniWrite(scheduleData.Get(day "Enabled", true) ? "true" : "false", iniFile, "Schedule", day "Enabled")
        IniWrite(scheduleData.Get(day "On", "07:00"),  iniFile, "Schedule", day "On")
        IniWrite(scheduleData.Get(day "Off", "18:00"), iniFile, "Schedule", day "Off")
    }
}
; ===== END MODULE: SETTINGS PERSISTENCE =====================


; ===== MODULE: TRAY ACTIONS & POWER =========================
PauseActivity(*) {
    global isPaused
    if (isPaused)
        return
    isPaused := true
    StopIntelligentTimers()
    RefreshPowerState()
    try ShowCustomTooltip("StayAwake prevention paused.", "paused")
    UpdateTray("paused")
}
ResumeActivity(*) {
    global isPaused
    if (!isPaused)
        return
    isPaused := false
    StartIntelligentTimers()
    RefreshPowerState()
    try ShowCustomTooltip("StayAwake prevention active. Your computer won't go to sleep.", "active")
    UpdateTray("active")
}
UpdateTray(state) {
    global g_IconPaused, g_IconActive
    scheduleInfo := GetScheduleTooltip()
    try {
        if (state = "paused") {
            TraySetIcon("HICON:*" g_IconPaused)
            A_IconTip := "StayAwake Prevention Paused" scheduleInfo
        } else {
            TraySetIcon("HICON:*" g_IconActive)
            A_IconTip := "StayAwake Prevention Active" scheduleInfo
        }
    }
}

ClearShutdownPending() {
    global g_shutdownPending := false
}

HandleForceShutdown(*) {
    ShowCustomConfirm("SHUTDOWN?!", "ARE YOU SURE YOU WANT TO INITIATE A 30 SECOND SHUTDOWN?", ExecuteShutdown)
}
ExecuteShutdown() {
    global g_shutdownPending := true
    Run('cmd.exe /c shutdown /s /f /t 30', , "Hide")
    ShowCustomTooltip("Shutdown in 30s. Use Power Center > Abort! to cancel.", "active", 3000)
    SetTimer(ClearShutdownPending, -30000)
}

HandleForceRestart(*) {
    ShowCustomConfirm("RESTART?!", "ARE YOU SURE YOU WANT TO INITIATE A 30 SECOND RESTART?", ExecuteRestart)
}
ExecuteRestart() {
    global g_shutdownPending := true
    Run('cmd.exe /c shutdown /r /f /t 30', , "Hide")
    ShowCustomTooltip("Restart in 30s. Use Power Center > Abort! to cancel.", "active", 3000)
    SetTimer(ClearShutdownPending, -30000)
}

HandleAbortShutdown(*) {
    global g_shutdownPending := false
    SetTimer(ClearShutdownPending, 0)
    Run('cmd.exe /c shutdown /a', , "Hide")
    ShowCustomTooltip("Shutdown/restart aborted.", "active")
}

ShowCustomConfirm(title, msg, confirmCb) {
    static confirmGui := ""
    try if (IsObject(confirmGui))
        confirmGui.Destroy()

    global UI_FONT, ICON_FONT, CLR_BG, CLR_FOOTER, TXT_BODY, TXT_WARN, GUI_PAD_X, g_btnRefs

    confirmGui := Gui("+AlwaysOnTop -Resize -MaximizeBox -MinimizeBox", title)
    confirmGui.MarginX := GUI_PAD_X, confirmGui.MarginY := 20, confirmGui.BackColor := CLR_BG
    ApplyDarkTitleBar(confirmGui)

    local WIN_W := 420
    local rightEdge := WIN_W - GUI_PAD_X

    ; Warning Icon (MDL2 Warning Triangle painted Yellow/Orange)
    confirmGui.SetFont("s26 w400 cFFB900", ICON_FONT)
    confirmGui.AddText("xm y24 w32", Chr(0xE814))

    ; Message
    confirmGui.SetFont("s10 w600 " TXT_BODY, UI_FONT)
    confirmGui.AddText("x+12 yp+6 w" (WIN_W - GUI_PAD_X * 2 - 44), msg)

    local footerY := 84
    AddFooterBar(confirmGui, footerY, WIN_W, 72)
    local footBtnY := footerY + 19

    btnNo := MakeButton(confirmGui, rightEdge - 214, footBtnY, 102, 36, "No", false, (*) => confirmGui.Destroy(), true, CLR_FOOTER)
    btnYes := MakeButton(confirmGui, rightEdge - 102, footBtnY, 102, 36, "Yes", true, TriggerYes, true, CLR_FOOTER)

    TriggerYes(*) {
        confirmGui.Destroy()
        if (confirmCb != "")
            confirmCb()
    }

    confirmGui.OnEvent("Escape", (*) => confirmGui.Destroy())
    confirmGui.AddText("x0 y" (footerY + 72) " w" WIN_W " h1 " BgOpt(CLR_FOOTER), "")
    confirmGui.MarginY := 0
    confirmGui.MarginX := 0
    confirmGui.Show("AutoSize Center")
}

ShowCustomTooltip(msg, state := "active", duration := 2000) {
    static tooltipGui := ""
    if (IsObject(tooltipGui))
        try tooltipGui.Destroy()
    tooltipGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notification")
    tooltipGui.BackColor := 0x181818
    tooltipGui.SetFont("s11 w500 " TXT_BODY, UI_FONT)
    tooltipGui.MarginX := 20, tooltipGui.MarginY := 16
    tooltipGui.AddPicture("w32 h32 Icon105", "imageres.dll")
    tooltipGui.AddText("x+12 yp+6 w360", msg)
    tooltipGui.Show("NoActivate")
    WinGetPos(&guiX, &guiY, &guiW, &guiH, tooltipGui)
    tooltipGui.Show("NoActivate x" (A_ScreenWidth - guiW - 10) " y" (A_ScreenHeight - guiH - 50))
    SetTimer(() => (IsObject(tooltipGui) ? tooltipGui.Destroy() : ""), -duration)
}
; ===== END MODULE: TRAY ACTIONS & POWER =====================


; ===== MODULE: ACCORDION CUSTOM TRAY MENU ===================
A_TrayMenu.Delete()
OnMessage(0x404, OnTrayIconClick)

global g_MnuMain := ""
global g_MainRows := []
global g_HoveredRowObj := ""
global g_PowerExpanded := false
global g_CustomExpanded := false
global g_MenuIsRefreshing := false
global g_LockedWinX := 0
global g_LockedBottomY := 0

OnTrayIconClick(wParam, lParam, msg, hwnd) {
    if (lParam = 0x202 || lParam = 0x205) { 
        global g_PowerExpanded := false
        global g_CustomExpanded := false
        global g_MenuIsRefreshing := false
        SetTimer(CreateCustomMenu, -10)
        return 0
    }
}

CreateCustomMenu() {
    global g_MnuMain, g_MainRows, isPaused, customCodeEnabled
    global g_PowerExpanded, g_CustomExpanded, g_MenuIsRefreshing
    global g_LockedWinX, g_LockedBottomY, g_HoveredRowObj
    global g_shutdownPending
    global UI_FONT, CLR_BG, CLR_FOOTER, CLR_DIVIDER, TXT_BODY, TXT_WARN, TXT_OK, TXT_GHOST
    
    if (IsObject(g_MnuMain)) {
        SetTimer(MenuTrackerLoop, 0)
        try g_MnuMain.Destroy()
    }

    g_MainRows := []
    g_HoveredRowObj := ""
    g_MnuMain := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "MenuMain")
    g_MnuMain.BackColor := CLR_BG
    ApplyDarkControl(g_MnuMain)
    
    local w := 220, y := 4
    
    AddRow := (txt, cb, triggerType := "", specialStyle := "", isIndented := false, rowBg := CLR_BG) => (
        g_MnuMain.SetFont("q4 " (specialStyle ? specialStyle : "s10 w400 " TXT_BODY), UI_FONT),
        lblText := (isIndented ? "        " : "   ") txt,
        
        wMain := (triggerType != "") ? (w - 32) : (w - 4),
        ctrl := g_MnuMain.AddText("x2 y" y " w" wMain " h28 +0x200 +0x100 " BgOpt(rowBg), lblText),
        
        arr := 0,
        (triggerType != "") ? (
            arrowTxt := (triggerType == "power") ? (g_PowerExpanded ? "▼" : "▶") : (g_CustomExpanded ? "▼" : "▶"),
            g_MnuMain.SetFont("q4 s9 w400 c8A8A8A", UI_FONT),
            arr := g_MnuMain.AddText("x" (w - 32) " y" y " w28 h28 +0x200 +0x100 Right " BgOpt(rowBg), arrowTxt "  ")
        ) : "",
        
        g_MainRows.Push({ hwnd: ctrl.Hwnd, hwndArrow: (arr ? arr.Hwnd : 0), cb: cb, trigger: triggerType, baseBg: rowBg }),
        ctrl.OnEvent("Click", (ctrlObj, *) => ExecMenuRow(ctrlObj.Hwnd)),
        (arr ? arr.OnEvent("Click", (ctrlObj, *) => ExecMenuRow(ctrl.Hwnd)) : ""),
        
        y += 28
    )
    
    AddDiv := () => (g_MnuMain.AddText("x4 y" (y+4) " w" (w-8) " h1 " BgOpt(CLR_DIVIDER), ""), y += 9)

    if (isPaused)
        AddRow("Resume Prevention", ResumeActivity, "", "s11 w600 " TXT_OK, false, CLR_FOOTER)
    else
        AddRow("Pause Prevention", PauseActivity, "", "s11 w600 " TXT_WARN, false, CLR_FOOTER)
    
    AddDiv()
    AddRow("Settings...", OpenSettings)
    
    AddRow("Power Center", "", "power")
    if (g_PowerExpanded) {
        AddRow("Force Shutdown", HandleForceShutdown, "", "", true)
        AddRow("Force Restart", HandleForceRestart, "", "", true)
        
        if (g_shutdownPending) {
            AddRow("Abort!", HandleAbortShutdown, "", "s10 w400 " TXT_WARN, true)
        } else {
            AddRow("Abort!", "", "", "s10 w400 " TXT_GHOST, true)
        }
    }
    
    if (customCodeEnabled) {
        AddRow("Custom Code", "", "custom")
        if (g_CustomExpanded) {
            AddRow("Edit Custom Code", HandleEditCustomCode, "", "", true)
            AddRow("Reload Custom Code", ReloadCustomCode, "", "", true)
            AddRow("Stop Custom Code", HandleStopCustomCode, "", "", true)
        }
    }
    
    AddDiv()
    AddRow("Exit", (*) => ExitApp())
    y += 4

    if (!g_MenuIsRefreshing) {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY)
        local calcX := mX - (w / 2)
        local calcY := mY - y - 20
        if (calcX + w > A_ScreenWidth)
            calcX := A_ScreenWidth - w - 10
        if (calcY < 0)
            calcY := 10
        
        g_LockedWinX := calcX
        g_LockedBottomY := calcY + y
    }
    
    local finalY := g_LockedBottomY - y
    g_MnuMain.Show("NoActivate x" g_LockedWinX " y" finalY " w" w " h" y)
    
    g_MenuIsRefreshing := false
    SetTimer(MenuTrackerLoop, 50)
}

ExecMenuRow(hwnd) {
    global g_MainRows, g_PowerExpanded, g_CustomExpanded, g_MenuIsRefreshing
    for r in g_MainRows {
        if (r.hwnd == hwnd) {
            if (r.trigger == "power") {
                g_PowerExpanded := !g_PowerExpanded
                g_MenuIsRefreshing := true
                CreateCustomMenu()
                return
            } else if (r.trigger == "custom") {
                g_CustomExpanded := !g_CustomExpanded
                g_MenuIsRefreshing := true
                CreateCustomMenu()
                return
            }
            if (r.cb != "") {
                SetTimer(MenuTrackerLoop, 0)
                try g_MnuMain.Destroy()
                SetTimer(r.cb, -10)
            }
            return
        }
    }
}

MenuTrackerLoop() {
    global g_MnuMain, g_HoveredRowObj, g_MainRows, CLR_BG, CLR_ACC_FILL

    if (!IsObject(g_MnuMain)) {
        SetTimer(MenuTrackerLoop, 0)
        return
    }

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &mHwnd)

    if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P")) {
        if (mHwnd != g_MnuMain.Hwnd) {
            SetTimer(MenuTrackerLoop, 0)
            try g_MnuMain.Destroy()
            return
        }
    }

    local hoveredRow := ""
    if (mHwnd == g_MnuMain.Hwnd) {
        MouseGetPos(,,, &ctrlHwnd, 2)
        for r in g_MainRows {
            if (r.hwnd == ctrlHwnd || r.hwndArrow == ctrlHwnd) {
                if (r.cb != "" || r.trigger != "")
                    hoveredRow := r
                break
            }
        }
    }

    if (hoveredRow !== g_HoveredRowObj) {
        if (g_HoveredRowObj) {
            try GuiCtrlFromHwnd(g_HoveredRowObj.hwnd).Opt(BgOpt(g_HoveredRowObj.baseBg))
            if (g_HoveredRowObj.hwndArrow)
                try GuiCtrlFromHwnd(g_HoveredRowObj.hwndArrow).Opt(BgOpt(g_HoveredRowObj.baseBg))
        }
        if (hoveredRow) {
            try GuiCtrlFromHwnd(hoveredRow.hwnd).Opt(BgOpt(CLR_ACC_FILL))
            if (hoveredRow.hwndArrow)
                try GuiCtrlFromHwnd(hoveredRow.hwndArrow).Opt(BgOpt(CLR_ACC_FILL))
        }
        g_HoveredRowObj := hoveredRow
    }
}

; ===== END MODULE: ACCORDION CUSTOM TRAY MENU ===============


; ===== MODULE: STARTUP ======================================
HandleAppExit(reason, code) {
    SetPowerRequest(false)
    try DllCall("wtsapi32\WTSUnRegisterSessionNotification", "Ptr", A_ScriptHwnd)
    StopCustomCode(true)
    StopGdiplus()
}
OnExit(HandleAppExit)

; Register the Lock Screen session listener
DllCall("wtsapi32\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
OnMessage(0x02B1, WM_WTSSESSION_CHANGE)

UpdateTray(isPaused ? "paused" : "active")
A_IconHidden := false

if (!isPaused) {
    ShowCustomTooltip("StayAwake is running and preventing your computer from sleeping.", "active")
    StartIntelligentTimers()
} else {
    ShowCustomTooltip("StayAwake started in disabled mode.", "paused")
}
RefreshPowerState()

if (customCodeEnabled)
    LaunchCustomCode(true)
; ===== END MODULE: STARTUP ==================================


; ===== MODULE: SCHEDULE ENGINE ==============================
CheckSchedule() {
    global scheduleMode, scheduleData, isPaused, startupDefaultActive

    if (scheduleMode = "disabled")
        return

    currentTime := FormatTime(, "HH:mm")
    currentDay  := FormatTime(, "dddd")
    desiredActive := false

    if (!scheduleData.Get(currentDay "Enabled", true)) {
        desiredActive := startupDefaultActive
    } else if (scheduleData.Get("SameTime", true)) {
        desiredActive := IsTimeInRange(currentTime, scheduleData.Get("SimpleOnTime", "07:00"), scheduleData.Get("SimpleOffTime", "18:00"))
    } else {
        desiredActive := IsTimeInRange(currentTime, scheduleData.Get(currentDay "On", "07:00"), scheduleData.Get(currentDay "Off", "18:00"))
    }

    if (desiredActive && isPaused) {
        isPaused := false
        StartIntelligentTimers()
        RefreshPowerState()
        UpdateTray("active")
    } else if (!desiredActive && !isPaused) {
        isPaused := true
        StopIntelligentTimers()
        RefreshPowerState()
        UpdateTray("paused")
    }
}
SetTimer(CheckSchedule, 60000)
CheckSchedule()
; ===== END MODULE: SCHEDULE ENGINE ==========================