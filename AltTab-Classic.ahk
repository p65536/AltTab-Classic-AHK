#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#UseHook

; Boost process priority to ensure responsive Alt+Tab switching
ProcessSetPriority("AboveNormal")

; Prevent menu bar (access key) activation when releasing Alt alone
A_MenuMaskKey := "vkE8"

; ==============================================================================
;  Default Configuration Fallback
; ==============================================================================
; These defaults ensure full standalone functionality even if config.ahk is missing.
defaultTrayIconSpec  := A_WinDir . "\System32\imageres.dll,297"
trayIconSpec         := defaultTrayIconSpec
trayIconTip          := "[AHK] AltTab Classic"
iconsPerRow          := 7
iconSize             := 32
spacing              := 12
padX                 := 12
padY                 := 16
panelColor           := "DEDEDE"
titleColor           := "Black"
highlightColor       := "004DFF"
highlightGap         := 4
highlightThickness   := 2
titleBelowRows       := true

; Default custom icons (UWP fallback)
customIcons := Map()

; Default window exclusion rules
excludedRules := []

; Load user customizations if config.ahk exists
#Include "*i config.ahk"

; ------------------------------------------------------------------------------
;  Derived Calculations & Initialization
; ------------------------------------------------------------------------------
; Convert CustomIcons to a case-insensitive Map safely
rawCustomIcons := customIcons
customIcons := Map()
customIcons.CaseSense := "Off"
for key, val in rawCustomIcons
    customIcons[key] := val

; Calculate panel dimensions based on the configured grid layout
highlightSize := iconSize + 2 * (highlightGap + highlightThickness)
maxPanelWidth := (iconsPerRow * iconSize) + ((iconsPerRow - 1) * spacing) + (2 * padX)
maxTextWidth  := maxPanelWidth - (2 * padX)

; Tray icon & tooltip initialization
ParseIconSpec(trayIconSpec, &trayIconPath, &trayIconIndex)

; Fall back to the built-in default if the configured icon source is invalid
if !FileExist(trayIconPath)
    ParseIconSpec(defaultTrayIconSpec, &trayIconPath, &trayIconIndex)

if FileExist(trayIconPath) {
    trayIconNumber := (trayIconIndex = "")
        ? 1
        : (trayIconIndex >= 0 ? trayIconIndex + 1 : trayIconIndex)
    TraySetIcon(trayIconPath, trayIconNumber, 1)
}           

A_IconTip := trayIconTip

; ------------------------------------------------------------------------------
;  Internal State Variables
; ------------------------------------------------------------------------------
guiActive := false
persistentAltTab := false
targetWindows := []
selectedIndex := 0
altTabGui := unset
glowBorder := unset, maskBorder := unset, titleLabel := unset

; ------------------------------------------------------------------------------
;  Hotkeys
; ------------------------------------------------------------------------------
~Alt::return

!Tab::
{
    global selectedIndex, persistentAltTab
    persistentAltTab := false

    if (!guiActive) {
        BuildAltTabGui()
        if (targetWindows.Length = 0)
            return
        selectedIndex := (targetWindows.Length > 1) ? 2 : 1
    } else {
        selectedIndex++
        if (selectedIndex > targetWindows.Length)
            selectedIndex := 1
    }

    UpdateHighlight()

    ; Compensate if Alt Up was already processed during GUI construction
    if (guiActive && !GetKeyState("Alt", "P"))
        FinishAltTab(targetWindows[selectedIndex].hwnd)
}

+!Tab::
{
    global selectedIndex, persistentAltTab
    persistentAltTab := false

    if (!guiActive) {
        BuildAltTabGui()
        if (targetWindows.Length = 0)
            return
        selectedIndex := targetWindows.Length
    } else {
        selectedIndex--
        if (selectedIndex < 1)
            selectedIndex := targetWindows.Length
    }

    UpdateHighlight()

    ; Compensate if Alt Up was already processed during GUI construction
    if (guiActive && !GetKeyState("Alt", "P"))
        FinishAltTab(targetWindows[selectedIndex].hwnd)
}

^!Tab::
{
    global selectedIndex, persistentAltTab
    persistentAltTab := true

    if (!guiActive) {
        BuildAltTabGui()
        if (targetWindows.Length = 0)
            return
        selectedIndex := (targetWindows.Length > 1) ? 2 : 1
    } else {
        selectedIndex++
        if (selectedIndex > targetWindows.Length)
            selectedIndex := 1
    }

    UpdateHighlight()
}

