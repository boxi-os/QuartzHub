---
name: run-app
description: QuartzHub bauen, starten und wirklich ansehen (Screenshot des Fensters, Menüs und Bedienungshilfen über System Events, Hell/Dunkel, Sprache). Verwenden, wenn die App gestartet, ein Screenshot gemacht oder eine UI-Änderung an der laufenden App bestätigt werden soll, nicht nur gebaut.
---

# QuartzHub laufen lassen und ansehen

## Bauen und starten

```sh
cd ~/Development/QuartzHub
scripts/xcodegen.sh
xcodebuild -project QuartzHub.xcodeproj -scheme QuartzHub -derivedDataPath build/DerivedData build -quiet
open -n build/DerivedData/Build/Products/Debug/QuartzHub.app --args -QHLanguage de -ApplePersistenceIgnoreState YES
```

Startargumente: `-QHLanguage de|en` (Sprache unabhängig vom Mac), `-QHWindowSize 1400x860`
(Startgröße; entfernt gespeicherte Fensterrahmen), `-ApplePersistenceIgnoreState YES` (kein
wiederhergestelltes Fenster), `-QHProfileDir <ordner>` (QuartzHubs Profil woanders, sonst
`~/Library/Application Support/QuartzHub`), `-QHMigrationSource <ordner>` (Profil von QuartzControl
für die Übernahme; leer = aus). **Ohne diese beiden bietet die App die Übernahme aus dem echten
QuartzControl-Profil an, solange QuartzHubs eigenes keine `projects.json` hat**; „Übernehmen“ liest
dann den echten Schlüsselbund-Eintrag. Zum bloßen Ansehen `-QHMigrationSource ""` setzen. Die
Übernahme-Tasten im Dialog: System Events findet den Button im Sheet nicht über `entire contents`;
Return löst „Übernehmen“ aus (Standardtaste). Für das Release-Paket: `scripts/package.sh`, dann
`build/package/QuartzHub.app`.

Beenden: `pkill -x QuartzHub`.

## Ansehen

Fenster-Screenshot (ohne Schatten) in den Scratchpad, dann mit Read ansehen:

```sh
cat > "$SCRATCH/winid.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "QuartzHub" { print(w[kCGWindowNumber as String]!); break }
SWIFT
screencapture -o -l "$(swift "$SCRATCH/winid.swift")" "$SCRATCH/shot.png"
```

Menüs und Kürzel über System Events (Menüleiste heißt auf Deutsch „Darstellung“ usw.):

```sh
osascript -e 'tell application "System Events" to tell process "QuartzHub"
  set out to {}
  repeat with mi in (every menu item of menu 1 of menu bar item "Darstellung" of menu bar 1)
    try
      set end of out to (name of mi) & " ⌘" & (value of attribute "AXMenuItemCmdChar" of mi) & " mod=" & (value of attribute "AXMenuItemCmdModifiers" of mi)
    end try
  end repeat
  return out
end tell'
```

`mod`: 0 = ⌘, 1 = ⇧⌘, 2 = ⌥⌘, 4 = ⌃⌘, 8 = ohne ⌘.

## Dunkel und Hell

Die App folgt dem System; eine eigene Einstellung (wie `nativeTheme.themeSource` in QuartzControl)
kommt erst mit den Einstellungen. `-AppleInterfaceStyle Light` als Startargument erzwingt auf einem
dunklen System **kein** Hell (gemessen 2026-11-06: Fenstermitte blieb RGB 30/30/30). Ob
`-AppleInterfaceStyle Dark` auf einem hellen System Dunkel erzwingt, ist nicht gemessen. Bis zur
eigenen Einstellung: die Systemdarstellung umstellen lassen (der Nutzer) und beide Aufnahmen machen.

## Automatisch

Der Rauchtest (`xcodebuild … test`) klickt jede Seite in zwei Größen durch. Er bewegt Maus und
Tastatur; während er läuft, nicht am Mac arbeiten. Fenster lassen sich unter XCUITest nicht per
Ziehen in der Größe ändern (siehe `docs/decisions/phase-1-geruest.md`), deshalb `-QHWindowSize`.
