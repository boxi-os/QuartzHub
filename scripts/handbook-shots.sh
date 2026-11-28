#!/bin/zsh
# Aufnahmen für das Handbuch (docs/plan.md, Handbuch, 3), am Demo-Projekt von
# scripts/handbook-demo.sh: jede Seite und jeder Reiter des Projektfensters, dazu einige Szenen
# (das leere Fenster „Projekte“, die Übernahme-Frage, „Neues Projekt“, die laufende Vorschau).
#
#   scripts/handbook-shots.sh [--lang de|en] [--theme light|dark] [--only <name,name>] [--out <ordner>]
#
# Ohne Angaben: beide Sprachen, hell, alles, nach <vault>/assets/screenshots/<lang>/<name>-hell.png
# (1440 px breit; dunkel: -dunkel). Danach läuft scripts/handbook-private.swift über die neuen
# Bilder; ein Fund endet mit Exit 1. Bewegt Maus und Tastatur: währenddessen nicht am Mac arbeiten.
#
# Navigiert wird sprachunabhängig: Seiten über ihre Position in der Seitenleiste (die Zeilen geben
# ihre Kennung nicht an die Bedienungshilfen weiter), Reiter über ihre Position im Segment.
set -eu
ROOT=${0:A:h:h}
APP=${QH_APP:-$ROOT/build/DerivedData/Build/Products/Debug/QuartzHub.app}
VAULT=${QH_HANDBOOK_VAULT:-$HOME/Documents/Obsidian/QuartzHub-Handbuch}
DEMO=/Users/Shared/QuartzHub-Demo
PROJECT=$DEMO/QuartzProjekte/QuartzHub-Docs
OUT=$VAULT/assets/screenshots
LANGS=(de en); THEMES=(light); ONLY=""
while [ $# -gt 0 ]; do
  case $1 in
    --lang) LANGS=($2); shift 2 ;;
    --theme) THEMES=($2); shift 2 ;;
    --only) ONLY=",$2,"; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    *) echo "unbekannt: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PROJECT" ] || { echo "Erst scripts/handbook-demo.sh" >&2; exit 1; }

# name | Zeile der Seitenleiste | Reiter (Position, leer = keiner) | s = mit laufender Vorschau,
# w = länger warten (die Seite lädt aus dem Netz oder liest viel)
# Zeilen: 1 Übersicht, 3 Konfiguration, 4 Plugins, 6 Layout, 7 Stile, 8 Vorlagen, 10 Vorschau & Build,
# 11 Git-Sync, 12 Dokumente, 13 Veröffentlichen, 15 Updates, 16 Snapshots (2, 5, 9, 14: Gruppen).
PAGES=(
  "uebersicht|1|"
  "konfiguration|3|1" "konfiguration-uebersetzungen|3|2"
  "plugins|4|1" "plugins-navigationen|4|2|s" "plugins-zusaetzliche-inhalte|4|3|s"
  "plugins-mehrsprachigkeit|4|4|s" "plugins-formulare|4|5|s" "plugins-formulare-formular|4|5|s"
  "plugins-marktplatz|4|6"
  "layout-uebersicht|6|1" "layout-komponenten|6|2" "layout-frames|6|3" "layout-frames-zeilen|6|3"
  "stile-basis|7|1" "stile-themes|7|2|w" "stile-themes-katalog|7|2" "stile-variablen|7|3"
  "stile-variablen-vorlage|7|3" "stile-variablen-plugins|7|3" "stile-css|7|4"
  "vorlagen|8|1|w" "vorlagen-erstellen|8|2|w"
  "vorschau-und-build|10|" "git-sync|11|" "dokumente|12|" "veroeffentlichen|13|"
  "updates|15|" "snapshots|16|"
)
SCENES=(projekte-leer projekte projekte-fehlt neues-projekt duplizieren
  einstellungen-allgemein einstellungen-zugaenge einstellungen-laufzeit einstellungen-daten vorschau-und-build-laeuft)

wanted() { [ -z "$ONLY" ] || [[ $ONLY == *",$1,"* ]]; }