~Alt Up::
{
    if (persistentAltTab)
        return

    ; selectedIndex may still be 0 during GUI construction.
    ; In that case, rely on the caller's physical Alt key state check.
    if (guiActive && selectedIndex >= 1 && selectedIndex <= targetWindows.Length)
        FinishAltTab(targetWindows[selectedIndex].hwnd)
}

#HotIf guiActive
Tab::
{
    global selectedIndex
    selectedIndex++
    if (selectedIndex > targetWindows.Length)
        selectedIndex := 1
    UpdateHighlight()
}

+Tab::
{
    global selectedIndex
    selectedIndex--
    if (selectedIndex < 1)
        selectedIndex := targetWindows.Length
    UpdateHighlight()
}

*Left::NavigateIcons("Left")
*Right::NavigateIcons("Right")
*Up::NavigateIcons("Up")
*Down::NavigateIcons("Down")

*Home::
{
    global selectedIndex
    selectedIndex := 1
    UpdateHighlight()
}

*End::
{
    global selectedIndex
    selectedIndex := targetWindows.Length
    UpdateHighlight()
}

*Space::
*Enter::
{
    if (selectedIndex >= 1 && selectedIndex <= targetWindows.Length)
        FinishAltTab(targetWindows[selectedIndex].hwnd)
}

*Esc::
{
    FinishAltTab(0)
}
#HotIf

