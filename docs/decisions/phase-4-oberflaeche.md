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

## 4c: Die Seiten

Eine Seite je Abschnitt, in der Reihenfolge des Plans. Vorbild ist jeweils `src/routes/*` in
QuartzControl 1.3.

### Übersicht

Vorbild `ProjectDashboard.tsx`. Neu im Kern sind zwei Dienste:

- **`BuildOutput.info`** beschreibt, was im Ausgabeordner liegt, als Nachbau von `getBuildOutput`.
  Gemessen mit `scripts/build-last-output-golden.mjs` gegen QuartzControls eigenen Code, 15 Fälle:
  - Links, Links ins Leere und ein verlinkter Ausgabeordner;
  - Millisekunden werden abgeschnitten, nicht gerundet;
  - ein Unterordner, der sich nicht lesen lässt.

  Abweichung: Lässt sich ein Unterordner nicht lesen, bekommt die Seite einen Fehler mit dem
  Ordner. QuartzControls Kachel wartete dann für immer auf eine Antwort.
- **`ProjectAttention`** enthält die Regeln des Bands „Handlungsbedarf“ und die Bedingung für
  „Alles ok“, mit je einem Test. Ein Lesevorgang hat drei Zustände: läuft noch, gescheitert,
  fertig. Ein gescheiterter Lesevorgang ergibt nie „Alles ok“.

**Aussehen.** Aus jeder Kachel wird ein Abschnitt eines gruppierten `Form`, untereinander in der
Reihenfolge der Kacheln:

- Die Kopfzeile zeigt das Symbol der Seite, den Namen und rechts den Zustand: Serverzustand, Branch
  oder Zahl der Updates.
- Oben im Abschnitt steht der eine Wert, um den es geht.
- Darunter stehen die Einzelheiten.
- Am Fuß führt ein Verweis auf die zuständige Seite.
- Das Band steht über allen Abschnitten.
- „Build ausführen“, „Snapshot anlegen“ und „Projektordner öffnen“ stehen in der Symbolleiste.
- Der Inspektor zeigt den Seitenkontext mit dem Projektordner.

Gesehen in Hell und Dunkel an einer Kopie von gui-test ohne `node_modules`. Gegen die Platte
geprüft:

| Angabe | Seite | Platte |
|---|---|---|
| Build-Ordner | 475 Dateien, 32 MB, vor 2 Wochen | 475 Dateien, 32.499.736 Byte, 25. Oktober |
| Snapshots | 12, nach einem Klick 13 („Von dir“) | 12 Refs, danach 13 |
| Ziele | 7 | 7 |
| Plugins | 46 von 64 aktiv | – |
| Band | „88 npm-Pakete fehlen“ mit „Installieren“ | – |

„Build ausführen“ meldete ohne Pakete „Build fehlgeschlagen“, und der alte Build blieb liegen.

**Was beim Bau anders war als gedacht.**
- **`RelativeDateTimeFormatter`** liest Wochen nur als `weekOfMonth`. Mit `weekOfYear` kam ein
  leerer Text heraus (gemessen: „“ gegen „vor 3 Wochen“), und die Git-Zeile stand ohne Datum da.
- **Serverzustand und Build-Aktivität** kamen bisher nur als Ereignisse aus `BuildService`.
  `BuildMonitor` liest sie in der Reihenfolge, in der der Dienst sie sendet, über einen Strom mit
  einem Leser auf dem Main Actor. Eine Seite, die vor dem ersten Ereignis öffnet, fragt den Dienst
  einmal. Kommt inzwischen ein Ereignis, gewinnt das Ereignis.
- **XCUITest liest als `label` den Text im Knopf**, auch wenn der Knopf selbst keinen
  Bedienungshilfe-Namen trägt. Die Gegenprobe ohne `accessibilityLabel` blieb grün, also prüft
  eine solche Assertion nichts. Ob ein Element einen Namen hat, sagt erst
  `AXUIElementCopyAttributeValue` (`AXDescription`). So stellte sich auch heraus, dass die Verweise
  `AXLink` mit Namen sind. Namenlos sind nur die Pfeile der Rollbalken und die Ampelknöpfe.
- **Die Update-Prüfung ist der einzige Netzzugriff der Seite** (`git ls-remote`). Rauchtest und
  Ansehen schalten sie im Debug-Bau mit `-QHNoUpdateCheck YES` ab. Der Abschnitt sagt dann „Nicht
  prüfbar“.

**Abweichungen von QuartzControl.**
- „Abbrechen“ bei der Frage zum Ausgabeordner schließt die Frage ohne weitere Meldung. QuartzControl
  zeigte einen Toast „Abgebrochen: …“. Die Frage selbst ist ein `NSAlert`; „Abbrechen“ steht zuerst
  und ist die Standardtaste.
