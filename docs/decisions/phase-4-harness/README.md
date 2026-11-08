# Messgeschirr Phase 4b

Zwei Wegwerf-Pakete für die zwei Entscheidungen in
[`phase-4-oberflaeche.md`](../phase-4-oberflaeche.md#4b-code-editor-und-umsortieren). Nicht Teil
des Baus; zum Nachmessen in einen Ordner außerhalb des Repos kopieren (SwiftPM legt `.build/` neben
`Package.swift` an).

## editor-spike

NSTextView (TextKit 2) gegen STTextView 2.4.1 (das Paket holt SwiftPM von GitHub, gepinnt mit
`exact:`), dieselbe Regex-Hervorhebung in beiden.

```sh
cat ~/Documents/QuartzProjekte/gui-test/quartz/styles/custom/*.scss > big.scss   # 6.819 Zeilen
cp ~/Documents/QuartzProjekte/gui-test/quartz/styles/custom/content.scss .        # 1.411 Zeilen
swift build -c release
.build/release/Spike ns content.scss            # ns | st; dritter Wert "nohl" ohne Hervorhebung
.build/release/Spike ns content.scss nohl ruler # mit Zeilennummern (nur ns)
.build/release/AXProbe <pid>                    # Bedienungshilfe-Baum des Editors, während er läuft
```

Der Spike öffnet ein Fenster, setzt den Text, färbt alles, tippt dann 200 Zeichen in die Mitte
(`insertText`, je Zeichen Absatz neu färben und `displayIfNeeded`), druckt die Zeiten und den
Speicher (RSS) und beendet sich nach 25 s. Screenshot mit `screencapture -o -l "$(swift winid.swift)"`.

## reorder-spike

SwiftUI-Liste mit `onMove`, Kontextmenü, Bedienungshilfe-Aktionen und einem Menü „Anordnen“
(⌥⌘↑/⌥⌘↓ über `focusedSceneValue`), jede Bewegung angesagt. Die Probe steuert sie von außen:

```sh
swift build
.build/debug/Reorder &                               # druckt die Reihenfolge nach jeder Bewegung
.build/debug/Probe <pid> dump                        # Zeilen und ihre Aktionen
.build/debug/Probe <pid> listen 12 &                 # AXAnnouncementRequested mitschreiben
.build/debug/Probe <pid> perform row.Gamma "Nach oben"
osascript -e 'tell application "System Events" to key code 125 using {option down, command down}'
.build/debug/Probe <pid> drag row.Alpha row.Delta   # Maus, bewegt den echten Zeiger
```