; ------------------------------------------------------------------------------
;  GUI Construction & Rendering
; ------------------------------------------------------------------------------
BuildAltTabGui() {
    global targetWindows, altTabGui, glowBorder, maskBorder, titleLabel, guiActive

    targetWindows := []

    ; Safely save and restore DetectHiddenWindows state
    oldDetectHidden := A_DetectHiddenWindows
    try {
        DetectHiddenWindows(false)
        winList := WinGetList()
    } finally {
        DetectHiddenWindows(oldDetectHidden)
    }

    for hWnd in winList {
        if !IsAltTabWindow(hWnd)
            continue

        try {
            windowTitle := WinGetTitle(hWnd)

            ; If the window has no title (e.g. IrfanView fullscreen), inherit title from owner
            if (windowTitle == "") {
                GW_OWNER := 4
                hOwner := DllCall("user32\GetWindow", "Ptr", hWnd, "UInt", GW_OWNER, "Ptr")
                if (hOwner && WinExist(hOwner))
                    windowTitle := WinGetTitle(hOwner)
            }

            if (windowTitle == "")
                continue

            windowClass := WinGetClass(hWnd)
            processName := WinGetProcessName(hWnd)
        } catch {
            continue
        }

        ; Check exclusion rules
        skip := false
        for rule in excludedRules {
            matchExe   := !rule.HasOwnProp("Exe")   || (rule.Exe = processName)
            matchClass := !rule.HasOwnProp("Class") || (rule.Class = windowClass)
            matchTitle := !rule.HasOwnProp("Title") || InStr(windowTitle, rule.Title)
            if (matchExe && matchClass && matchTitle) {
                skip := true
                break
            }
        }
        if skip
            continue

        targetWindows.Push({
            hwnd:    hWnd,
            title:   windowTitle,
            class:   windowClass,
            process: processName
        })
    }

    if (targetWindows.Length = 0)
        return

    if IsSet(altTabGui) && altTabGui is Gui
        altTabGui.Destroy()

    altTabGui := Gui("+AlwaysOnTop -Caption +Owner +ToolWindow +Border", "Alt-Tab")
    altTabGui.BackColor := panelColor
    altTabGui.MarginX := 0
    altTabGui.MarginY := 0

    glowBorder := altTabGui.Add("Progress", "x0 y0 w" highlightSize " h" highlightSize " -Smooth Background" highlightColor " -Border Hidden Disabled")
    innerSize := iconSize + 2 * highlightGap
    maskBorder := altTabGui.Add("Progress", "x0 y0 w" innerSize " h" innerSize " -Smooth Background" panelColor " -Border Hidden Disabled")

    ; Adjust icon starting Y-coordinate based on title position
    startY := titleBelowRows ? padY : (padY + 30 + spacing)
    x := padX, y := startY, rowHeight := iconSize + spacing

    for idx, win in targetWindows {
        win.x := x
        win.y := y

        opt := "x" x " y" y " w" iconSize " h" iconSize
        iconSpec := GetCustomIconSpec(win.class, win.title, win.process)

        if (iconSpec != "") {
            ParseIconSpec(iconSpec, &iconPath, &iconIndex)
        }

        if (iconSpec != "" && FileExist(iconPath)) {
            iconOpt := opt
            if (iconIndex != "") {
                iconNum := (iconIndex >= 0) ? iconIndex + 1 : iconIndex
                iconOpt .= " Icon" iconNum
            }
            picCtrl := altTabGui.Add("Picture", iconOpt, iconPath)
        } else {
            hIcon := GetWindowIcon(win.hwnd, 1)
            picCtrl := altTabGui.Add("Picture", opt, hIcon ? "HICON:*" hIcon : unset)
        }

        picCtrl.OnEvent("Click", OnIconClick.Bind(idx))
        win.ctrlHwnd := picCtrl.Hwnd

        x += iconSize + spacing
        if (x + iconSize + padX > maxPanelWidth) {
            x := padX
            y += rowHeight
        }
    }

    rows := Ceil(targetWindows.Length / iconsPerRow)
    rowsAreaHeight := rows * (iconSize + spacing) - spacing
    altTabGui.SetFont("c" titleColor)

    if (titleBelowRows) {
        titleY := padY + rowsAreaHeight + ((3 * padY) // 4)
        titleLabel := altTabGui.Add("Text", "x" padX " y" titleY " w" maxTextWidth " h30 +Border +0x80 +0x200 +0x4000 +0x1000", "")
        totalHeight := Integer(titleY + 40)
    } else {
        titleLabel := altTabGui.Add("Text", "x" padX " y" padY " w" maxTextWidth " h30 +Border +0x80 +0x200 +0x4000 +0x1000", "")
        totalHeight := Integer(padY + 30 + spacing + rowsAreaHeight + padY)
    }

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)

    ; Center within work area excluding taskbar (Fallback to primary monitor)
    primaryMon := MonitorGetPrimary()
    MonitorGetWorkArea(primaryMon, &monLeft, &monTop, &monRight, &monBottom)

    screenX := monLeft + ((monRight - monLeft - maxPanelWidth) // 2)
    screenY := monTop + ((monBottom - monTop - totalHeight) // 2)

    monCount := MonitorGetCount()
    Loop monCount {
        MonitorGet(A_Index, &fullLeft, &fullTop, &fullRight, &fullBottom)

        if (mouseX >= fullLeft && mouseX < fullRight
         && mouseY >= fullTop && mouseY < fullBottom) {

            MonitorGetWorkArea(A_Index, &monLeft, &monTop, &monRight, &monBottom)
            screenX := monLeft + ((monRight - monLeft - maxPanelWidth) // 2)
            screenY := monTop + ((monBottom - monTop - totalHeight) // 2)
            break
        }
    }

    altTabGui.Show("x" screenX " y" screenY " w" maxPanelWidth " h" totalHeight)
    guiActive := true
    SetTimer(CheckHover, 50)
}

; ------------------------------------------------------------------------------
;  Highlight & Title Updates
; ------------------------------------------------------------------------------
UpdateHighlight() {
    if (selectedIndex < 1 || selectedIndex > targetWindows.Length)
        return

    win := targetWindows[selectedIndex]

    outerX := win.x - (highlightGap + highlightThickness)
    outerY := win.y - (highlightGap + highlightThickness)
    glowBorder.Move(outerX, outerY, highlightSize, highlightSize)
    glowBorder.Visible := true
    glowBorder.Redraw()

    innerX := win.x - highlightGap
    innerY := win.y - highlightGap
    innerSize := iconSize + 2 * highlightGap
    maskBorder.Move(innerX, innerY, innerSize, innerSize)
    maskBorder.Visible := true
    maskBorder.Redraw()

    ; Add left padding immediately before displaying title text
    titleLabel.Value := " " . win.title
}

; ------------------------------------------------------------------------------
;  Mouse Interactions
; ------------------------------------------------------------------------------
CheckHover() {
    global selectedIndex
    if (!guiActive || !IsSet(altTabGui))
        return

    MouseGetPos(,, &winHwnd, &ctrlHwnd, 2)
    if (winHwnd != altTabGui.Hwnd || !ctrlHwnd)
        return

    for idx, win in targetWindows {
        if (ctrlHwnd = win.ctrlHwnd) {
            if (idx != selectedIndex) {
                selectedIndex := idx
                UpdateHighlight()
            }
            break
        }
    }
}

OnIconClick(idx, *) {
    global selectedIndex
    if (idx >= 1 && idx <= targetWindows.Length) {
        selectedIndex := idx
        FinishAltTab(targetWindows[selectedIndex].hwnd)
    }
}

; ------------------------------------------------------------------------------
;  Navigation Logic
; ------------------------------------------------------------------------------
NavigateIcons(direction) {
    global selectedIndex
    count := targetWindows.Length
    if (count = 0)
        return

    if (direction = "Left") {
        selectedIndex--
        if (selectedIndex < 1)
            selectedIndex := count
    } else if (direction = "Right") {
        selectedIndex++
        if (selectedIndex > count)
            selectedIndex := 1
    } else if (direction = "Up") {
        selectedIndex -= iconsPerRow
        if (selectedIndex < 1)
            selectedIndex := selectedIndex + iconsPerRow * Ceil(count / iconsPerRow)
        if (selectedIndex > count)
            selectedIndex := count
    } else if (direction = "Down") {
        if (selectedIndex + iconsPerRow <= count) {
            selectedIndex += iconsPerRow
        } else {
            ; If there is no item directly below, move to the last item.
            ; If already on the last row, wrap to the same column in the first row.
            rows := Ceil(count / iconsPerRow)
            currentRow := Ceil(selectedIndex / iconsPerRow)

            if (currentRow < rows)
                selectedIndex := count
            else
                selectedIndex -= iconsPerRow * (rows - 1)
        }
    }

    UpdateHighlight()
}

; ------------------------------------------------------------------------------
;  Cleanup & Window Activation
; ------------------------------------------------------------------------------
; Do not force-release physical Alt/Tab to prevent failure when reopening GUI with Alt held
ForceModifierReset() {
    if !GetKeyState("Alt", "P")
        SendInput("{Blind}{Alt Up}")

    if !GetKeyState("Tab", "P")
        SendInput("{Blind}{Tab Up}")
}

FinishAltTab(hWnd) {
    global guiActive, persistentAltTab
    SetTimer(CheckHover, 0)
    if IsSet(altTabGui) && altTabGui is Gui
        altTabGui.Hide()
    guiActive := false
    persistentAltTab := false
    ForceModifierReset()

    if (hWnd && WinExist(hWnd)) {
        ; If the window owns an active modal popup (e.g. Save As), activate the popup instead
        targetHwnd := DllCall("user32\GetLastActivePopup", "Ptr", hWnd, "Ptr")
        if (!targetHwnd || !DllCall("user32\IsWindowVisible", "Ptr", targetHwnd) || !DllCall("user32\IsWindowEnabled", "Ptr", targetHwnd))
            targetHwnd := hWnd

        try WinActivate(targetHwnd)
    }
}

; ------------------------------------------------------------------------------
;  Icon Retrieval Helpers (with timeout protection & owner icon inheritance)
; ------------------------------------------------------------------------------
GetWindowIcon(hWnd, preferBigIcon := 0) {
    if !hWnd || !WinExist(hWnd)
        return 0

    WM_GETICON    := 0x7F
    GCLP_HICON    := -14
    GCLP_HICONSM  := -34
    timeoutMs     := 50
    stopWMGetIcon := false

    GetWMIcon(wParam) {
        if stopWMGetIcon
            return 0

        try {
            return SendMessage(WM_GETICON, wParam, 0,, hWnd,,,, timeoutMs)
        } catch {
            ; Abort remaining WM_GETICON attempts immediately if failed or timed out
            stopWMGetIcon := true
            return 0
        }
    }

    ; 1. Query window instance icons and class icons
    hIcon := 0
    if preferBigIcon {
        hIcon := GetWMIcon(1)
              || GetWMIcon(0)
              || GetWMIcon(2)
              || DllCall("user32\GetClassLongPtr", "Ptr", hWnd, "Int", GCLP_HICON, "UPtr")
              || DllCall("user32\GetClassLongPtr", "Ptr", hWnd, "Int", GCLP_HICONSM, "UPtr")
    } else {
        hIcon := GetWMIcon(0)
              || GetWMIcon(2)
              || GetWMIcon(1)
              || DllCall("user32\GetClassLongPtr", "Ptr", hWnd, "Int", GCLP_HICONSM, "UPtr")
              || DllCall("user32\GetClassLongPtr", "Ptr", hWnd, "Int", GCLP_HICON, "UPtr")
    }

    ; 2. If no icon found, inherit from the owner window (e.g. Save As dialogs)
    if !hIcon {
        GW_OWNER := 4
        hOwner := DllCall("user32\GetWindow", "Ptr", hWnd, "UInt", GW_OWNER, "Ptr")
        if (hOwner && WinExist(hOwner))
            hIcon := GetWindowIcon(hOwner, preferBigIcon)
    }

    ; 3. Final fallback: standard generic application icon (IDI_APPLICATION: 32512)
    if !hIcon
        hIcon := DllCall("user32\LoadIcon", "Ptr", 0, "Ptr", 32512, "Ptr")

    return hIcon
}

; ------------------------------------------------------------------------------
;  Alt+Tab Target Window Verification
; ------------------------------------------------------------------------------
IsAltTabWindow(hWnd) {
    if !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr", hWnd, "UInt", 1, "Ptr"))
        return false

    try {
        style := WinGetStyle(hWnd)
        exStyle := WinGetExStyle(hWnd)
    } catch {
        return false
    }

    WS_VISIBLE          := 0x10000000
    WS_CHILD            := 0x40000000
    WS_EX_TOOLWINDOW    := 0x00000080
    WS_EX_APPWINDOW     := 0x00040000
    WS_EX_NOACTIVATE    := 0x08000000

    ; Exclude invisible and child windows
    if !(style & WS_VISIBLE) || (style & WS_CHILD)
        return false

    ; Exclude tool windows unless explicitly marked with WS_EX_APPWINDOW
    if (exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
        return false

    ; Exclude passive windows (KeyTips, on-screen overlays)
    if (exStyle & WS_EX_NOACTIVATE) && !(exStyle & WS_EX_APPWINDOW)
        return false

    ; Exclude cloaked windows (hidden UWP apps or other virtual desktops) via DWMWA_CLOAKED (0x0E)
    DWMWA_CLOAKED := 14
    cloaked := 0
    if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hWnd, "UInt", DWMWA_CLOAKED, "UInt*", &cloaked, "UInt", 4) == 0) {
        if (cloaked != 0)
            return false
    }

    ; Windows Shell Rule:
    ; A window must not be an owned/child window unless it has WS_EX_APPWINDOW.
    ; If the root owner is visible, this dependent window must be excluded.
    ; If the root owner is hidden (e.g. IrfanView fullscreen mode), admit this window as the visible proxy.
    if !(exStyle & WS_EX_APPWINDOW) {
        GA_ROOTOWNER := 3
        rootOwner := DllCall("user32\GetAncestor", "Ptr", hWnd, "UInt", GA_ROOTOWNER, "Ptr")
        if (rootOwner && rootOwner != hWnd && DllCall("user32\IsWindowVisible", "Ptr", rootOwner))
            return false
    }

    return true
}

; ------------------------------------------------------------------------------
;  Custom Icon Resolver
; ------------------------------------------------------------------------------
ParseIconSpec(iconSpec, &iconPath, &iconIndex) {
    iconPath := iconSpec
    iconIndex := ""

    if RegExMatch(iconSpec, "^(.*),(-?\d+)$", &match) {
        iconPath := match[1]
        iconIndex := Integer(match[2])
    }
}

GetCustomIconSpec(windowClass, windowTitle, processName) {
    classTitleKey := windowClass ": " windowTitle
    titleKey      := "#TITLE:" . windowTitle
    classKey      := "#CLASS:" . windowClass
    procKey       := "#PROC:"  . processName

    if customIcons.Has(classTitleKey)
        return customIcons[classTitleKey]
    if customIcons.Has(titleKey)
        return customIcons[titleKey]
    if customIcons.Has(classKey)
        return customIcons[classKey]
    if customIcons.Has(procKey)
        return customIcons[procKey]
    return ""
}