- Was eine Aktion nicht konnte, steht in einem Hinweisfenster. QuartzControl zeigte dafür einen
  Toast.
- Der Rückweg zur Übersicht (`markReturn`) ist nicht übernommen. Die Seitenleiste zeigt den Weg
  zurück.
- Die Tabs, auf die ein Verweis zielt (`config?tab=site`, `styles?tab=customCss`), stehen schon
  in `ProjectAttention.Issue.tab`. Die Seiten lesen sie, sobald sie Tabs haben.

**Nicht gemessen:**
- „Installieren“ (npm aus dem Netz);
- die Update-Prüfung selbst;
- Starten des Servers: ohne `node_modules` startet Quartz nicht, und mit fehlt der Kopie nichts.

### Vorschau & Build

Vorbild `BuildServer.tsx` mit `LogConsole`, `DiscoveredServers` und `BuildActivityLine`. Neu im
Kern ist nur **`ProjectPrefs.outputDirProblem`**: die Regel aus QuartzControls Schema
`projectPrefs` (`ipc/schemas.ts`) für den Ausgabeordner. Erlaubt sind leer, absolut bis 4096
UTF-16-Einheiten oder relativ bis 1024 ohne ein Segment „..“ (getrennt an „/“ und „\“). Gemessen
mit `scripts/output-dir-golden.mjs` gegen das Schema selbst, 37 Fälle. Die Gegenproben scheitern:
Zeichen statt UTF-16 zählen, oder nur an „/“ trennen.

**Aussehen.** Drei Abschnitte eines gruppierten `Form`:
- **Dev-Server.** Er beginnt mit der Adresse: ein Link, wenn der Server läuft, sonst grau mit der
  Adresse, die er haben wird. Daneben steht „Kopieren“. Darunter kommen:
  - die Angaben zum Lauf oder der Hinweis;
  - der Fehler;
  - der Hinweis auf eine fehlende `index.md`;
  - die Aktivität;
  - Starten oder Neustarten und Stoppen;
  - die Server-Einstellungen, eingeklappt, jedes Feld eine Zeile;
  - die Live-Vorschau;
  - die Konsole.
- **Laufende Server auf diesem Rechner** (`ServerScan.discover`).
- **Einmaliger Build** mit:
  - „Jetzt bauen“;
  - dem Inhalt des Ausgabeordners;
  - dem Feld „Ausgabeordner“ mit „Auswählen“ und „Zurücksetzen“;
  - dem Ergebnis;
  - der Konsole.

**Gemessen** in Hell und Dunkel an einer Kopie von gui-test. Die `node_modules` sind per APFS-Klon
mitgekopiert, Server auf 8080/3001:

| Vorgang | Ergebnis |
|---|---|
| Starten | Port 8080 lauscht nach 16 s; Zustand „Läuft“, Vorschau zeigt die Startseite |
| „Mobil“ | Vorschau 390 pt breit, mittig, Anzeige „390 px“ |
| In der Vorschau auf „animation“, dann „Desktop“ | Vorschau bleibt auf „animation“: Breitenwechsel lädt nicht neu |
| „Jetzt bauen“ nach `public/` bei laufendem Server | abgelehnt, der Satz rot in der Build-Konsole |
| Ausgabeordner „../x“ | Fehler unter dem Feld, `project-prefs.json` unverändert |
| Ausgabeordner „dist“, dann bauen | Datei hat `"dist"`, „Erfolgreich in 12,1s“, 475 Dateien in `dist/`, der Server lief weiter |
| „Server beenden“ in der Liste, „Abbrechen“ | Server läuft weiter |
| dasselbe, „Server beenden“ | Port frei, Liste „Es läuft kein Quartz-Server …“, 0 |
| Port 8095 eingetippt, zur Übersicht und zurück | 8095 steht noch, die Adresse sagt `:8095`, die Einstellungen offen |

**Was beim Bau anders war als gedacht.**
- **Die Konsole folgte dem Ende nicht.** Ob der Leser unten steht, prüfte sie an der Höhe des
  Dokuments. TextKit 2 legt neue Zeilen aber erst später aus. Die Höhe war also noch die alte,
  und die Konsole blieb auf dem ersten Bildschirm stehen (gesehen an der Server-Konsole). Jetzt
  merkt sie sich das Folgen, wenn der Leser selbst rollt (`boundsDidChange`; wachsender Text
  bewegt keine Grenzen). Sie rollt über den Bereich (`scrollRangeToVisible`), nicht über den
  Rahmen.
- **„localhost:8.080“.** Ein interpolierter String-Literal in `Label("…\(port)")` ist ein
  `LocalizedStringKey`, und die Zahl kam mit Tausenderpunkt heraus. Jetzt steht dort ein
  zusammengesetzter `String`.
