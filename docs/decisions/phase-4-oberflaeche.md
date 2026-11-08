# Phase 4: Oberfläche

Die Messungen und Entscheidungen beim Bau der Oberfläche, ein Abschnitt je Teil.

## Entscheidungen zu Beginn (Nutzer, 2026-11-08)

- QuartzControl gibt Funktion, Texte und Ränder vor; das Aussehen ist natives macOS (`Form`
  grouped, Listen, Inspektor statt Karten).
- Die Einstellungen sind ein eigenes Fenster (⌘,).
- Für den Code-Editor darf STTextView über SwiftPM rein, wenn die Lizenz zu GPL-3.0 passt.
- **Ein Fenster „Projekte“ und ein Fenster je Projekt** statt QuartzControls einem Fenster mit
  Startseite. Zwei Projekte können gleichzeitig offen sein, dasselbe nur einmal.

## 4a: Fenster „Projekte“ und Projektfenster

**Aufbau.** `Window` „Projekte“ (`App/Projects/ProjectsWindow.swift`, die erste Szene, also das
Fenster beim Start und das, was das Dock-Symbol zurückholt; Fenster ▸ Projekte, ⇧⌘0) und
`WindowGroup(id: "project", for: String.self)` mit der Projekt-ID (`App/Shell/ProjectWindow.swift`).
SwiftUI hält je Wert ein Fenster: ein zweites Öffnen holt das offene nach vorn. Ablage ▸
„Vorhandenes Projekt öffnen…“ (⌘O) ersetzt „Neues Fenster“: ein Projektfenster ohne Projekt
bedeutet nichts. Die Liste liegt in einem gemeinsamen Modell (`ProjectsModel`); ein Projektfenster,
dessen Projekt entfernt wird, sagt das und bietet die Liste an.

**Kern.** `ProjectOverviews` portiert `projectOverviewService` und Sortierung und Suche aus
`Home.tsx`. Gemessen gegen Home.tsx' eigene Ausdrücke in Node
(`scripts/project-overview-golden.mjs`, 13 Zeilen, 13 Suchen). Dabei gefunden: Ein leerer
`lastOpenedAt` ist in JavaScript falsy und zählt als 0, nicht als NaN; ein unlesbarer ist NaN, und
`NaN || …` fällt auf den Namen durch. Mit NaN sortiert V8 inkonsistent; `JS.sort` bildet das nach,
das unlesbare Projekt steht an derselben Stelle wie in QuartzControl. Eine Abweichung mit Absicht:
Die Suche nimmt „ä“ und „a“ + Trema als gleich (Swifts `contains`), JavaScripts `includes` nicht.
`ProjectList` setzt zusammen, was QuartzControls `projects:*`-Handler zusammen taten (Pfade
umbiegen vor dem Verschieben, Server stoppen und Relay-Geheimnisse löschen beim Entfernen).

**UI-Test.** Der Rauchtest braucht jetzt ein Projekt: ein Wegwerf-Profil mit einem Ordner samt
`quartz.config.yaml`, geöffnet mit `-QHOpenProject <pfad>` (nur Debug). Drei Dinge, die dabei
anders waren als gedacht:

- Der Fenstertitel im Bedienungshilfe-Baum ist Titel und Untertitel zusammen („smoke-projekt –
  Übersicht“); der Test sucht mit `BEGINSWITH`.
- Mit zwei Fenstern findet `app.descendants(…)[kennung].firstMatch` die Kennung im falschen
  Fenster: „inspector.toggle“ gibt es in beiden, der Test klickte den Inspektor der Projektliste
  und wartete im Projektfenster vergeblich. Und „inspector.pageContext“ stand in beiden, die
  Prüfung je Seite hätte also nie scheitern können. Prüfungen im Projektfenster suchen jetzt nur
  dort, und der Kontext der Projektliste heißt „inspector.projectsContext“.
- `app.buttons["Aus der Liste entfernen"]` traf die Kopie des Buttons in der Touch Bar
  („cannot be called with Touch Bar elements“); `app.windows.buttons[…]` trifft den im Dialog.

Gegenproben: Entfernen ohne Wirkung scheitert an „row still listed“, Entfernen ohne Rückfrage an
„no question before removing“.