winid() {
  # The largest of QuartzHub's windows: the project window when one is open, else Projects.
  # With "front": the frontmost one (the settings).
  swift - "${1:-largest}" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let own = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "QuartzHub" && ($0[kCGWindowLayer as String] as? Int) == 0 }
let area = { (w: [String: Any]) -> Double in let b = w[kCGWindowBounds as String] as! [String: Double]; return b["Width"]! * b["Height"]! }
let pick = CommandLine.arguments.last == "front" ? own.first : own.max(by: { area($0) < area($1) })
if let w = pick { print(w[kCGWindowNumber as String]!) }
SWIFT
}

ax() { osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set frontmost to true
 $1
end tell" >/dev/null; }
key() { ax "keystroke \"$1\" using command down"; }
escape() { ax "key code 53"; }

# The project window: any but the Projects window, whose title is "Projekte" or "Projects".
project_window='(first window whose name is not "Projekte" and name is not "Projects")'

page() {
  ax "set selected of row $1 of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of $project_window to true"
}

tab() {
  # The tabs' segmented control is the window's only radio group, a few groups deep.
  ax "set w to $project_window
 set els to entire contents of w
 repeat with e in els
  try
   if role of e is \"AXRadioGroup\" then
    click radio button $1 of e
    exit repeat
   end if
  end try
 end repeat"
}

# A row of the Projects window's list (the window's only outline). The contents go into a variable
# first: an element straight out of `entire contents` does not take a property change.
project_row() {
  ax "set els to entire contents of window 1
 repeat with e in els
  try
   if role of e is \"AXOutline\" then
    set selected of row $1 of e to true
    exit repeat
   end if
  end try
 end repeat"
}

# A button by its accessibility identifier, wherever it sits in the front window.
press() {
  ax "set els to entire contents of window 1
 repeat with e in els
  try
   if role of e is \"AXButton\" and value of attribute \"AXIdentifier\" of e is \"$1\" then
    click e
    exit repeat
   end if
  end try
 end repeat"
}

# A button of the project window by its label, German or English (toolbar buttons have no
# identifier the accessibility tree passes on).
press_label() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXButton\" and (description of e is \"$1\" or description of e is \"$2\" or name of e is \"$1\" or name of e is \"$2\") then
    click e
    exit repeat
   end if
  end try
 end repeat"
}

# Selects row n of the project window's list with the given accessibility identifier (row 1 can be
# a section header).
list_row() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXOutline\" and value of attribute \"AXIdentifier\" of e is \"$1\" then
    set selected of row $2 of e to true
    exit repeat
   end if
  end try
 end repeat"
}

# Clicks the n-th disclosure triangle of the inspector (a Fold's header): the right quarter of the
# project window, since the site in a preview has triangles of its own.
disclose() {
  ax "set n to 0
 set w to $project_window
 set edge to (item 1 of (position of w as list)) + (item 1 of (size of w as list)) * 3 / 4
 set els to entire contents of w
 repeat with e in els
  try
   if role of e is \"AXDisclosureTriangle\" and (item 1 of (position of e as list)) > edge then
    set n to n + 1
    if n is $1 then
     click e
     exit repeat
    end if
   end if
  end try
 end repeat"
}

