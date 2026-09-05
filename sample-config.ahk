; ==============================================================================
;  User Configuration for AltTab-Classic
; ==============================================================================

; ------------------------------------------------------------------------------
;  Tray Icon & Tooltip Settings
; ------------------------------------------------------------------------------
; Icon source:
;   "path\icon.ico"       : External icon file
;   "path\resource,index" : Icon resource using a zero-based index
; ------------------------------------------------------------------------------
trayIconSpec := A_WinDir . "\System32\imageres.dll,297"
trayIconTip  := "[AHK] AltTab Classic"

; ------------------------------------------------------------------------------
;  1. GUI Layout & Appearance
; ------------------------------------------------------------------------------

; [Grid Layout]
iconsPerRow          := 7        ; Maximum icons per row (Default: 7, Windows XP style)
iconSize             := 32       ; Icon display size in px (32 is recommended)
spacing              := 12       ; Space between icons in px
padX                 := 12       ; Horizontal margin inside the window in px
padY                 := 16       ; Vertical margin inside the window in px

; [Color Palette] (RRGGBB format or standard color names)
panelColor           := "DEDEDE" ; Background color of the switcher panel
titleColor           := "Black"  ; Window title text color ("Black", "White", etc.)
highlightColor       := "004DFF" ; Selection border highlight color

; [Selection Box Decoration]
highlightGap         := 4        ; Gap between icon and selection border in px
highlightThickness   := 2        ; Thickness of selection border in px

; [Title Position]
titleBelowRows       := true     ; true = Title below icons / false = Title above icons

; ------------------------------------------------------------------------------
;  2. Custom Icon Mapping
; ------------------------------------------------------------------------------
; Assign custom icons to matching windows.
;
; Icon sources:
;   "path\icon.ico"           : External icon file
;   "path\resource,index"     : Icon resource using a zero-based index
;
; Matching syntax (checked in the following order):
;   "ClassName: WindowTitle" : Exact class + title match
;   "#TITLE:WindowTitle"     : Exact title match
;   "#CLASS:ClassName"       : Class name match
;   "#PROC:ProcessName"      : Process exe match
; ------------------------------------------------------------------------------
customIcons := Map(
    ; External icon file
    ;"ApplicationFrameWindow: Calculator", A_ScriptDir . "\icons\Calculator.ico",
    ;"#PROC:notepad.exe", A_ScriptDir . "\icons\Notepad.ico",

    ; Default icon for UWP apps
    ;"#CLASS:ApplicationFrameWindow", A_WinDir . "\System32\imageres.dll,11"
)

; ------------------------------------------------------------------------------
;  3. Window Exclusion Rules
; ------------------------------------------------------------------------------
; Exclude specific windows from the Alt+Tab switcher.
; Any omitted property acts as a wildcard (matches anything).
;
; Properties:
;   - Exe   : Exact match for process executable name (case-insensitive)
;   - Class : Exact match for window class name (case-insensitive)
;   - Title : Substring match for window title (case-insensitive)
;
; All specified properties within a rule must match.
; A window is excluded if any rule matches.
; ------------------------------------------------------------------------------
excludedRules := [
    ; [Pattern 1] Exe + Class (Recommended for mode-specific sub-screens)
    ; {Exe: "i_view64.exe", Class: "FullScreenClass"},  ; IrfanView fullscreen

    ; [Pattern 2] Exe + Substring Title (e.g. Exclude private browsing windows)
    ; {Exe: "msedge.exe", Title: "InPrivate"},

    ; [Pattern 3] Class Only (Matches any window with this class)
    ; {Class: "Shell_TrayWnd"},

    ; [Pattern 4] Title Only (Matches any window containing this title)
    ; {Title: "Sticky Notes"},

    ; [Pattern 5] Exe Only (Matches all windows belonging to this process)
    ; {Exe: "ApplicationFrameHost.exe"}

    ; Applications that you prefer to hide from the switcher
    ; {Exe: "firefox.exe", Class: "MozillaDialogClass"}, ; Firefox Picture-in-Picture
]