**Neues Projekt.** `ProjectCreation` (Kern) ist der Ablauf aus `Home.tsx` nach `quartz create`:
in die Liste, Stilblöcke ohne Snapshot verschieben, Beispielvorlage mit `packageWins`, die Sprache
der Website nach der App. Was danach scheitert, wird gemeldet, nicht zurückgenommen. Eine
Abweichung: Ein gescheitertes Verschieben der Stile ist ein eigener Satz; in QuartzControl stand es
zwischen den `art:detail`-Warnungen und kam als „1× ‹ganzer Satz›“ heraus. `ImportWarnings` macht aus
den Warnungen die Sätze von `ImportOutcome.tsx` (gruppiert, Detail-Arten über eine Probe im
Katalog). Der Dialog (`CreateProjectSheet`, ⌘N und Symbolleiste) ist im UI-Test nur bis vor das
Anlegen geprüft: ein echtes Anlegen klont Quartz von GitHub und ist ein Netzlauf.

**Einstellungen.** Ein eigenes Fenster (⌘,) mit drei Tabs: Allgemein (Design, Sprache,
Projektordner, Beim Beenden), Laufzeit (Node, git), Daten & Wartung. Jede Wahl schreibt sofort und
nur ihr Feld (`SettingsStore`, lesen–ändern–schreiben wie QuartzControls ganzes Objekt). Der
GitHub-Token und die Verbindungen kommen mit „Veröffentlichen“. Drei Dinge, gemessen am laufenden
Fenster (2026-11-08):

- **Design** setzt `NSApp.appearance` und greift sofort, in allen Fenstern.
- **Sprache:** Die Fenster bauen ihren Inhalt neu auf (`followsLanguage`, `.id` an einer Revision),
  unsere Menübefehle ebenfalls, wenn ihr `body` die Revision liest; ohne das blieben „Neues
  Projekt…“ und „Inspektor einblenden“ in der alten Sprache. Die Menüs von macOS selbst (Ablage,
  Bearbeiten, Fenster) nehmen die Sprache beim Start. Deshalb schreibt der Wechsel auch
  `AppleLanguages` der App, wie es die Systemeinstellung „Sprache je App“ tut; nach dem Neustart
  hießen sie File, Edit, View. Bei „Systemsprache folgen“ wird der Schlüssel entfernt.
- **Node-Laufzeit:** Die Umgebung wurde bisher einmal beim Start bestimmt. Jetzt wird sie beim
  Umschalten neu bestimmt, und der `BuildService` fragt bei jedem Vorgang die aktuelle
  (`AppServices.current()`): „Gilt für Vorgänge, die danach starten“, wie der Text sagt.

**Neben QuartzControl.** Ein Band oben im Projektfenster, solange QuartzControl läuft
(`NSRunningApplication`, aktualisiert bei Start und Ende von Apps), dazu dessen Dev-Server für genau
dieses Projekt. Nicht am laufenden QuartzControl gesehen: es zu starten, löst dessen Abfrage nach
einer neueren Fassung bei GitHub aus, ein Netzlauf. Was das Band meldet, prüft
`CoexistenceConcernsTests`. Eine Warnung je Schreibvorgang kommt mit den Seiten, die schreiben.

## 4b: Code-Editor und Umsortieren

Zwei Entscheidungen, je mit einer kleinen Messung (2026-11-08, macOS 27.2, Apple Silicon). Das
Messgeschirr liegt in [`phase-4-harness/`](phase-4-harness/README.md). Jede Zahl ist ein Lauf, das
Öffnen schwankte zwischen zwei Läufen um 10 ms. Gebaut wird beides mit der ersten Seite, die es
braucht, nicht vorab.

### Code-Editor: NSTextView mit TextKit 2, kein Fremdpaket