# Clicks a text of the project window that reads the German or the English word, with the mouse
# at its left edge: a Fold's label and a list row take a click, not an accessibility action. Only
# what the list has laid out is found (rows out of view do not exist yet). The click is a real
# mouse event: System Events' `click at` reached the element but left a Fold shut (2026-11-22).
# A third argument moves the click that many points down (a row under a heading that has no text
# of its own for the accessibility tree).
click_text() {
  local at=$(osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set frontmost to true
 set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXStaticText\" and ((value of e as text) is \"$1\" or (value of e as text) is \"$2\") then
    set p to position of e
    set s to size of e
    return ((item 1 of p) + 4 as integer as text) & \" \" & ((item 2 of p) + (item 2 of s) / 2 + ${3:-0} as integer as text)
   end if
  end try
 end repeat
 return \"\"
end tell")
  [ -n "$at" ] || { echo "nicht gefunden: $1" >&2; return 0; }
  mouse click ${=at}
}
# Clicks into the text field whose placeholder starts with the German or the English text, then
# types: SwiftUI took a value set through the accessibility tree without updating its binding.
type_by_placeholder() {
  local at=$(osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set frontmost to true
 set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXTextField\" then
    set ph to value of attribute \"AXPlaceholderValue\" of e
    if ph starts with \"$1\" or ph starts with \"$2\" then
     set p to position of e
     set s to size of e
     return ((item 1 of p) + 20 as integer as text) & \" \" & ((item 2 of p) + (item 2 of s) / 2 as integer as text)
    end if
   end if
  end try
 end repeat
 return \"\"
end tell")
  [ -n "$at" ] || { echo "nicht gefunden: $1" >&2; return 0; }
  mouse click ${=at}; sleep 0.5
  ax "keystroke \"$3\""
}
# Scrolls the project window's middle column down by the given points (a lot reaches the end).
scroll_down() {
  local at=$(osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set p to position of $project_window
 return ((item 1 of p) + 500 as integer as text) & \" \" & ((item 2 of p) + 450 as integer as text)
end tell")
  mouse scroll ${=at} $1
}
# Real mouse events: `mouse click x y`, `mouse scroll x y points`.
mouse() {
  swift - "$@" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(100_000)
if a[1] == "click" {
  for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(80_000)
  }
} else {
  var left = Int32(a[4])!
  while left > 0 {
    let step = min(left, 50)
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)!.post(tap: .cghidEventTap)
    left -= step
    usleep(20_000)
  }
}
SWIFT
}
# For a list too long for `entire contents` (Community-Themes, over a thousand rows; System Events
# took more than ten minutes): the accessibility tree walked directly, without going into a list's
# rows. `axdo row <list id> <n>` selects row n (section headings count), `axdo press <id>` presses,
# `axdo center <id>` prints where to click into a field.
axdo() {
  swift - "$@" <<'SWIFT'
import AppKit
import ApplicationServices
let a = CommandLine.arguments
guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.boxios.quartzhub").first?.processIdentifier else { exit(1) }
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func find(_ e: AXUIElement, _ id: String) -> AXUIElement? {
  if attr(e, "AXIdentifier") as? String == id { return e }
  let kids = attr(e, "AXChildren") as? [AXUIElement] ?? []
  if kids.count > 100 { return nil }
  for k in kids { if let f = find(k, id) { return f } }
  return nil
}
let windows = attr(AXUIElementCreateApplication(pid), "AXWindows") as? [AXUIElement] ?? []
guard let w = windows.first(where: { !["Projekte", "Projects"].contains(attr($0, "AXTitle") as? String ?? "") }),
      let e = find(w, a[2]) else { FileHandle.standardError.write("nicht gefunden: \(a[2])\n".data(using: .utf8)!); exit(0) }
if a[1] == "row", let rows = attr(e, "AXRows") as? [AXUIElement], let n = Int(a[3]), n <= rows.count {
  AXUIElementSetAttributeValue(rows[n - 1], "AXSelected" as CFString, kCFBooleanTrue)
} else if a[1] == "press" {
  AXUIElementPerformAction(e, "AXPress" as CFString)
} else if a[1] == "center", let p = attr(e, "AXPosition"), let z = attr(e, "AXSize") {
  var o = CGPoint.zero, d = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &o)
  AXValueGetValue(z as! AXValue, .cgSize, &d)
  print(Int(o.x + 20), Int(o.y + d.height / 2))
}
SWIFT
}
# Sets the text field with the given accessibility identifier.
set_field() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXTextField\" and value of attribute \"AXIdentifier\" of e is \"$1\" then
    set focused of e to true
    set value of e to \"$2\"
    exit repeat
   end if
  end try
 end repeat"
}
# The page a preview shows (the field with the identifier preview.page), then Return.
preview_page() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXTextField\" and value of attribute \"AXIdentifier\" of e is \"preview.page\" then
    set focused of e to true
    set value of e to \"$1\"
    exit repeat
   end if
  end try
 end repeat
 delay 0.5
 key code 36"
}