- **Ein `Text` meldet seine Worte als Wert, nicht als Label.** Unter XCUITest ist `label` leer, der
  Text steht in `value` (gemessen über `AXValue`). Der Test wartet deshalb auf `value`.
- **Übernommene Texte nannten „QuartzControl“ und „Von dieser App“.** Das betraf die
  Stopp-Fragen, den Warnhinweis und die Herkunft in der Liste. Sie sagen jetzt „QuartzHub“.
- **Die Stopp-Frage teilt sich am Absatz.** Der Text vor dem Absatz ist der Titel, der Rest der
  Text des Hinweisfensters. QuartzControl hatte beides in einem Text.

**Abweichungen von QuartzControl.**
- **Die Konsole ist ein `NSTextView` statt einer Liste.**
  - Text lässt sich über Zeilen hinweg markieren und kopieren.
  - Neue Zeilen werden angehängt, statt bis zu 999 neu zu zeichnen.
  - Der Hintergrund folgt dem System, nicht immer dunkel.
  - Sie folgt dem Ende nur, wenn man unten steht; QuartzControl rollte bei jeder Zeile hinab.
  - Neue Zeilen werden nicht angesagt (`role="log"`); bei einem laufenden Server wäre das
    Dauerrede.
- **Die Vorschau ist ein `WKWebView`.** Eine Navigation bleibt nur innerhalb des Servers. Ein Link
  anderswohin öffnet sich im Browser, ebenso `target="_blank"`. QuartzControls Sandbox ließ beide
  stumm.
- **`sitePreview.highlight` nach dem Laden entfällt.** Es begrenzte `scrollIntoView` der Seite auf
  den iframe. Ein `WKWebView` ist eine eigene Rollansicht, die das Formular nicht mitrollt.
  Beobachtet beim Rollen, nicht mit einem Sprung aus dem Inhaltsverzeichnis gemessen.
- **Ein unverändertes Feld „Ausgabeordner“ schreibt nichts**, auch kein `.quartz-gui/`.
  QuartzControl schrieb bei jedem Verlassen des Feldes.
- **Ein abgelehnter Ordner bekommt einen Satz** (`buildServer.exportDirInvalid`), nicht die
  Meldung von zod.
- **Die Dauer des Builds hat ein Dezimalkomma** („12,1s“). QuartzControls `toFixed` schrieb immer
  einen Punkt.
- **Fertig und abgelehnt werden angesagt.** In QuartzControl war die Ergebniszeile still.
- **Die Server-Einstellungen bleiben im Speicher je Projekt** (`BuildServerMemory`), wie
  `useStickyState`, nicht auf der Platte.

**Nicht gemessen:**
- ein Server mit `remoteDevHost` (Tunnel);
- ein fremder Server aus dem Terminal in der Liste;
- „Ordner öffnen“ und „Auswählen“, weil beide den Finder bzw. das Ablagefenster öffnen;
- VoiceOver.

### Konfiguration: Website, ⌘S und die Frage beim Verlassen

Vorbild `ConfigEditor/index.tsx` mit `ContentFolder`, `ProjectImage` und `SiteSettings`, dazu
`state/saveCommand.ts` und `state/unsavedGuard.tsx`. Neu im Kern:

- **`ProjectImageBox`**, QuartzControls `shared/projectImageBox.ts`: das Projektbild im Kopfbereich
  als eine Layout-Box, an ihrer Klasse wiedererkannt. Gemessen mit
  `scripts/project-image-box-golden.mjs` über 18 Plugin-Listen, verglichen als JSON-Text, also mit
  Schlüsselreihenfolge. Die Gegenproben scheitern: nur doppelte Anführungszeichen erkennen, oder
  `enabled` beim Ersetzen ans Ende stellen.
- **`ContentIndexPage`** („Startseite anlegen“), QuartzControls `createIndexPage`. Welche Notizen
  der Build liest, fragt der neue Helfer `content-files` das globby des Projekts, so wie
  `quartz/util/glob.ts` es aufruft. Fehlt globby, nimmt er QuartzControls Ersatzweg; die Abschrift
  ist per `diff` wortgleich. Die Front Matter schreibt yaml's `stringify` im selben Helfer.
  QuartzControl lud das globby des Projekts in seinen Hauptprozess, hier läuft es in einem kurzen
  Kindprozess. Gemessen mit `scripts/content-index-golden.mjs` über 15 Projekte: globby aus
  gui-test, Ersatzweg, `.gitignore`, verknüpfter Vault, vorhandene `index.md`, Sonderzeichen,
  kaputte Config. Der Test baut sie unter „Gärten-Ü“ nach. Die Gegenproben scheitern: Sortieren
  ohne `numeric` (2 Fälle), oder globby nie finden (die 4 globby-Fälle).