**Was QuartzControl vom Editor will.** CodeMirror steht in `Styles/CustomCss.tsx` und
`PluginOptionsForm/snippets.tsx`. Gebraucht wird:
- SCSS und CSS gefärbt, mit Einrückungslinien (der Block des Cursors dunkler);
- Markdown und HTML mit Zeilenumbruch;
- eine nur lesende Fassung für die Referenzdateien;
- Einfügen an der Cursorstelle, nur wenn der Nutzer einen Cursor gesetzt hat;
- Sprung zu einer Zeile (Diagnose der SCSS-Prüfung);
- Zeilennummern, Suchen, Hell und Dunkel;
- eine Änderung von außen ersetzt das Dokument, ohne einen dritten Stand dazwischen
  (`styles-and-fonts.md`, „Der Editor darf zwischen zwei Ständen nicht durch einen dritten“).

**Lizenz.** STTextView steht unter GPLv3 (ohne „or later“), alternativ kommerziell. Seine
Abhängigkeiten sind STTextKitPlus (BSD-3-Clause) und CoreTextSwift (MIT). Das ist mit
GPL-3.0-or-later vereinbar; das gebaute Ganze stünde dann unter GPL-3.0. STTextView scheitert also
nicht an der Lizenz.

**Messung.** Beide Editoren hatten denselben Regex-Färber und dieselbe Schrift, gebaut als
Release. Die Dateien:
- `content.scss` aus gui-test, 1.411 Zeilen;
- alle Dateien unter `custom/` hintereinander, 6.819 Zeilen.

„Tastendruck“ heißt: `insertText` eines Zeichens in die Mitte, dann den Absatz neu färben und
`displayIfNeeded`, gemittelt über 200 Drücke. Der Speicher ist der RSS des Prozesses.

| | NSTextView (TextKit 2) | STTextView 2.4.1 |
|---|---|---|
| Öffnen bis zur ersten Anzeige, 1.411 Zeilen | 19–30 ms | 35–36 ms |
| je Tastendruck ohne Färben | **1,26 ms** | **8,10 ms** |
| je Tastendruck mit Färben, 1.411 / 6.819 Zeilen | 17,9 / 23,5 ms | 25,2 / 32,1 ms |
| Speicher nach dem Öffnen → nach 200 Drücken, ohne Färben | **106 → 121 MB** | **93 → 315 MB** |
| Speicher nach 200 Drücken mit Färben, 6.819 Zeilen | 128 MB | 389 MB |
| Bedienungshilfen (aus einem zweiten Prozess abgefragt) | `AXTextArea`, 11 parametrisierte Attribute | `AXTextArea`, 7 davon |

**Bedienungshilfen.** Beide lesen dieselbe Zeile zu Index 500 (Zeile 8) und denselben Text zu einem
Bereich. STTextView fehlen `AXRangeForIndex`, `AXStyleRangeForIndex`, `AXRTFForRange` und
`AXSharedTextElementForIndex`.

**Was STTextView fertig mitbringt.** Gegenüber NSTextView sind das nur die Zeilennummern.
Einrückungslinien hat keiner von beiden, Suchen haben beide (NSTextView über `usesFindBar`). Für
die Nummern genügt ein `NSRulerView`, der `enumerateTextLayoutFragments` ab dem ersten sichtbaren
Fragment geht (40 Zeilen, `editor-spike/Sources/Spike/Ruler.swift`). Er zeichnet richtig (im
Screenshot steht 1411 an der letzten Zeile von `content.scss`). Messbar kostet er nichts: 1,24 ms je
Tastendruck mit Leiste gegen 1,26 ms ohne, bei 6.819 Zeilen 1,22 ms. Beim Bau beachten: Die leere
Zeile nach dem letzten Zeilenumbruch hat kein Layout-Fragment und bekommt so keine Nummer.

**Das Teure ist das Färben, nicht der Editor.** Die Regex-Färbung des Spikes kostet in beiden
Editoren rund 16 ms je Tastendruck. Ein Tastendruck kostet ohne sie 1,3 ms. Der echte Färber wird
ein kleiner Lexer im Kern, ohne UI testbar. Sein Ziel: wenige Millisekunden je Tastendruck auf den
6.819 Zeilen, gemessen, bevor die erste Seite ihn bekommt.

**Entscheidung.** NSTextView mit TextKit 2 (`NSTextView.scrollableTextView()` liefert TextKit 2),
dazu eigene Zeilennummern, eigenes Färben und eigene Einrückungslinien, als `NSViewRepresentable`.
Kein Paket. STTextView ist bei jedem Tastendruck sechsmal so teuer, und sein Speicher wuchs je
Tastendruck um gut 1 MB. Bei den Bedienungshilfen bietet es weniger, und es würde zwei Pakete
mitbringen, um ein Lineal zu sparen.