# "x y w h" of the element of the project window with the given accessibility identifier.
element_frame() {
  osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set els to entire contents of $project_window
 repeat with e in els
  try
   if value of attribute \"AXIdentifier\" of e is \"$1\" then
    set p to position of e
    set z to size of e
    return ((item 1 of p) as text) & \" \" & ((item 2 of p) as text) & \" \" & ((item 1 of z) as text) & \" \" & ((item 2 of z) as text)
   end if
  end try
 end repeat
end tell"
}

# Picks an item of the pop-up button with the given identifier, by its title.
pick() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXPopUpButton\" and value of attribute \"AXIdentifier\" of e is \"$1\" then
    click e
    delay 0.5
    click menu item \"$2\" of menu 1 of e
    exit repeat
   end if
  end try
 end repeat"
}

# Clicks the n-th radio button of the n-th radio group of the project window (1: the page's tabs).
radio() {
  ax "set n to 0
 set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXRadioGroup\" then
    set n to n + 1
    if n is $1 then
     click radio button $2 of e
     exit repeat
    end if
   end if
  end try
 end repeat"
}

# A drag with the real mouse, held at its end for <hold> seconds, then moved to <x3 y3> and let go
# there: drag_hold x1 y1 x2 y2 hold x3 y3. Runs in the background; a drag that ends where nothing
# takes it changes nothing.
drag_hold() {
  swift - "$@" <<'SWIFT' &
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
func ev(_ t: CGEventType, _ x: Double, _ y: Double) {
  CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!.post(tap: .cghidEventTap)
}
func glide(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
  for i in 1...30 { let t = Double(i) / 30; ev(.leftMouseDragged, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t); usleep(25000) }
}
ev(.mouseMoved, a[0], a[1]); usleep(150000)
ev(.leftMouseDown, a[0], a[1]); usleep(200000)
glide(a[0], a[1], a[2], a[3])
let until = Date().addingTimeInterval(a[4])
while Date() < until { ev(.leftMouseDragged, a[2], a[3]); usleep(100000) }
glide(a[2], a[3], a[5], a[6])
usleep(200000)
ev(.leftMouseUp, a[5], a[6])
SWIFT
}

# The first button of the project window whose accessibility value is the German or English word.
press_value() {
  ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXButton\" and ((value of e as text) is \"$1\" or (value of e as text) is \"$2\") then
    click e
    exit repeat
   end if
  end try
 end repeat"
}

# Types into the n-th text field of the front window (sheets included).
type_into() {
  ax "set n to 0
 set els to entire contents of window 1
 repeat with e in els
  try
   if role of e is \"AXTextField\" then
    set n to n + 1
    if n is $1 then
     set focused of e to true
     exit repeat
    end if
   end if
  end try
 end repeat
 delay 0.5
 keystroke \"$2\""
}

# launch <lang> <profile> <windows to wait for> [more arguments]
launch() {
  local lang=$1 profile=$2 windows=$3; shift 3
  pkill -x QuartzHub 2>/dev/null || true
  sleep 2
  open -n "$APP" --args -QHLanguage "$lang" -ApplePersistenceIgnoreState YES -QHProfileDir "$profile" \
    -QHMemorySecrets YES -QHWindowSize 1440x900 "$@"
  # Adding the project runs node once (its frames' paths); its window comes after that.
  for i in {1..40}; do
    sleep 1
    osascript -e 'tell application "System Events" to tell process "QuartzHub" to count windows' 2>/dev/null | grep -q "^[$windows-9]" && break
  done
  sleep 3
}

# The project window asks GitHub for updates (git ls-remote, read only), so Updates and the
# overview show a real answer rather than "Nicht prüfbar"; the other windows stay offline.
with_project() { launch $1 "$DEMO/profile-$2" 2 -QHOpenProject "$PROJECT"; ax "perform action \"AXRaise\" of $project_window"; }
offline=(-QHNoUpdateCheck YES)

# An empty profile in the given theme, made again for every use: the question at the first start
# would otherwise not come back.
empty_profile() {
  local p="$DEMO/profile-empty-$1"
  rm -rf "$p"; mkdir -p "$p"
  printf '{\n  "theme": "%s"\n}\n' "$1" > "$p/settings.json"
  echo "$p"
}