**Aussehen.** Ein gruppiertes `Form`: Content-Ordner, Projektbild, Seiteneinstellungen,
Ausschließen, Statistik, der Verweis auf die Stile. Die Dialoge „Quelle ändern…“ und „Startseite
anlegen…“ sind Sheets. „Speichern“ steht in der Symbolleiste, daneben „Nicht gespeichert“ bzw.
„Gespeichert.“; Fehler beim Speichern stehen oben im Formular.

**Die Frage beim Verlassen** (`App/Shell/UnsavedGuard.swift`). Eine Seite meldet sich mit
`.unsavedChanges(dirty, save:)` beim Wächter ihres Fensters an. Gefragt wird an vier Türen:
Seitenleiste, Link auf einer Seite (`openPage`), Fenster schließen, Beenden. QuartzControl hatte
ein Fenster und fragte an der Seitenleiste und am Weg zur Projektliste. Hier gehen Änderungen beim
Schließen eines Projektfensters verloren, also fragt das Schließen. Die Frage ist ein `NSAlert`
als Sheet am Fenster mit „Abbrechen“, „Speichern“ (wenn die Seite speichern kann) und „Änderungen
verwerfen“ (destruktiv). Ungespeichert zeigt das Fenster zusätzlich den Punkt im Schließen-Knopf
(`isDocumentEdited`).

**Gemessen** in Hell und Dunkel an der gui-test-Kopie und an einem Wegwerf-Projekt:

| Vorgang | Ergebnis |
|---|---|
| Seitentitel geändert | „Nicht gespeichert“ in der Symbolleiste, Punkt im Schließen-Knopf, Ablage ▸ Speichern aktiv |
| Seitenleiste „Plugins“, „Abbrechen“ | bleibt auf Konfiguration, Markierung zurück, Änderung bleibt |
| ⌘S | genau die Zeile `pageTitle` geändert, Snapshot angelegt, Ablage ▸ Speichern wieder grau |
| geändert, ⌘W, „Änderungen verwerfen“ | Fenster zu, Datei unverändert |
| geändert, ⌘Q, „Abbrechen“ | App läuft weiter |
| geändert, ⌘Q, „Speichern“ | Datei geschrieben, App beendet |
| „Startseite anlegen“, Titel „Mein: Garten“, ohne `node_modules` | `title: "Mein: Garten"`, „privat“ (Muster) fehlt, „Teil 2“ vor „Teil 10“, Hinweis auf den Ersatzweg |
| Anbieter „google“, `tagId`, zweites Muster in neuer Zeile, ⌘S | `analytics: {provider: google, tagId: …}`, beide Muster |

**Was beim Bau anders war als gedacht.**
- **Ablage ▸ Speichern erschien nicht.** SwiftUI lässt die Gruppe `.saveItem` in einer App ohne
  Dokumente weg, ob ersetzt, davor oder dahinter (gemessen, macOS 27). Der Eintrag steht jetzt
  hinter „Öffnen“ mit Trennlinie.
- **Die Seitenleiste blieb auf der abgelehnten Seite markiert.** Die Liste hing an einer Bindung
  auf `pageID`; nach „Abbrechen“ änderte sich `pageID` nicht, also wurde nichts neu gezeichnet. Die
  Markierung hat jetzt einen eigenen Zustand, den „Abbrechen“ zurücksetzt.
- **Das Musterfeld hätte Return verschluckt.** Eine Bindung, die bei jedem Tastendruck leere
  Zeilen wegwirft, nimmt die neue Zeile gleich wieder weg. Das Feld hält seinen Text selbst und
  übergibt die bereinigte Liste.
- **macOS 27 stapelt die Knöpfe des Hinweisfensters senkrecht**, „Abbrechen“ unten, obwohl er als
  erster angelegt ist. Die Reihenfolge legt das System fest.
- **Vier übernommene Texte nannten „QuartzControl“** (Projektbild, Kopfbereich). Sie sagen jetzt
  „QuartzHub“.

**Abweichungen von QuartzControl.**
- **⌘S ist grau, wenn es nichts zu speichern gibt.** QuartzControls Menü konnte das nicht.
- **Fenster schließen und Beenden fragen** (siehe oben).
- **Nach dem Speichern liest die Seite die Datei neu** (Regel „Eine Seite besitzt ihr Dokument“).
  QuartzControl übernahm seinen Entwurf als gespeichert.
- **Ein Anbieter, den QuartzHub nicht kennt, bleibt wählbar**, statt als „Keine Statistik“ zu
  erscheinen.

**Nicht gemessen:**
- „Quelle ändern…“ (kopiert oder verknüpft einen Ordner);
- Bild wählen, ersetzen, entfernen, auch das dunkle (Ablagefenster);
- der Schalter „Im Kopfbereich zeigen“ mit Installation von quartz-layout-box (Netz); die
  Listen-Logik dahinter ist golden gemessen;
- VoiceOver.