### Umsortieren: native Liste, dazu Befehle

**Was QuartzControl tut.** dnd-kit steht in acht Dateien:
- Sortierlisten: installierte Plugins, Formularfelder, Seitenreihenfolge der Dokumente; dazu die
  Ladereihenfolge der Stylesheets, die nur Pfeile hat;
- ein Raster: den Frame-Builder;
- ein Board mit Ablagezonen und Vorrat: das Layout.

Die Regeln dazu stehen in `conventions-full.md` unter „Kein natives HTML5-Drag mehr“ und „Was
keinen festen Platz hat …“:
- Alles muss mit der Tastatur gehen.
- Sortierlisten tragen zusätzlich „nach oben / nach unten“, weil die Tastatur-Aufnahme eine Geste
  ist, die man kennen muss.
- Das Board verschiebt über die Seitenleiste: „Früher“, „Später“, Position, „In den Vorrat legen“.
- Jede Bewegung wird mit einem ganzen Satz angesagt, der sagt, was passiert ist.

**Messung.** Gemessen an einer SwiftUI-Liste mit fünf Zeilen, die von außen über die
Bedienungshilfen gesteuert wurde. Die App druckte die Reihenfolge nach jeder Bewegung.
- **Maus:** `ForEach.onMove` in `List(selection:)`. Alpha, über Delta gezogen, landete dahinter.
  Vorher stand die Liste auf Alpha, Gamma, Delta, Beta, Epsilon, danach auf Gamma, Delta, Alpha,
  Beta, Epsilon.
- **Tastatur:** Ein Menü „Anordnen“ hat „Nach oben“ und „Nach unten“ mit ⌥⌘↑ und ⌥⌘↓, angebunden
  über `focusedSceneValue`. ⌥⌘↓ bewegte die ausgewählte Zeile Beta von Platz 3 auf 4, und die
  Auswahl blieb auf Beta.
- **VoiceOver-Aktionen:** `accessibilityAction(named:)` erscheint als `Name:Nach oben` unter den
  Aktionen. `AXUIElementPerformAction` darauf bewegte Gamma von Platz 3 auf 2. Die Aktionen hängen
  am Inhalt der Zeile (`AXStaticText`), nicht an der `AXRow`.
- **Ansage:** `AccessibilityNotification.Announcement(…).post()` kam je Bewegung einmal als
  `AXAnnouncementRequested` mit dem Satz an, mitgelesen über `AXObserver`.

Nicht gemessen:
- ob VoiceOver die Ansage tatsächlich spricht; die Ansage kam beim System an, gehört wurde sie
  nicht;
- wo die Aktionen landen, wenn eine Zeile mehr als ein Element hat.

**Entscheidung.**
- **Sortierlisten:** `List` mit `onMove` für die Maus. Dazu kommen „Nach oben“ und „Nach unten“
  mit derselben Funktion an drei Stellen:
  - im Menü mit ⌥⌘↑/⌥⌘↓;
  - im Kontextmenü der Zeile;
  - als Bedienungshilfe-Aktion der Zeile.
  
  Nach jeder Bewegung kommt eine Ansage mit den übernommenen `dnd.*`-Sätzen und
  `pluginsInstalled.moveUp`/`moveDown`. Beim Bau zu messen: ob das Kürzel nur greift, solange die
  Liste den Fokus hat (`focusedValue` statt `focusedSceneValue`), und wo die Aktionen bei einer
  Zeile mit mehreren Elementen landen (`accessibilityElement(children: .combine)`).
- **Raster und Board (Layout):** Die Maus zieht mit `draggable` und `dropDestination`. Die Tastatur
  verschiebt über den Inspektor, so wie QuartzControls Seitenleiste seit 1.1. macOS hat keine
  native Geste, mit der die Tastatur etwas in einem Raster zieht. Eine nachgebaute wäre wieder
  dnd-kits Pfeil-Logik mit allen Rändern aus `dndKeyboard.ts`. Gemessen wird das mit der Seite
  Layout.