new=()
shoot() {
  local file="$OUT/$lang/$1-$suffix.png"
  screencapture -o -x -l "$(winid ${2:-})" "$file"
  # sRGB: the display's own profile would carry its model name into the handbook.
  # At most 1440 px wide; a smaller window (the settings) is not enlarged.
  local width=$(sips -g pixelWidth "$file" | awk '/pixelWidth/ { print $2 }')
  [ "$width" -gt 1440 ] && sips --resampleWidth 1440 "$file" >/dev/null
  sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" "$file" >/dev/null
  new+=("$file")
  echo "$file"
}

for lang in $LANGS; do
  for theme in $THEMES; do
    suffix=$([ $theme = light ] && echo hell || echo dunkel)
    mkdir -p "$OUT/$lang"

    todo=0; for line in $PAGES; do wanted ${line%%|*} && todo=1; done
    if [ $todo = 1 ]; then
      with_project $lang $theme
      # One build first, so the overview and Preview & build show its result.
      key b; sleep 40
      serving=0
      for line in $PAGES; do
        name=${line%%|*}; rest=${line#*|}; row=${rest%%|*}; t=${rest#*|}
        flag=""; [[ $t == *"|"* ]] && { flag=${t#*|}; t=${t%%|*}; }
        wanted $name || continue
        # Snapshots shows a list: one taken from the overview first (they add up over runs).
        if [ $name = snapshots ]; then page 1; sleep 2; press_label "Snapshot anlegen" "Take snapshot"; sleep 8; fi
        # The editors' previews need the dev server; started once, before the first of them.
        if [ "$flag" = s ] && [ $serving = 0 ]; then key r; sleep 30; serving=1; fi
        page $row; sleep 2
        [ -n "$t" ] && { tab $t; sleep 2; }
        # After the page is open: before it, the wait was spent on the previous page and Vorlagen
        # was taken while it still said „Lade…“ (2026-11-13).
        [ "$flag" = w ] && sleep 10
        # Anwenden with the basic template loaded: the parts with their choice per part.
        if [ $name = vorlagen ]; then
          press templates.pickBuiltin; sleep 10
        fi
        # A navigation chosen: the inspector shows its first step.
        if [ $name = plugins-navigationen ]; then
          list_row navigations.list 2; sleep 3
        fi
        # Stile ▸ Variablen as it opens (base colours unfolded), then the template's variables with
        # one chosen, then a plugin's: found through the search, so its row is laid out.
        # The rows are buttons (no text of their own in the tree): the template's is pressed by its
        # identifier, the plugin's clicked under its plugin's heading. Scrolled so the section is on top.
        if [ $name = stile-variablen-vorlage ]; then
          click_text "Grundfarben" "Base colors"; sleep 1
          click_text "Abstände" "Spacing"; sleep 1
          ax "set els to entire contents of $project_window
 repeat with e in els
  try
   if role of e is \"AXButton\" and value of attribute \"AXIdentifier\" of e is \"variables.row.tpl-space-md\" then
    click e
    exit repeat
   end if
  end try
 end repeat"; sleep 2
          scroll_down 520; sleep 2
        fi
        if [ $name = stile-variablen-plugins ]; then
          scroll_down 3000; sleep 1
          click_text "Alle Theme- und Build-Variablen" "All theme and build variables"; sleep 2
          scroll_down 3000; sleep 1
          type_by_placeholder "Variable suchen" "Search variable" rail-icon; sleep 2
          scroll_down 3000; sleep 1
          click_text "Plugin-Variablen" "Plugin variables"; sleep 2
          scroll_down 3000; sleep 1
          click_text "Navigations" "Navigations" 41; sleep 2
        fi
        # A row comes in on the frame board: index on Mobile, right dragged between header and left,
        # taken while the line shows; let go over the sidebar, so the frame stays as it was.
        if [ $name = layout-frames-zeilen ]; then
          pick layout.frames.picker index; sleep 2
          radio 2 3; sleep 2
          set -- $(element_frame layout.frames.area.right); rx=$(( $1 + $3 / 2 )); ry=$(( $2 + $4 / 2 ))
          set -- $(element_frame layout.frames.area.header); hy=$(( $2 + $4 ))
          set -- $(element_frame layout.frames.area.left); ly=$2
          set -- $(osascript -e "tell application \"System Events\" to tell process \"QuartzHub\" to get position of $project_window" | tr -d ,)
          wx=$(( $1 + 600 )); wy=$(( $2 + 20 ))
          set --
          # Let go over the window's title bar, which takes no drop: not over another app.
          drag_hold $rx $ry $rx $(( (hy + ly) / 2 )) 5 $wx $wy
          sleep 4
          shoot $name
          wait
          sleep 2
          continue
        fi
        # Community-Themes: the project's theme chosen and turned on in the draft only, so the inspector
        # shows it loaded with its settings; then a theme of the catalog, found through the search. Turned
        # off again afterwards, so the page is not left with a change.
        if [ $name = stile-themes ]; then
          axdo row themes.list 2; sleep 2
          axdo press themes.reactivate; sleep 10
        fi
        if [ $name = stile-themes-katalog ]; then
          mouse click $(axdo center themes.search); sleep 0.5
          ax "keystroke \"Catppuccin\""; sleep 3
          axdo row themes.list 4; sleep 6
          shoot $name
          mouse click $(axdo center themes.search); sleep 0.5
          key a; ax "key code 51"; sleep 1
          axdo row themes.list 2; sleep 2
          axdo press themes.disable; sleep 1
          continue
        fi
        # A form chosen: the step "Felder"; the preview goes to a page that embeds it. Back to the
        # first step whatever the window remembered, then one on.
        if [ $name = plugins-formulare-formular ]; then
          preview_page $([ $lang = de ] && echo kontakt || echo en/contact); sleep 4
          list_row forms.list 2; sleep 2
          repeat 6 { ax "key code 123 using {command down, option down}"; sleep 0.3 }
          ax "key code 124 using {command down, option down}"; sleep 4
        fi
        shoot $name
      done
      [ $serving = 1 ] && { key .; sleep 3; }
    fi

    if wanted projekte-leer; then
      launch $lang "$(empty_profile $theme)" 1 $offline
      shoot projekte-leer
    fi
    if wanted projekte || wanted projekte-fehlt || wanted neues-projekt || wanted duplizieren; then
      launch $lang "$DEMO/profile-$theme" 1 $offline
      if wanted projekte; then project_row 1; sleep 1; shoot projekte; fi
      if wanted projekte-fehlt; then project_row 3; sleep 1; shoot projekte-fehlt; fi
      if wanted neues-projekt; then key n; sleep 3; shoot neues-projekt; escape; sleep 1; fi
      if wanted duplizieren; then
        project_row 1; sleep 1; press projects.duplicate; sleep 2
        type_into 2 QuartzHub-Docs-$([ $lang = de ] && echo Kopie || echo copy); sleep 1
        shoot duplizieren; escape; sleep 1
      fi
    fi
    # The settings, one shot per tab (toolbar buttons in order).
    if wanted einstellungen-allgemein || wanted einstellungen-zugaenge || wanted einstellungen-laufzeit || wanted einstellungen-daten; then
      launch $lang "$DEMO/profile-$theme" 1 $offline
    fi
    n=0
    for t in allgemein zugaenge laufzeit daten; do
      n=$((n + 1))
      wanted einstellungen-$t || continue
      ax 'keystroke "," using command down'; sleep 2
      ax "click button $n of toolbar 1 of window 1"; sleep 2
      shoot einstellungen-$t front
    done
    if wanted vorschau-und-build-laeuft; then
      with_project $lang $theme
      page 10; sleep 2; key r
      # Quartz builds before it serves; the preview shows the site after that.
      sleep 25
      shoot vorschau-und-build-laeuft
      key .; sleep 3
    fi
  done
done
pkill -x QuartzHub 2>/dev/null || true
[ ${#new} -eq 0 ] && exit 0
swift "$ROOT/scripts/handbook-private.swift" "$VAULT" $new
