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

### Konfiguration: Übersetzungen

Vorbild `ConfigEditor/Localization.tsx`; im Kern war `LocaleFiles` schon fertig (Helfer
`locale-edit`). Ein Umschalter über dem Inhalt wählt den Reiter, je Fenster gemerkt
(`@SceneStorage("config.tab")`). In der Symbolleiste schob er den Inspektor-Knopf in die
Fenstermitte (gesehen), deshalb steht er über dem Formular.

Der Reiter zeigt den Update-Schutz (`.gitattributes` mit `merge=ours` und Treiber) mit „Jetzt
aktivieren“, darunter Sprache, Suche, „N ungespeichert“ und „Speichern“ in einer Zeile, dann je
Eintrag Schlüssel und Feld. Gespeichert wird je Sprache mit dem Knopf daneben, nicht mit ⌘S, wie
in QuartzControl. Gewählte Sprache, Suche und ungespeicherte Einträge bleiben je Projekt im
Speicher (`LocalizationModel.forProject`, wie `useStickyState`); ein Seitenwechsel fragt deshalb
nicht.

**Gemessen** am Wegwerf-Projekt mit `de-DE.ts` und `en-US.ts` aus gui-test, als git-Repository:

| Vorgang | Ergebnis |
|---|---|
| `propertyDefaults.title` geändert, „Speichern“ | genau diese Zeile in `de-DE.ts` geändert, `.gitattributes` mit `quartz/i18n/locales/*.ts merge=ours`, `merge.ours.driver` = `true`, Abzeichen „Update-Schutz aktiv“ |
| geändert, zur Übersicht und zurück | keine Frage; „1 ungespeichert“ und der Text stehen noch, der Reiter auch |

**Abweichungen von QuartzControl.**
- **Einspaltig.** QuartzControl stellte die Einträge ab breitem Fenster zweispaltig; hier ist es ein
  gruppiertes Formular.
- **Ein Satz statt „ließ sich nicht laden“** (`localization.localeLoadFailed`): „konnte nicht
  geladen werden“, nach der Stilregel.
- **Speichern wird angesagt**, erfolgreich oder nicht.

**Nicht gemessen:** ein Eintrag der Art `template` (mehrzeilig, „JS“) mit Syntaxfehler; ein
Sprachwechsel mit ungespeicherten Einträgen (sie werden verworfen, wie in QuartzControl); VoiceOver.

### Plugins: Installiert und die Options-Form

Vorbild `routes/Plugins/Installed.tsx` und `components/PluginOptionsForm`. Die übrigen fünf Reiter
kommen einzeln; bis dahin zeigen sie den Platzhalter.

**Kern.** `OptionFormText` trägt, was die Form über eine Option sagt: Titel, Beschreibung und
Gruppe je Sprache, Beschriftungen der Auswahl, die Suche, den Satz unter einer Option, deren
Bedingung nicht gilt, die Reihenfolge der Gruppen und den Wert, den eine von Hand getippte Option
wird. Dazu `QuartzConfig.siteLanguages` und `PluginRepository` (das „owner/repo“ einer Quelle).
Gemessen mit `scripts/option-form-golden.mjs` gegen QuartzControls eigenen Code:
- 27 Felder aus zwei Schemas, die beide Normalisierer lesen;
- 19 Werte als eine Zeile;
- 37 getippte Werte, darunter `0x10`, ` true `, `[1, 2` und Ziffern anderer Schriften;
- 9 Configs für die Sprachen und 18 Quellformen.

Sechs Gegenproben schlugen an (Reihenfolge der Gruppen, Trimmen, `@`, an/aus, Kleinschreibung,
Beschriftungen).

**Abweichung.** Ein getipptes `Infinity` bleibt Text. QuartzControls YAML-Schreiber schrieb `.inf`;
der Weg zum Helfer `yaml-edit` ist JSON, und das kennt keine Unendlichkeit. Die Option wäre als
`null` angekommen.

**Form.** Sie besteht aus `Section`s im gegliederten `Form` des Inspektors. Gruppen falten über
`DisclosureGroup`, verschachtelte Objekte stehen als Stapel in ihrer Zeile. Textfelder schreiben
beim Verlassen und bei Return, wie QuartzControl beim `blur`.

Gefunden in der laufenden App: Das Feld verwarf seinen Entwurf sofort nach dem Schreiben und zeigte
einen Augenblick den alten Wert. Beim nächsten Verlassen schrieb das Textfeld diesen alten Wert
zurück. Gemessen: Ein geleertes `condition` stand nach einem Zeilenwechsel wieder als „has-tags“ in
der Datei. Jetzt bleibt der Entwurf stehen, bis die Seite den neuen Wert liefert. Derselbe Ablauf
(eintragen, leeren, Zeile wechseln) lässt die Datei byte-gleich.

**Liste.** Die Reihenfolge folgt Quartz: Komponenten je Position nach `layout.priority`,
Seitentypen und die übrige Verarbeitung je nach `order`, eigene Frames ohne Reihenfolge.
Umsortiert wird auf drei Wegen zu einer Funktion:
- `onMove` mit der Maus;
- Anordnen ▸ Nach oben/Nach unten (⌥⌘↑/⌥⌘↓), über `focusedSceneValue`;
- dieselben zwei im Kontextmenü und als Bedienungshilfe-Aktion.

Jede Bewegung nummeriert die Gruppe in Zehnerschritten neu, wie in QuartzControl. Gemessen an der
gui-test-Kopie:
- ⌥⌘↓ und ⌥⌘↑ stellen die zwei Zeilen wieder her;
- ein dritter Eintrag mit Lücke ging dabei von 70 auf 60.

Bei aktivem Filter ist das Umsortieren aus, und das Menü ist grau. Schreiben geht wie in
QuartzControl durch eine Schlange: Die Änderung steht sofort im Speicher, die Schreibvorgänge
folgen einander, und nur der letzte liest die Datei neu. Jedes Schreiben nimmt einen Snapshot
`configChange`, Entfernen einen `pluginChange`.

**Kleinstes Fenster.** Sechs Reiter mit fester Breite drückten das Fenster bei 900 pt breiter als
den Bildschirm. Der UI-Test fand die Seitenleiste nicht mehr („Unable to find hit point“). Reicht
der Platz nicht, werden die Reiter jetzt ein Menü (`ViewThatFits`).

**Offen bis zur Seite Layout.** „Im Layout-Editor“ und „Auf der Bühne zeigen“ öffnen die Seite
Layout, wählen dort aber noch nichts aus. Die Widgets der Layout-Box (Snippet-Datei, Bild einfügen,
Platzhalter) und die Gründe „wirkt nicht“ für Navigationen, Layout-Box und Formulare kommen mit
ihren Reitern. Bis dahin ist `file` ein Textfeld.

Die Prüfung, ob ein Plugin ein Update hat (`git ls-remote` je Eintrag), läuft wie auf der Übersicht
nicht mit `-QHNoUpdateCheck YES`.

### Plugins: Marktplatz

Vorbild `routes/Plugins/Marketplace.tsx` und `components/ReadmeText.tsx`. Der Katalog kommt aus
`Marketplace` (Phase 3) und gilt fünfzehn Minuten für alle Fenster (`AppServices.marketplace`).
Gefragt wird erst, wenn der Reiter erscheint, nicht mit der Seite. Der Token hebt nur das
Anfragelimit und kommt vor jeder Anfrage aus den Verbindungen.

**README ohne HTML.** `ReadmeText` liest die Markdown-Formen einer Plugin-README (Überschriften,
Absätze, Listen, Codeblöcke, Tabellen, Code, Fett, Links) in Blöcke, die die App nativ zeigt; HTML
verliert seine Klammern, ein Bild sagt seinen Alt-Text. Gemessen mit
`scripts/readme-text-golden.mjs`: QuartzControls Komponente liefert React-Elemente, das Skript
liest sie in eine neutrale Form zurück. Verglichen werden
- die sechs READMEs der Plugins von gui-test,
- 20 Ränder (Leerzeichen anderer Schriften, U+2028, CRLF, offene Kommentare und Tags, Links aller
  Arten, die Grenze von 4000 Zeichen je Absatz),
- 400 Zufallstexte mit festem Startwert.

Alle 426 stimmen. JavaScripts `\s`, `.` und `$` stehen ausgeschrieben im Muster, denn ICU versteht
sie anders (gemessen mit NSRegularExpression gegen Node): `\s` trifft U+0085, aber nicht U+FEFF;
`.` trifft weder U+000B noch U+0085; `$` trifft auch vor einem letzten Zeilenende. Zwei Gegenproben schlugen an: `.` mit U+2028 bei 8 von 426, `trim` ohne U+00A0 bei 42.

**Preis.** Eine README von 256 KB aus lauter offenen Links unter der Absatzgrenze braucht in Swift
1,4 s (Debug-Bau), in Node 70 ms; ICU sucht langsamer zurück als V8. Echte READMEs sind schnell,
alle 426 zusammen 0,11 s. Deshalb liest der Inspektor die README außerhalb des Main-Threads und
zeigt bis dahin „Lade die Beschreibung…“. Ein einzelner Absatz von 120 KB dieser Art ist dank der
Grenze in 9 ms Text; ohne sie 22 s (`overlongParagraphIsPlainText`).

**Liste.** Die Suche und die Teilung in Plugins (Markierung `quartz-plugin`, nicht archiviert) und
„Weitere Repositories“ stehen im Kern (`MarketplaceResult.split`), nach Sternen und sonst in der
Reihenfolge des Katalogs. Der Satz, was die weiteren Repositories sind, steht als Zeile in der Liste,
nicht im Abschnittskopf, der ihn auf eine Zeile kürzte.

**Installieren** geht über `PluginsModel.add` (`quartz plugin add` mit Snapshot `pluginChange`) und
wartet zuerst auf die Schreib-Schlange von Installiert: Der CLI schreibt die Config, und ein
später gespeicherter Stand hätte den neuen Eintrag wieder entfernt.

Angesehen gegen GitHub (nur lesend) an der gui-test-Kopie, Hell und Dunkel: 47 Plugins im Katalog,
44 davon im Projekt, eine README mit Codeblöcken und Links, „Weitere Repositories“ auf- und
zugeklappt, Katalog neu geladen. Nicht ausgelöst: Installieren und Hinzufügen, das wären npm- und
git-Läufe ins Netz. Der UI-Test öffnet den Reiter nicht, weil er ohne Netz läuft.

Geändert: Der leere Inspektor sagte „Wähle links ein Plugin“. Der Hinweis „nicht erreichbar“
verwies auf einen GitHub-Token „in den Einstellungen“, wo QuartzHub ihn nicht hat, und hatte vier
Sätze.

### Die Vorschau neben den Plugin-Editoren

Vorbild `components/SitePreview.tsx`, `utils/sitePreview.ts`, `data/componentSelectors.ts` und
`electron/main/services/previewHighlight.ts`. Navigationen, Zusätzliche Inhalte, Mehrsprachigkeit
und Formulare zeigen sie unter ihrer Liste (`EditorPreview`).

**Kern.** Gemessen mit `scripts/site-preview-golden.mjs` gegen QuartzControls Code:
- welcher Selektor einen Eintrag findet (`ComponentSelectors`), 14 Einträge mit Kopien und Klassen;
- ob ein Bericht des Markierungsskripts gilt, 21 Fälle;
- der Zoom-Ausschnitt, 40 Fälle;
- die nächste Seite mit dem Eintrag und welcher Satz unter der Vorschau steht.

Seitenpfade werden nach Bytes verglichen, nicht mit `==` („Über“ in NFC und NFD sind zwei Seiten,
wie in Node). Das Markierungsskript selbst ist QuartzControls `previewScript`, wie dessen Bundle es
übersetzt. Das Golden-Skript schreibt es als `PreviewScript.swift`, und ein zweiter Lauf lässt die
Datei byte-gleich. Drei Gegenproben schlugen an: Vergleich mit `==`, Zoom-Grenze 2,0, Kopien nicht
ausgenommen.

**Skalieren.** Die Website wird in echter Gerätebreite gerendert (Desktop mindestens 1280 px) und
auf die Spalte verkleinert, wie QuartzControls iframe mit CSS-Transform. Nativ hängt die WKWebView
in einer Ansicht, deren `bounds` der Ausschnitt der Website sind. AppKit zeichnet sie dann skaliert
und rechnet Klicks zurück, und die Web-Ansicht behält ihre Größe, also bleibt auch der Viewport der
Website gleich. In der laufenden App: 1280 px gezeigt mit 73 %, scharf; der Zoom auf eine
Navigation zeigt sie mit 100 %.

Das Skript meldet sich mit `parent.postMessage`. In der Web-Ansicht ist die Website das oberste
Fenster, `parent` ist also die Seite selbst; ein Nutzerskript reicht die Meldung als Text an
QuartzHub weiter, und `PreviewMarks.report` prüft jedes Feld. Gesehen: Markierung und Abdunkeln,
„Markiert: „Akkordeon #1““. Nach einer gespeicherten Änderung lädt Quartz' eigener Live-Reload die
Seite neu, und die Markierung steht wieder.

### Plugins: Navigationen

Vorbild `routes/Plugins/Navigations.tsx`, `navigationVariants.ts`, `instanceClass.ts`,
`navigationRoot` in `optionFormExtras.ts` und der Teil von `LayoutEditor/utils.ts`, den die Editoren
mit der Bühne teilen (`LayoutEntries`). Gemessen mit `scripts/navigations-golden.mjs`, mit dem
Schema von quartz-navigations aus gui-test:
- 3290 Gründe „wirkt nicht“ (zehn Varianten, sieben Werte für `mobile`, alle Optionen);
- 52 Form-Einstellungen mit Leitabschnitt, Sätzen und dem, was nur gesetzt erscheint;
- 22 Namen als Klasse, 12 Einträge und 11 Duplikate mit Neunummerierung.

Drei Gegenproben schlugen an (Slug ohne NFKD, `columns` mit Wirkung, Kopie behält `id`).

**Abweichung.** Ein Eintrag an einer Position, die die Bühne nicht kennt, ließ QuartzControls
`duplicateAfter` werfen; `LayoutEntries` antwortet `nil`. QuartzControls `getLayout` zählt auch eine
Liste als Layout-Block (`typeof` sagt `object`); das ist übernommen.

**Oberfläche.** Liste und Vorschau stehen untereinander in einem `VSplitView`, die gewählte
Navigation im Inspektor: an/aus, die Variante als Kacheln, dann die Optionen dieser Variante. Was
bei ihr nicht wirkt, steht ausgegraut mit den Varianten, bei denen es wirkt. „Neue Navigation“
öffnet dieselben Kacheln in einem Popover. Alles schreibt über die Schlange von Installiert.

Gemessen an der gui-test-Kopie, Hell und Dunkel:
- Variante Baum und zurück zu Akkordeon: eine Zeile, danach byte-gleich;
- Duplizieren nummeriert die linke Seitenleiste neu (vier Prioritäten) und hängt die Kopie mit
  `className: nav-menue nav-menue-2` an;
- Entfernen über den Dialog nimmt nur die Kopie, die Neunummerierung bleibt (wie in QuartzControl);
- eine neue Leiste steht im Kopfbereich mit Priorität 80 und `nav-bar`, und nach dem Neubau
  markiert die Vorschau sie;
- „Alle Optionen in der Plugin-Liste“ öffnet Installiert mit der Navigation im Inspektor.

Gefunden in der laufenden App: „Auf der Bühne zeigen“ und „Alle Optionen …“ standen nebeneinander
und wurden im Inspektor abgeschnitten; jetzt stehen sie untereinander.

### Der Code-Editor, zum ersten Mal gebraucht

`App/Components/CodeEditor.swift` baut die Entscheidung aus 4b. Es ist NSTextView mit TextKit 2 und
den Zeilennummern aus dem Messgeschirr (eine Nummer je Absatz, ein umbrochener Absatz behält eine).
Dazu kommen die Suchleiste des Systems, Hell und Dunkel über dynamische Systemfarben und das
Einfügen an der Cursorstelle, nur wenn der Nutzer einen Cursor gesetzt hat (sonst ans Ende, auf
eine eigene Zeile, wie in QuartzControl). Gefärbt wird je Zeile durch `CodeColors` im Kern (HTML und
Markdown; CSS und SCSS kommen mit Stile). Regeln laufen nie über einen Zeilenumbruch. Ein
HTML-Kommentar oder ein Codeblock über mehrere Zeilen wird deshalb nur an seinen Marken gefärbt,
wo CodeMirror das ganze Dokument parste.

**Messung.** Eine Zeile in der Mitte von 5.000 Zeilen färben, 2.000-mal: zusammen 0,5 s für HTML
und Markdown. Die Gegenprobe (jede Regel über das ganze Dokument) lief nach zehn Minuten noch und
wurde abgebrochen. Die Schranke im Test liegt bei 5 ms je Zeile, weit über der Messung.

**Zwei Fehler, gefunden beim Klicken.** Beide sind behoben, und ihr Grund steht im Code:
- Die Einfügung kam nicht an, solange der Editor sie als Binding bekam. Eine Ansicht, deren `body`
  ein Binding nur weiterreicht, rechnet SwiftUI nicht neu, also lief `updateNSView` nie. Jetzt geht
  die Einfügung als Wert hinein.
- Danach lief die Einfügung, verschwand aber wieder. Sie geschah mitten in `updateNSView`; SwiftUI
  verwirft das Zurückschreiben ins Binding dort, und das nächste Update setzte den alten Text.
  Jetzt fügt der Editor einen Takt später ein.

Gemessen an der Datei auf der Platte: `{{title}}` steht nach „Snippet speichern“ an der
Cursorstelle.

### Plugins: Zusätzliche Inhalte

Vorbild `routes/Plugins/ExtraContent.tsx`, `ExtraContentFiles.tsx`, `layoutBoxes.ts`,
`boxSilenced` und `layoutBoxRoot` in `optionFormExtras.ts` und die Snippet-Felder aus
`PluginOptionsForm/snippets.tsx`. Gemessen mit `scripts/layout-boxes-golden.mjs`, mit dem Schema
von quartz-layout-box aus gui-test:
- 34 Optionssätze, je mit sechs installierten Fassungen für die Frage, wo das Plugin abbricht;
- sechs Umbenennungen eines Schnipsels über 17 Einträge;
- 372 Form-Einstellungen;
- dazu Bildverweise, Ordnernamen und Geschwisterwerte.

Nachgebaut ist auch JavaScripts Spread von Listen und Texten (`{ ...[1] }` ergibt `{"0": 1}`).
`mentionsImage` vergleicht UTF-16-Einheiten wie `includes`: „ü“ und „u + ̈“ sind zwei Namen. Vier
Gegenproben schlugen an:
- `byLang` wird beim Umbenennen nicht nachgezogen;
- `null` bricht nie;
- der Ordnername ohne `trim`;
- Swifts `contains` statt `includes`.

**Oberfläche.** In der Mitte stehen drei Teile untereinander in einem `VSplitView`: die Boxen, die
Dateien hinter ihnen (Schnipsel je Ordner, Bilder, das Projektbild nur lesend) und die Vorschau. Die
gewählte Box steht im Inspektor: an/aus, „Text in der Konfiguration | Datei“ als Kacheln, dann die
Optionen. Was nicht wirkt, steht grau mit dem Grund. Die Options-Form kennt jetzt den Projektpfad.
Ein Feld mit `x-quartz-widget: snippetFile` ist dann eine Dateiauswahl mit „Neu“, „Importieren…“
und „Bearbeiten“. Ein HTML- oder Markdown-Text bekommt „Bild einfügen…“ (ein SVG auf Wunsch als
Code über `InlineSvg`), und wo das Plugin `placeholders` hat, die Liste der Platzhalter. Installiert
benutzt dafür jetzt dieselben Extras ohne Kacheln wie QuartzControl (`OptionRoot.withoutTiles`).
Fragen mit drei Antworten (Ersetzen, Vorhandene verwenden, Abbrechen) sind `Confirm.choose`.

Gemessen an der gui-test-Kopie, Hell und Dunkel:
- Datei → Text → Datei an „Über dieses Handbuch“: Aus einer Markdown-Datei wird der Beispieltext,
  `file` steht grau mit „wirkt nicht“. Zurück mit „Text entfernen“ ist die Config byte-gleich.
- `sidebar-note.en.md` → `sidebar-note.english.md`: Die Datei heißt neu, die Box nennt für `en`
  den neuen Namen. Zurückbenannt ist die Config byte-gleich.
- Neue Box: links, Priorität 50, `layout-box-neue-box`. Duplizieren gibt der Kopie
  `layout-box-neue-box layout-box-neue-box-2` und nummeriert links neu. Zwei gleich benannte
  Boxen heißen „Neue Box #8“ und „#9“. Entfernen über den Dialog nimmt nur die Kopie.
- Snippet bearbeiten: Tippen zeigt „Ungespeichert“. `{{title}}` aus der Liste landet am Cursor,
  „Snippet speichern“ schreibt die Datei. Danach ist die Datei zurückgespielt.

Gefunden in der laufenden App und behoben:
- „Neu“, „Importieren…“ und „Bearbeiten“ neben der Dateiauswahl waren im Inspektor auf je einen
  Buchstaben gekürzt. Dasselbe galt für „Bild einfügen…“ neben „Schließen“ und „Snippet
  speichern“. Beide Reihen stehen jetzt in eigenen Zeilen.
- Die Kachel „Text in der Konfiguration“ trennte das Wort.
- Der Status „… ist gespeichert.“ drückte den Dateinamen auf „side…te.md“.
- Die Platzhalter waren als graue Knöpfe zu breit; jetzt sind sie randlos in der Akzentfarbe.

Nicht gemessen: Importieren und „Bild einfügen…“ mit dem Dateidialog, In den Papierkorb, Ordner
hinter einer Verknüpfung.

### Plugins: Mehrsprachigkeit

Vorbild `routes/Plugins/Multilanguage.tsx` und `multilanguageOptions.ts`. Gemessen mit
`scripts/multilanguage-golden.mjs`, mit dem Schema von quartz-multilanguage aus gui-test:
- 13 Optionssätze, je mit 188 Schritten zusammen: umbenennen, entfernen, veröffentlichen,
  tauschen, ändern, hinzufügen, unverändert zurückschreiben;
- die Gruppen der Einstellungen in beiden Sprachen;
- 24 Code-Prüfungen.

QuartzControl merkt sich in einer WeakMap, aus welchem geschriebenen Eintrag eine Sprache gelesen
ist, damit ein `DE`, das niemand angefasst hat, `DE` bleibt. In Swift ist das ein Feld `readFrom`
am Eintrag, das beim Ändern wegfällt. Die Golden-Datei beschreibt die Schritte deshalb als Schritte
auf den Einträgen, und der Test geht sie auf seinen eigenen nach.

`normalizeCode` nimmt `NSString.lowercased`, nicht Swifts `lowercased()`: Nur das schreibt ein
Schluss-Sigma als „ς“ wie JavaScripts `toLowerCase` (gemessen mit „ΣΟΦΟΣ“). Vier Gegenproben
schlugen an:
- `readFrom` vergessen;
- Swifts Kleinschreibung;
- ein zweiter Eintrag vor seiner Sprache bleibt beim Tauschen stehen;
- die Gruppe ohne Namen nicht zuletzt.

Für den letzten Fall hat das echte Schema keine Felder, deshalb steht ein kleines eigenes Schema
in der Golden-Datei. Eine fünfte Gegenprobe, Sortieren ohne den Platz als Gleichstand, schlug
nicht an: Swifts Sortierung ist in der Praxis stabil, zugesagt ist es nicht, und der Gleichstand
bleibt im Code.

**Oberfläche.** Oben steht der Eintrag mit „Eingeschaltet“ und „Alle Optionen“. Darunter kommt
eine Liste mit zwei Abschnitten: die Sprachen (ziehen, Anordnen ▸ Nach oben/unten mit ⌥⌘↑/⌥⌘↓,
Kontextmenü, Bedienungshilfe-Aktion) und die Gruppen der Einstellungen mit einer Zeile, was sie
gerade sagen. Unten steht die Vorschau. Im Inspektor steht eine Sprache, eine Gruppe (eine Gruppe
aus einem einzigen Objekt zeigt dessen Inhalt mit `switcher.`-Schlüsseln) oder der Überblick.

Gemessen an der gui-test-Kopie, Hell und Dunkel; nach jedem Hin und Zurück war die Config
byte-gleich:
- `en` → `en-GB` schreibt `en-gb` in einer Zeile und behält die Auswahl;
- `de` als Code von English sagt „Diese Sprache gibt es schon.“ und schreibt nichts;
- „Früher“ tauscht die Einträge, ⌥⌘↑ tauscht zurück (das Menü bot für die zweite Sprache nur
  „Nach oben“ an);
- `FR` hinzufügen schreibt `- fr`, Entfernen über den Dialog nimmt es wieder;
- English nicht veröffentlichen schreibt `publishLanguages: [de]`. Deutsch entfernen fragt dann
  „… entfernen und English veröffentlichen?“ mit „Entfernen und veröffentlichen“ (abgebrochen),
  wieder einschalten gibt `[]`;
- `switcher.showCurrent` aus und an.

Gefunden in der laufenden App: Die Code-Spalte brach „EN-GB“ in zwei Zeilen; sie ist jetzt
einzeilig und so breit wie nötig.

### Plugins: Formulare

Vorbild `routes/Plugins/Forms.tsx` mit `FormFieldsEditor.tsx`, `FormText.tsx`, `FormsTexts.tsx`,
`FormsKeys.tsx` und `FormsRelay.tsx`; die Regeln in `formsOptions.ts` (`FormsOptions`, gemessen
mit `scripts/forms-options-golden.mjs`).

**Wo ein Formular eingebettet ist** (`FormUsages`), gemessen mit `scripts/form-usages-golden.mjs`
gegen QuartzControls `shared/formUsages.ts` und `contentService.formUsages`:
- 31 Pfade durch `quartzSlug` und `slugPath`;
- 50 Seiten durch `pageFormUse` (Frontmatter, Codeblöcke, Platzhalter, Inline-Code, CR, U+2028,
  U+0085, NFC und NFD);
- 12 kleine Projekte durch den ganzen Scan, mit und ohne globby, mit verlinktem Vault, einer
  unlesbaren Datei und den Filtern remove-draft und explicit-publish.

Die Frontmatter liest der Helfer `content-files` (`op: parse`) mit dem yaml-Paket, das
QuartzControl nahm, alle Seiten in einem Aufruf. Ein Datum (ein Dokument mit `%YAML 1.1`) wird
dabei `null`: JSON hätte es zum String gemacht, und der Scan hätte ihn als Titel gelesen. Die
Regeln sind von Hand nachgebaut, wo ICU anders liest als V8: `.` hält bei U+0085 an, `(?i)` nimmt
das Kelvin-Zeichen für ein k, Swifts `==` hält „ü“ und „ü“ für gleich. Sieben Gegenproben
schlugen an: Swifts `==`, `(?i)`, das Zählen der unlesbaren Dateien, Swifts Kleinschreibung,
ohne Sortieren, die Filter ohne ihren Schalter und der Helfer ohne die Datumsregel.

Abweichung: QuartzControl zeigte bei einem Scan, der scheitert, die Sätze von „Startseite
anlegen“ („… deshalb ist keine Startseite angelegt“). Der Scan hat eigene Sätze.

**Oberfläche, Teil 1: Liste und Formular.** Oben stehen der Eintrag mit „Eingeschaltet“ und
„Alle Optionen“, das Urteil von quartz-forms (`FormsCLI.check`, 600 ms nach dem letzten Schreiben,
nachdem die Warteschlange leer ist) und die Warnung, wenn eine Seite ein Formular nennt, das es
nicht gibt. Die Liste hat zwei Abschnitte, die Formulare und die Einstellungen für alle. Darunter
steht die Vorschau; sie markiert `form.quartz-form[data-form="<id>"]` und geht über „Zeigen“
(`PreviewGoTo`, neu in `EditorPreview`) auf eine Seite, die das Formular einbindet. Im Inspektor
stehen das Formular in Teilen zum Aufklappen (welche offen sind, gilt für alle Formulare je
Fenster) oder ein Bereich. Jedes Schreiben geht gegen den neuesten Stand des Formulars; ein Wert,
den die Vorlage schon gibt, wird nicht geschrieben. Der Feld-Editor, die eigenen Bereiche
Schlüssel, Texte und Layout-Position und das Relay folgen; bis dahin zeigt „Felder“ den
allgemeinen Listen-Editor, und die Zeile „Relay“ fehlt.

Gemessen an der gui-test-Kopie, Hell und Dunkel; nach jedem Hin und Zurück war die Config
byte-gleich:
- Titel setzen und leeren;
- `kontakt` → `kontakt-neu`: Die Rückfrage nennt `kontakt.md`. „Abbrechen“ schreibt nichts,
  „Kennung ändern“ schreibt eine Zeile, und die Warnung über die unbekannte Kennung erscheint.
  Zurück fragt nicht, weil keine Seite `kontakt-neu` nennt;
- Neues Formular mit „Feedback“: quartz-forms meldet „recipient: das Relay braucht den Namen des
  Empfängers“ an Zeile und Teil. Duplizieren und Entfernen (die Rückfrage sagt „Keine Seite bindet
  es ein.“);
- „Anonym“ ein (dann steht „wirkt nicht“ bei „Seite mitschicken“) und aus;
  `showFingerprint: false` landet unter `encryption`;
- „Kopieren“ beim Codeblock legt die drei Zeilen in die Zwischenablage.

Gefunden in der laufenden App:
- Die Kennung im Hinzufügen-Popover folgte der Vorlage nicht: Das Feld schreibt beim Fokussieren
  seinen Wert zurück, und das zählte als getippt. Jetzt zählt nur ein geänderter Text.
- Der Hinweis darunter war bei „Ziffern…“ abgeschnitten: Das Popover hängt am Kopf eines
  Listenabschnitts und erbt dessen eine Zeile. `.lineLimit(nil)` am Popover behebt das.
- Ein abgebrochenes Umbenennen ließ die neue Kennung im Feld stehen.
- Das rote Problem-Abzeichen war auf einer ausgewählten Zeile kaum lesbar; jetzt ist es gefüllt.

**Oberfläche, Teil 2: der Feld-Editor** (`FormFieldsEditor.swift`, Vorbild `FormFieldsEditor.tsx`).
Die Felder stehen als Zeilen untereinander im Teil „Felder“. Eine Zeile klappt auf und zeigt, was
ihr Typ liest; den Rest zeigt das Schema des Plugins (`fieldVariant`). Umsortieren geht auf allen
Wegen der Konvention: Ziehen (`draggable`/`dropDestination`), die Pfeile, das Kontextmenü,
Anordnen ▸ Nach oben/unten für das offene Feld und die Bedienungshilfe-Aktionen. Die Kennungen der
Zeilen zählen Plätze; die offene Zeile wandert beim Verschieben und Entfernen mit. Solange das
Formular die Felder seiner Vorlage nimmt, sind sie bearbeitbar wie eigene: Die erste Änderung
schreibt die ganze Liste. Neu sind Seitenumbrüche, Bedingungen (`ConditionEditor`) und die Optionen
einer Auswahl.

Gemessen an der gui-test-Kopie, Hell und Dunkel; nach jedem Rückweg über „Felder der Vorlage …
nehmen“ war die Config byte-gleich:
- „Name“ nach unten: Die vier Felder der Vorlage werden eigene, in neuer Reihenfolge;
- `name` → `vorname`, Breite „Halb“ (die Zeile zeigt „· ½“);
- eine Auswahlliste angelegt (`auswahl`, zwei Möglichkeiten) und mit ⌥⌘↑ zweimal vor „Nachricht“
  geschoben. Bei „Nachricht“ „Nur zeigen, wenn … Auswahlliste“ gibt `equals: a`, mit „Möglichkeit 2“
  `equals: [a, b]`;
- ein Seitenumbruch am Ende: quartz-forms meldet „ein Seitenumbruch steht zwischen Feldern, nicht
  am Anfang oder Ende“ an der Zeile und am Teil. Zweimal ⌥⌘↑ nimmt die Meldung weg, die offene Zeile
  wandert mit. Entfernen fragt „Seine Felder gehören dann zum Schritt davor.“;
- „Noch etwas?“ mit der Maus auf die erste Zeile gezogen.

Gefunden in der laufenden App: Name, Typ und Abzeichen in einer Zeile kürzten die Namen in der
Breite des Inspektors auf „Nach…“; der Typ steht jetzt darunter. In drei Spalten waren zwei
Kacheln von „Feld hinzufügen“ abgeschnitten; es sind jetzt zwei Spalten.

**Oberfläche, Teil 3: Schlüssel, Texte, Position.** Zwei Regeln sind dafür in den Kern gekommen,
beide gegen QuartzControls eigenen Code gemessen:
- `FormsOptions.formsUsingKey`, `withoutKey` und `keyNameProblem` aus `FormsKeys.tsx`
  (`forms-options-golden.mjs`, 15 Fälle, die Namensregel aus der Datei gelesen). Drei Gegenproben
  schlugen an: eine geleerte Liste bleibt stehen, ein ausgeschaltetes Formular zählt mit, 65
  Zeichen.
- `LayoutEntries.place` ist `placeComponent` des Layout-Bretts (`navigations-golden.mjs`, 71 Fälle
  auf demselben Brett). Drei Gegenproben: die verlassene Position nicht neu nummeriert, die Gruppe
  ignoriert, ein Eintrag ohne Layout-Block bekommt einen.

Den Bereich „Texte“ füllt der Wortlaut des installierten Plugins (`FormsCLI.texts`); was man
einträgt, wird ohne Trimmen geschrieben. Bei „Schlüssel“ liest das Plugin jeden Schlüssel selbst.
Ein eingefügter Schlüssel wird erst nach dieser Prüfung gespeichert, und zwar nur sein Block.

Gemessen an der gui-test-Kopie, Hell und Dunkel:
- denselben Schlüssel als `zweit` eingefügt: Er wurde geprüft und als `armored` geschrieben, mit
  Fingerabdruck und Nutzer-ID. Beim Entfernen nennt die Rückfrage `kontakt`. Danach war die Config
  byte-gleich;
- `submit` auf „Absenden“ und „Plugin-Wortlaut“: Danach steht wieder `texts: {}`, byte-gleich;
- Position „Nach dem Inhalt“ → „Fußzeile“: Beide Positionen sind in Zehnern neu nummeriert. Die
  Config ist danach aus der Sicherung zurückgeholt, weil der Rückweg die Nachbarn anders nummeriert;
- „Auf der Bühne zeigen“ öffnet Layout.

Nicht gemessen: Schlüssel aus einer Datei (Dateidialog).

Gefunden in der laufenden App: Nach „Plugin-Wortlaut“ kam „Absenden“ zurück, sobald man den
Bereich verließ. Return lässt in SwiftUI den Fokus im Feld (in QuartzControl nahm es ihn weg), und
`CommitField` hielt den Entwurf, solange das Feld fokussiert war; beim Verschwinden schrieb es ihn.
Jetzt fällt ein Entwurf weg, der noch dem alten Wert gleicht, wenn der Wert von außen kommt. Das
betrifft jedes Textfeld der Options-Form.

**Oberfläche, Teil 4: das Relay** (`FormsRelaySection.swift`, Vorbild `FormsRelay.tsx`). Drei
kleine Regeln von dort stehen im Kern und sind aus der Datei gelesen gemessen
(`forms-options-golden.mjs`): der Name eines Empfängers, die Beispieladresse „@example.“ (nur
ASCII wird gefaltet, wie V8 ohne u-Flag) und das Zerlegen der erlaubten Origins (U+0085 ist kein
Leerraum). Gegenproben: 65 Zeichen, ohne Faltung, U+0085 als Leerraum.

Das Hochladen geht durch `AppDeploy`, neu in `App/Shell`: die Verbindungen aus dem Schlüsselbund
und die Adapter für Ordner, SFTP, rsync und FTP. Ein unbekannter SSH-Host wird gefragt wie in
QuartzControls `hostVerifier.ts`, mit der sicheren Antwort zuerst. Dieselbe Fabrik braucht später
„Veröffentlichen“.

Gemessen an der gui-test-Kopie, Hell und Dunkel, ohne Netz:
- die Zeile „Relay“ in der Liste, der Bereich, die Plakette „Relay seit dem Hochladen geändert“
  oben im Formular;
- die Empfänger-Auswahl mit „TestKontakt (Adresse fehlt)“, weil der Schlüsselbund des Testprofils
  keine Adresse hat;
- das Betreff-Präfix wird in `.quartz-gui/forms-relay.json` geschrieben. Die Datei bekommt dabei
  die Form von `{ ...DEFAULT_RELAY, ...file.settings }` wie in QuartzControl: `targetId` steht am
  Ende, `envelopeSender` kommt dazu. Danach ist sie aus der Sicherung zurückgeholt.

Nicht gemessen: Hochladen, Entfernen und Prüfen am Server (Netz, nur auf Ansage), Export in einen
Ordner (Dateidialog), Geheimnisse speichern (sie gingen in den echten Schlüsselbund).

Gefunden in der laufenden App: Die drei Knöpfe unten waren nebeneinander auf „Relay…“, „Als O…“
und „Vom…“ gekürzt; sie stehen jetzt untereinander. Zwölf Texte des Relays nannten QuartzControl
oder sagten „lässt sich“, auch Meldungen des Kerns (`main.relay*`), die hier erscheinen.

### Updates

Vorbild `Updates.tsx`, Dienste `CoreUpdate`, `PluginUpdates`, `GitStatus` aus Phase 3; keine neue
Logik im Kern. Eine Form mit zwei Abschnitten, Kern und Plugins. Die Karte, die auf Snapshots
verwies, ist der Seitenkontext im Inspektor; „Erneut prüfen“ steht in der Symbolleiste.

- **Der Lauf gehört dem Projekt, nicht der Seite** (`UpdatesModel.shared`): Ein Kern-Update läuft
  Minuten (Merge, `npm install`, Aufwärm-Build). In QuartzControl waren Ausgabe und „läuft“ weg,
  sobald man die Seite verließ. Hier zeigt die wieder geöffnete Seite den Lauf noch laufend oder
  sein Ende. Der letzte Satz von `main.updateAlreadyRunning` („Die Ausgabe des Laufs sieht nur, wer
  …“) ist deshalb gestrichen.
- **Dafür gilt das Schloss jetzt für den Prozess** (Nachtrag in `phase-3-dienste.md`, eigener
  Commit): Es hing an der Instanz, und die wieder geöffnete Seite hätte neben dem ersten Lauf einen
  zweiten gestartet.
- **Ein Satz über dem Text von git und npm:** „Das Kern-Update ist abgeschlossen.“ bzw. „… konnte
  nicht abgeschlossen werden.“, auch angesagt. Danach die Konfliktdateien, dann die Ausgabe. Das
  Plugin-Update bekommt keinen solchen Satz: Die CLI endet mit 0, wenn einzelne Plugins scheitern;
  angesagt wird nur „Das Plugin-Update ist beendet.“
- **„Snapshot von vor dem Update öffnen“** setzt `@SceneStorage("backups.open")` und geht zu
  Snapshots; die Seite Snapshots liest es, wenn sie portiert ist. Den Rückweg-Link
  (`markReturn`) gibt es noch nicht.
- **Ohne Netz ansehen:** Unter `-QHNoUpdateCheck YES` (nur Debug) darf git auf dieser Seite nur
  `file://` erreichen (`GIT_ALLOW_PROTOCOL=file`). Die Prüfungen antworten sofort „Nicht prüfbar“,
  ein Lauf endet am Fetch mit „transport 'https' not allowed“ (gemessen: 16 ms gegen eine nicht
  erreichbare Adresse). Plugins mit `file://`-Quelle werden echt geprüft.

Gemessen in Hell und Dunkel, groß und in 1000×700:
- an der gui-test-Kopie: fünf Plugins „Nicht prüfbar“ mit „Aktualisieren“, sechs lokal. Ein Lauf
  scheitert am Fetch, und die Kopie ist danach unverändert: Status, HEAD, Stash, `.git/config`,
  Notiz und Snapshot-Zahl. Es entsteht kein Snapshot, weil sich seit dem letzten nichts geändert
  hat (`SnapshotStore`, wie in QuartzControl), also auch kein Link;
- an einem Wegwerf-Projekt mit zwei Plugin-Repos über `file://`: „Aktuell“ und ein veraltetes
  Plugin; ein Lauf mit Snapshot-Link; Ausgabe und Link nach Übersicht und zurück noch da; der Link
  öffnet Snapshots; ein Merge mit Konflikt zeigt das Banner, ein Lauf darin wird mit
  `main.updateMergeUnfinished` und `README.md` abgewiesen; „Merge abbrechen“ räumt den Merge weg
  und leert die Ausgabe; „Nicht abgeschlossen“ aus einer Notiz mit fehlendem Paket und einer nur
  mit gescheitertem `npm install`.

Nicht gemessen: ein echtes Kern-Update und ein Plugin-Update (`npx quartz plugin install
--latest`). Beide brauchen Netz und passieren nur auf Ansage.

Gefunden in der laufenden App: Die Konfliktliste stand über dem Satz „konnte nicht abgeschlossen
werden“; jetzt kommt erst der Satz. Die Sätze des Katalogs enden mit zwei Zeilenumbrüchen, die im
Kasten als leere Zeilen standen; sie werden für die Anzeige weggelassen. Sieben Texte des Kerns, die
hier erscheinen, sagten „lässt sich“ oder „ließ sich“.

Nachtrag (2026-11-09, beim Portieren von Snapshots): Ein geworfener Fehler stand als
`localizedDescription` im Kasten, bei den Fehlertypen des Kerns also „Der Vorgang konnte nicht
abgeschlossen werden. (QuartzHubCore.SnapshotStore.Failure-Fehler 1.)“. Gemessen mit einem
schreibgeschützten Snapshot-Speicher, an dem der Lauf vor dem Fetch scheitert. Jetzt
`String(describing:)` wie im Rest der App: „Der Projektstand konnte nicht erfasst werden:“ und gits
Grund.

### Snapshots

Vorbild `Backups.tsx`, Dienste `SnapshotStore` und `ContentBackups` aus Phase 3; keine neue Logik
im Kern. In der Mitte ein neuer Snapshot (Name, „Snapshot anlegen“, „Content-Ordner mitsichern“),
die Liste und darunter die beiseitegelegten Content-Ordner. Der offene Snapshot steht im Inspektor:
Vergleich mit dem heutigen Stand, Auswahl einzelner Dateien, „Auch den Projekt-Commit …
zurücksetzen“, Wiederherstellen, Export, Löschen. Ohne Auswahl fasst der Inspektor den Speicher
zusammen (Anzahl, neuester, ältester, Content-Ordner).

- **Das Modell gehört dem Projekt** (`SnapshotsModel.shared`), wie auf Updates: Ein Wiederherstellen,
  das `package.json` zurückholt, ruft `npm install` und kann dauern. Die letzte Meldung gehört
  dagegen dem Besuch, der sie auslöste, und ist beim nächsten Öffnen weg.
- **Der Unterschied einer Datei öffnet sich in einem Sheet**, nicht im Inspektor: Der ist für gits
  Zeilen zu schmal. QuartzControl zeigte ihn im rechten Panel.
- **Der Vault-Satz nach dem Wiederherstellen erscheint.** Der Kern hängt
  `main.snapshotVaultUntouched` an gits Text; QuartzControl zeigte bei Erfolg nur „Wiederhergestellt.“
  und verschluckte ihn. Hier steht er darunter.
- **Der Projekt-Commit wird beim Öffnen eines Snapshots neu gelesen**, nicht nur beim Öffnen der
  Seite. Gemessen: ein Commit, nachdem die Seite offen war, und der Schalter fehlte, bis die Seite
  neu geladen wurde.
- **Export über `NSSavePanel` als Sheet**; den letzten Ordner merkt sich das Panel selbst
  (QuartzControls `saveDialogStartDirectory` braucht es nicht).
- **Die alten Config-Backups werden beim Öffnen übernommen**, wie in QuartzControl
  (`migrateConfigBackups`). Ohne `.quartz-gui/backups/` schreibt das Öffnen nichts (gelesen, nicht
  gemessen: die Umbenennung scheitert zuerst, und ohne Store kopiert `withIndex` nichts).

Zwei Fehler, die das ganze Fenster leerten (Seitenleiste, Symbolleiste und Inspektor eingeschlossen,
der Bedienungshilfe-Baum ohne ein Element, die App ohne Last und ohne Meldung). Eingegrenzt durch
Halbieren der Seite, je mit Gegenprobe:
- **Ein `@SceneStorage`-Schlüssel mit zwei Typen.** Updates führte `backups.open` als `String`, diese
  Seite als `String?`. Schon eine Seite aus nur einem Text blieb leer, auch wenn Updates in diesem
  Lauf nie offen war. Beide als `String?`: Die Seite zeichnet.
- **`fixedSize(horizontal: false, vertical: true)` an umbrechendem Text außerhalb einer
  Scrollansicht.** Der Kopf über der Liste trug es an drei Hinweisen. Ohne es zeichnet die Seite, mit
  ihm bleibt das Fenster leer. In einer `Form` oder `List` (Updates, Inspektor) schadet es nicht.

Gemessen an einem Wegwerf-Projekt (Git, echter Content-Ordner, zwei alte Config-Backups, zwei
beiseitegelegte Content-Ordner, einer davon als Link auf einen Vault), in Hell, in Dunkel und in
1000×700:
- die Übernahme: zwei Config-Backups derselben Woche, einer bleibt („Altes Config-Backup“), wie es
  QuartzControls Ausdünnung will;
- ein Snapshot mit Namen; der Vergleich nach einer geänderten, einer gelöschten und einer neuen Datei
  mit Commit (drei Dateien, richtiger Status, Unterschied nur bei der geänderten);
- „Auswahl wiederherstellen“ mit einer Datei (Frage im Singular, nur README.md zurück, vorher ein
  Snapshot „Vor Wiederherstellung“); „Abbrechen“ ändert nichts;
- „Alles wiederherstellen“ mit dem Projekt-Commit: HEAD zurück auf den aufgezeichneten Commit,
  die neue Datei weg, die gelöschte wieder da, Arbeitsbereich sauber;
- der Link von Updates: Ein Kern-Update ohne Netz legt einen Snapshot an und scheitert am Fetch, der
  Link öffnet genau diesen Snapshot;
- Export als ZIP über das Sheet, Löschen eines Snapshots aus dem Inspektor;
- den Link auf den Vault wieder eingesetzt (der bisherige Ordner geht beiseite), der Schalter aus,
  gesperrt und lesbar, der Vault-Hinweis im Vergleich; „Alles wiederherstellen“ lässt den Vault
  unberührt und sagt es; einen beiseitegelegten Ordner gelöscht (die Frage nennt die Größe).

Gefunden in der laufenden App außerdem: die zwei Wiederherstellen-Buttons nebeneinander waren im
Inspektor abgeschnitten, jetzt untereinander; ein falscher SF-Symbolname (`folder.badge.clock`, gibt
es nicht). Texte: zwei sagten „lässt sich“, „Wähle links“ stimmt mit dem Inspektor nicht mehr,
„Datei(en)“ ist jetzt ein Plural, und der Hinweis unter „Neuer Snapshot“ hatte drei Sätze.

Nicht gemessen: ein Wiederherstellen, das `package.json` zurückholt und dann `npm install` ruft
(Netz).

### Git-Sync

Vorbild `GitSync.tsx`, Dienste `GitStatus`, `Sync`, `GitHubAPI` und für „Merge abbrechen“
`CoreUpdate.abort` aus Phase 3; keine neue Logik im Kern. Eine gruppierte Form: Stand des
Repositorys, das Repository auf GitHub (nur ohne `origin`), der Sync, zuletzt die Liste der
geänderten Dateien. Die Liste steht unten, weil sie bis zu 500 Zeilen lang wird und den Sync sonst
aus dem Fenster schöbe; in QuartzControl stand sie in der Statuskarte. „Aktualisieren“ ist in der
Symbolleiste. Der Inspektor zeigt den Kontext der Seite; auszuwählen gibt es nichts.

- **Das Modell gehört dem Projekt** (`GitSyncModel.shared`), wie auf Updates: Ein Push oder Pull
  spricht mit einem anderen Rechner. Gemessen: die Seite während eines Pushs verlassen und wieder
  geöffnet, „Push läuft…“ steht noch da. Das Ergebnis des Laufs bleibt; der Satz nach „Merge
  abbrechen“ gehört dem Moment und geht mit dem nächsten Schritt (Aktualisieren, Sync, erneutes
  Öffnen), wie QuartzControls `abortNote`.
- **Commit und Nachricht je Fenster** (`@SceneStorage("sync.commit")`, `"sync.message"`), wie
  QuartzControls `useStickyState`.
- **Der Satz nach „Repository anlegen“ steht beim `origin`**, nicht in der Karte: Die verschwindet
  mit dem `origin`, das sie gerade gesetzt hat. In QuartzControl ging die Erfolgsmeldung so mit der
  Karte unter.
- **Die Ausgabe-Box ist ein gemeinsamer Baustein** (`App/Components/RunOutput.swift`, mit
  `OutcomeTitle`), aus Updates herausgezogen.

Gemessen an einer APFS-Kopie von gui-test, deren `origin` auf ein lokales Bare-Repository zeigt (kein
Netz, nichts erreicht GitHub), in Hell, in Dunkel und in 1000×700:
- Push mit eigener Nachricht: 89 Änderungen in einem Commit mit dieser Nachricht, das Remote auf
  demselben Commit, danach „Keine lokalen Änderungen“ und „Auf dem Stand des Remotes“;
- ein Commit am Remote, nach `git fetch` „1 Commit noch nicht geholt“; Pull mit einer lokalen Datei:
  Merge-Commit, die Zeile vom Remote im README;
- ein Konflikt (dieselbe Zeile lokal und am Remote): „Fehlgeschlagen.“, „1 Konflikt“, das Band
  „Ein Merge ist angefangen …“ mit „Merge abbrechen“; der Abbruch räumt das Band ab, sein Satz steht
  darunter;
- ohne `origin`: die Karte „Repository auf GitHub anlegen“ ohne Token gesperrt und lesbar, Name
  vorbelegt, die drei Buttons gesperrt; die Warnung zum Pull-Branch auf einem anderen Branch als
  `v5`; detached HEAD mit Hinweis und ohne Warnung; Commit aus mit seinem Hinweis;
- ein unlesbarer Index (`chmod 000 .git/index`): der Lesefehler mit gits Text, die Buttons offen
  („kann nicht sagen“ ist nicht „nein“);
- ein Remote mit einem `pre-receive`-Hook, der 8 s wartet: „Push läuft…“ mit gesperrten Buttons;
  der erste Push eines Branchs ohne Upstream legt ihn an;
- ein Ordner ohne `.git`: „kein Git-Repository“, die Buttons gesperrt mit Hinweis, und das Öffnen
  legt kein `.quartz-gui/` an.

Texte: zwei sagten „lässt sich“, zwei Hinweise hatten drei Sätze, und die Einzahl von
`gitSync.commitHint` hieß „Die 1 lokale Änderung wird committet.“

**Befund, nicht behoben, beide Apps: Ein abgebrochener Merge nach einem Pull löscht den Content-Ordner
im Arbeitsbereich.** `quartz sync` nimmt den Content-Ordner vor dem Pull weg (`stashContentFolder`)
und legt ihn danach zurück; `git pull --autostash` hält dazwischen sein Fehlen als Löschung aller
Content-Dateien fest. Scheitert der Pull an einem Konflikt, bleibt dieser Autostash am Merge hängen,
und `git merge --abort` spielt ihn ein („Applied autostash.“): Alle Content-Dateien sind von der
Platte gelöscht, im Repository nur als Änderung. Gemessen an der Kopie (228 Löschungen nach dem
Abbruch, Zeitstempel von Pull und Abbruch getrennt) und mit reinem git nachgestellt. Ein weiterer
Sync mit Commit würde die Löschung committen und per Force-Push hochladen (gefolgert, nicht
gemessen). QuartzControl kennt
`autostash` nirgends; der Abbruch ist derselbe wie auf Updates.

Wie in QuartzControl holt die Seite nichts vom Server: „Auf dem Stand des Remotes“ heißt „auf dem
Stand des letzten Fetch“ (gemessen: ein Commit am Remote, die Seite blieb grün bis `git fetch`).

Nicht gemessen: Push mit Token zu GitHub, „Repository anlegen“ (Netz) und ein Content-Ordner als
Vault-Link beim Sync.

### Stile: Farben ohne Browser (`CssColor`)

- **Was QuartzControl den Browser fragte, fragt QuartzHub `CssColor`.** Die Stile-Seite las jede
  Farbe über `fillStyle` eines Canvas (`probeColor` in `variableGraph.ts`): ob ein Wert eine Farbe
  ist, welches Hex der Farbwähler bekommt, welches Alpha dazu. `CssColor` ist ein Leser für CSS
  Color 4 in Swift: Hex, Namen, `rgb()`, `hsl()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`,
  `color()` in allen Räumen, `color-mix()` mit Farbton-Methoden und `calc()` in den Kanälen (die
  Themes schreiben `hsl(var(--h), calc(var(--s) * 1.01), …)`, und nach dem Einsetzen bleibt
  `calc()` stehen).
- **Gemessen gegen Chrome:** `scripts/css-color-golden.mjs` lässt QuartzControls `variableGraph.ts`
  in Chrome laufen (playwright-core aus QuartzControl) und hält je Wert fest, was Canvas daraus
  macht, `cssColorToHexAlpha`, `isDisplayableColor` und das Pixel über Weiß und über Schwarz. Die
  Werte sind jeder helle und dunkle Wert der Variablen-Graphen aus `Fixtures/variable-graph`
  (gui-test, mit dem Theme minimal, minimal allein, die erfundenen Ränder), jeder davon auch so,
  wie QuartzControl ihn auflöst, die Paletten von gui-test und Example und erfundene Ränder: 1044
  Werte, 391 davon Farben. Alles gleich, die Pixel auf ±2.
- **Was Chrome anders rechnet, als man denkt:**
  - `rgb()`, Hex und Namen hält Chrome in 8 Bit je Kanal, Alpha auch: `rgba(255, 0, 0, 0.5)` mit
    Blau gemischt hat das Alpha 0,75098 (die Mitte von 128/255 und 1). `hsl()` und `hwb()` dagegen
    mischt es ungerundet: `hsl(0, 0%, 15%)` in `color-mix()` hatte die Helligkeit von 15 %, nicht
    die von 38/255.
  - `hsl()` und `hwb()` rechnet Chrome in 32-Bit-Float nach der Formel aus CSS Color 4:
    `hsl(254, 75%, 50%)` ist dort #4c20df, in Double #4d20df (0,2999998 gegen 0,3, mal 255).
  - Das Alpha in `rgba()` schreibt Chrome mit zwei Nachkommastellen, wenn die dieselben 8 Bit
    ergeben, sonst mit drei (`#fff8` ist 0,533). Eine Mischung in sRGB, `hsl` oder `hwb` kommt als
    `color(srgb r g b / a)` mit sechs gültigen Stellen zurück, in Exponentenform als `1.00000e-7`.
  - Ohne `in` mischt `color-mix()` in oklab. Ein Kommentar vor dem Wert macht ihn ungültig, einer
    zwischen den Argumenten nicht.
- **Übernommen, nicht behoben:** QuartzControl setzte das Canvas zuerst auf `#010203` und las eine
  unveränderte Antwort als „keine Farbe“. `rgb(1, 2, 3)` ist dort also keine Farbe, und hier auch.
- **Nicht gelesen**, obwohl Chrome sie liest: Systemfarben (`Canvas`, `ButtonText`; ihr Wert ist
  der der Plattform) und relative Farben (`rgb(from red r g b)`). Kein Theme im Golden benutzt sie;
  der Test nennt sie einzeln.
- **Der Farbfleck** malt mit `CssColor.srgb`: die Farbe in sRGB, außerhalb des Raums ungekappt, damit
  ein Display-P3-Bildschirm zeigt, was die Website zeigt. Der Test kappt wie Canvas und vergleicht.
- Gegenproben (18, jede lässt einen Test scheitern; vier waren erst ungefangen und bekamen ihren
  Fall: Farbton-Methode „longer“, „increasing“, „decreasing“, Alpha über 1 in `oklch()`).

### Stile: Variablen auflösen (`VariableResolve`)

- **Der Rest von `variableGraph.ts`, dazu `swatch.ts`:** Wert heute, Wert ohne die eigene
  Änderung, die Kette der Aliase (höchstens 20 Schritte, Halt bei einem Kreis), das Literal am Ende
  mit eingesetzten Verweisen (`hsl(var(--h) …)`), Herkunft, Gruppe, „ist eine Farbe“ in beiden
  Fragen (ohne und mit der eigenen Änderung), der Grund, auf dem ein Farbfleck liegt. Die eigenen
  Änderungen behalten die Reihenfolge der Seite: In JavaScript behält ein Objekt sie, und die Liste
  der bekannten Variablen folgt ihr.
- **Gemessen gegen QuartzControls Code in Chrome:** `scripts/variable-resolve-golden.mjs`, zehn
  Kontexte aus den Graphen von `Fixtures/variable-graph` (gui-test, mit minimal, minimal allein, die
  Ränder, ein eigener Ausgabeordner, viele Build-Dateien, kein Graph), den Paletten von gui-test und
  Example und eigenen Änderungen jeder Art: geänderte Farbe, nur hell, eigene Variable ohne
  Grundlage, Alias, Kreis, eingebetteter Verweis mit und ohne Fallback, geleertes Paar, eine Farbe
  über einem Wert, der keine ist, Verweise neun Ebenen tief. 4127 Zeilen, je Modus Wert, Grundwert,
  Kette und Literal, dazu 32 getippte Werte. Alles gleich.
- Gegenproben (21, 20 fangen; vier waren erst ungefangen und bekamen ihren Fall: ein `var()` mit
  Fallback und etwas dahinter, die Tiefengrenze beim Einsetzen und bei Fallback-Ketten, eine
  Farbe über einem Theme-Wert, der keine ist). Ungefangen bleibt die Tiefengrenze in
  `resolvedValue`: Die von `substituteVars` greift eine Ebene früher, die zweite ist eine doppelte
  Vorsicht aus QuartzControl.

### Stile: Woher die Schriften kommen (`FontDelivery`, `GoogleFontList`)

- **Die Schrift-Logik des Reiters Basis:** `fontDelivery.ts` (welche drei Lader eine Webschrift
  holen: Quartz selbst, das Plugin quartz-fonts, ein Community-Theme; die zwei Schalter; „Google,
  aus dem Projekt“ auf dem Weg hinein und hinaus), `primaryFamily` und `summarizeFaces` aus
  `fontSpec.ts`, `fontBuildState` aus `previewFonts.ts`, die fertigen Stylesheets aus `cssFixes.ts`,
  dazu `activeThemeIdOf` und `familyOf` der Seite.
- **Gemessen gegen QuartzControls Code:** `scripts/font-delivery-golden.mjs` lädt die Dateien in
  Node (sie brauchen keinen Browser) und zeichnet 254 Configs auf: die von gui-test und Example und
  erfundene über alles, was etwas entscheidet (`fontOrigin` fehlend, Google, lokal, unbekannt;
  `cdnCaching` fehlend, an, aus; das Fonts-Plugin an, aus, mit eigenem `fontOrigin`, zweimal; ein
  Theme mit und ohne seine Schriften, aus, mit einer Zahl als Theme, zwei Themes). Je Config die
  Lader, beide Schalter in beide Richtungen, hinein mit sieben Stylesheet-Anfängen und hinaus, und
  der Stand der Schriften mit vier Mengen von Schnitten und drei Antworten auf „gibt es einen
  Build“. Alles gleich, die Configs mit Schlüsselreihenfolge.
- **Die Liste der Google-Schriften** (1959 Familien vom 2026-11-05) schreibt dasselbe Skript aus
  QuartzControls `src/data/googleFonts.ts` nach `GoogleFontList.swift`, als eine Zeichenkette mit
  Tabulatoren, die beim ersten Gebrauch zerlegt wird.
- Gegenproben (16, jede lässt einen Test scheitern).

### Stile: der Rahmen und Basis

- **Ein Modell für vier Reiter** (`StylesModel`, QuartzControls `Styles/index.tsx`): Config, eigene
  Variablen, `custom.scss`, die Entwürfe der Stylesheets und der Variablen-Graph. Die vier Reiter
  schreiben in zwei Orte, also überlebt ein Entwurf den Wechsel des Reiters, und „Speichern“ (⌘S)
  schreibt alles, was `dirty` zählt, egal welcher Reiter vorn ist: erst `custom.scss` als Ganzes,
  dann die übrigen Stylesheets, dann die Config samt Google-Schriften, zuletzt die Variablen. Ein
  Entwurf von `custom.scss` oder `_quartzcontrol.scss`, unter dem etwas anderes geschrieben hat,
  geht nur vom Reiter „Eigenes CSS“ aus. Gebaut ist jetzt Basis; die drei anderen Reiter zeigen bis
  zu ihrem eigenen Commit den Platzhalter.
- **Basis** wie dort: Font-Quelle, drei Schriftfelder mit Vorschlägen (die 1959 Google-Familien
  oder, bei „lokal“, die Familien des Projekts, über `textInputSuggestions`), die Hinweise auf
  andere Schreibweise, unbekannte Namen, Theme und eigene Variable; die Auslieferung mit beiden
  Schaltern und dem Stand der Schriften; bekannte Konflikte; Import einer Schriftdatei; ungenutzte
  Schriften; die Farben je Modus. Der Farbwähler ist der des Systems (`ColorPicker` mit Alpha) und
  schreibt `#rrggbb` oder `rgba()`; in QuartzControl konnte das HTML-Feld kein Alpha und behielt es
  deshalb neben dem Hex.
- **Die Sätze der Seite** (Speicherfehler, was das Speichern nebenbei tat, „Umstellen“) stehen als
  erste Abschnitte im Formular des Reiters, in seiner Flucht. Darüber gestellt waren sie breiter als
  das Formular, und mit `fixedSize(vertical:)` am Text des Umstellens blieb das ganze Fenster leer
  (die Regel aus den Konventionen, hier ein zweites Mal gesehen).
- **Bei 1000×700 werden die Reiter zum Menü**, wie bei Plugins: Als Segmente schoben sie das
  Fenster über seinen Rahmen, Seitenleiste und Inspektor waren angeschnitten (gesehen).
- **Gemessen** an Kopien von gui-test und Example, Hell und Dunkel, 1400×860 und 1000×700:
  - Eine Farbe ändern und mit ⌘S speichern: In der Config ändert sich nur diese Farbe (dazu die
    Pfade der Frames, die `ConfigFile.write` auf den Ordner der Kopie setzt), die Stylesheets
    bleiben gleich, Google wird nicht gefragt (die Anfrage ist dieselbe, alle Dateien da).
  - Theme minimal und Fonts-Plugin an: Das Band zählt 9 von 9 Farben und 3 von 3 Schriften, die
    Felder sind abgeblendet, „THEME“ steht an den Farben, die Lader sagen Quartz und Plugin.
  - „Fix anlegen“ legt `custom/fix-heading-fonts.scss` an, nimmt sie in die Ladereihenfolge und
    wechselt zu „Eigenes CSS“.
  - Import einer WOFF2: Familie aus dem Dateinamen, Gewicht 100 900 und kursiv aus der Datei,
    danach unter „Ungenutzte Schriften“; Entfernen fragt und nimmt Datei und Regel weg.
  - Ein Projekt in der Form von 1.0 (Blöcke in custom.scss): Der Hinweis erscheint, „Jetzt
    umstellen“ legt zuerst einen Snapshot `styleMigration` an, danach ist `_quartzcontrol.scss`
    byte-gleich mit der des Originals.
- **Nicht gemessen:** eine neue Google-Schrift speichern (holt bei Google, braucht Netz), die
  Schalter für die Auslieferung speichern (holt oder entfernt die Google-Dateien), ein
  Speicherfehler mitten im Ablauf.
- **Nebenbefund, nicht behoben (beide Apps):** Wird ein Stylesheet außerhalb der App gelöscht und
  bleibt seine Zeile in der Ladereihenfolge, dann legt „Fix anlegen“ (allgemein: ein Stylesheet
  gleichen Namens anlegen) es ein zweites Mal in die Reihenfolge, mit dem Namensraum `…-2`.
  QuartzControls `createStyleFileNow` und `StyleFiles.create` schreiben erst die Datei und lesen
  dann die Reihenfolge, in der die verwaiste Zeile damit wieder gilt. Ob Sass das zweimalige
  `@use` derselben Datei annimmt, ist nicht gemessen.

### Stile: Style Settings schreiben und lesen (`StyleSettingsValues`)

- **Ein Port von `styleSettings.ts`** mit der Gruppierung aus `StyleSettingsForm.tsx`: der Schlüssel
  `<blockId>@@<id>` mit `@@light`/`@@dark`, die Paare, die eine gewählte Farbe ergibt (drei für
  `hsl-split`, beide Modi für eine Theme-Farbe ohne Modus), alle Schlüssel eines Felds für
  „Zurücksetzen“, das Zurücklesen in den Farbwähler (mit dem Vorgabewert des Themes, wenn nichts
  gespeichert ist), ein Patch auf `styleSettings` (leer heißt entfernen), die brauchbaren Felder,
  die Suche und die Gruppen nach den Überschriften des Themes.
- **Gemessen gegen QuartzControls Code:** `scripts/style-settings-golden.mjs` lädt `styleSettings.ts`
  und `buildGroups` aus dem Formular (React und die UI-Bausteine durch Platzhalter ersetzt). Die
  Schemas: Ultra Lobster (176 Felder, die Kopie in QuartzControls Profil, `theme-docs/`, also die
  Doku eines veröffentlichten Themes), Tokyo Night aus `Fixtures/themes` und erfundene Felder jeder
  Art und jedes Formats. 209 Felder mit Schlüsseln, je Farbe acht Hex-Werte in drei Modi, das
  Zurücklesen aus drei Wertesätzen (gültig, schief, leer), 15 Gruppierungen mit Suche, 240 Fälle
  `hslToHex`. Alles gleich.
- Gegenproben (16, jede lässt einen Test scheitern).

### Stile: Community-Themes

- **Wie dort:** das aktive Theme mit Deaktivieren und Wieder-aktivieren (der Eintrag bleibt mit
  `enabled: false`, Theme und Einstellungen bleiben erhalten), „Als Preset speichern“, die
  Style Settings des Themes, die Presets mit Anwenden und Löschen, der Katalog mit Suche und
  „Neu laden“. Die Details eines Katalog-Themes und „Installieren & aktivieren“ stehen im
  Inspektor (die Regel „rechts nur der Inspektor“), in QuartzControl klappte die Zeile auf.
- **Die Style Settings** gruppieren nach den Überschriften des Themes, als `DisclosureGroup`, zu-
  oder aufgeklappt, wie der Autor es vorgibt; eine Suche klappt alles auf. Jede Art hat ihr
  Bedienelement (Schalter, Auswahl, Schieber mit Zahl, Text, Farbwähler, zwei für eine
  Theme-Farbe), dazu „Zurücksetzen“, sobald ein Schlüssel des Felds gesetzt ist.
- **Ein Fehler aus dem ersten Bau:** Das Namensfeld des Presets hing an einem optionalen Namen,
  und nach dem Speichern stand es wieder da. Das Textfeld schreibt seinen Text beim Verschwinden
  noch einmal zurück, und aus `nil` wurde wieder der getippte Name (gesehen, über die
  Bedienungshilfen bestätigt). Jetzt sind „Feld offen“ und „Name“ zwei Zustände.
- **Gemessen** an der gui-test-Kopie mit Theme minimal und mit ultra-lobster (beide installiert),
  Dunkel, 1400×860:
  - Der Katalog kam über `npm search` (177 Themes, 30 sichtbar, „147 weitere Treffer“); die
    Details von cupertino aus seinem `theme.json` im Inspektor.
  - Ultra Lobster mit der Doku aus QuartzControls Cache im Testprofil: „139 Optionen“, die Zahl,
    die QuartzControls Doku nennt (176 im Original, 139 brauchbar), die Gruppen wie im Original
    auf- und zugeklappt.
  - Preset speichern schreibt `.quartz-gui/theme-presets.json` mit `createdAt` als
    `toISOString` (der erste Bau schrieb es ohne „Z“), „Aktiv“ steht daneben; Löschen fragt,
    danach ist die Datei inhaltlich wieder die vom Anfang.
  - Deaktivieren und ⌘S: In der Config steht `enabled: false`, Theme und Modus bleiben.
- **Nicht gemessen:** „Installieren & aktivieren“ und „Anwenden“ eines Presets (beide `npm
  install`, Netz), „Doku neu laden“ gegen GitHub.
- **Nebenbefund, nicht behoben (beide Apps):** Für minimal, das bekannteste Theme, gibt es keine
  Doku. Seine drei `@settings`-Blöcke rücken mit Tabulatoren ein, und die Bibliothek `yaml` lehnt
  das ab („Tabs are not allowed as indentation“), also fällt jeder Block weg und die Antwort ist
  „keins“ (gemessen mit dem echten `theme.css` von kepano/obsidian-minimal, 267 KB). QuartzControls
  `styleSettingsSchemaService` geht denselben Weg mit derselben Bibliothek. Der Reiter zeigt dann
  nur die rohen Schalter.
- **Nebenbefund:** `SyncTests.aSyncThatHangsEnds` flackert (ENOENT auf `askpass-path`, allein in
  zwei von drei Läufen gescheitert); Sync ist in dieser Runde nicht angefasst.

### Stile: eine Variable bearbeiten (`VariableEditing`)

- **Die inneren Funktionen von `VariableRow.tsx`** (`base`, `draft`, `setMode`, `followLight`, wann
  zwei Felder stehen), von Hand portiert: Sie leben in einer React-Komponente, ein Golden über
  QuartzControls Code ginge nur über die ganze Komponente. Jede Regel kam aus einem Review, und ihr
  Fall ist ein Test: die dunkle Hälfte einer in den Modi verschiedenen Variablen bleibt erhalten
  (1.0.1, gui-tests `--secondary`), im umgestellten Projekt wird eine helle Änderung „nur hell“
  geschrieben, in einem nicht umgestellten mit expliziter dunkler Hälfte (siebenundvierzigstes
  Review); eine dunkle Hälfte, die nur den Grundwert wiederholt, gilt als ungesetzt, verglichen als
  CSS-Text (`#A1A1A1` gegen `#a1a1a1`, gui-tests `--gray`); ein geleertes helles Feld springt
  nicht auf den Grundwert zurück; eine eigene Variable verschwindet nie durch eine Änderung; „im
  Dunkelmodus gleich“ nimmt die dunkle Hälfte weg, statt sie zu setzen.
- Gegenproben (9, jede lässt einen Test scheitern; eine war erst ungefangen und bekam ihren Fall:
  eine Variable ohne Farbe, die in Dunkel anders ist).

### Stile: Variablen

- **Wie dort:** die Hauptvariablen nach den Gruppen des Katalogs (Grundfarben offen, die anderen
  zu, mit Anzahl und „n geändert“), darunter alle Theme- und Build-Variablen, ohne Suche nach
  Namensanfang gruppiert (eine Gruppe mit einer einzigen Variablen geht nach „Einzelne
  Variablen“), mit Suche auf 150 begrenzt, dazu „Nur geänderte“ und der Filter Farben/Andere. Die
  Zeile: zwei Farbflecken auf dem Seitengrund der Website, Name, Wert, „n abhängig“, Herkunft, und
  Zurücksetzen bzw. Entfernen einer eigenen Variablen (fragt). Die gewählte Variable steht im
  Inspektor (in QuartzControl in der rechten Spalte): Wert in beiden Modi, Herkunft und Kette,
  „Verwendet diese Variablen“ und „Wird verwendet von“ als Sprünge, die Felder, „Im Dunkelmodus
  abweichend“, Zurücksetzen. Ohne Auswahl zeigt der Inspektor die Zahlen und die eigenen Änderungen
  zum Anspringen. Wo man war (Auswahl, offene Gruppen, Suche, Filter) hält `@SceneStorage`.
- **Ein Sprung** wählt die Variable, öffnet ihre Gruppe, setzt die Suche und scrollt zur Zeile.
  Zwei Dinge aus dem ersten Bau: In einer `Form` sucht `scrollTo` die ID des `ForEach`, nicht die
  eines `.id`-Modifiers (mit diesem scrollte nichts), und es braucht einen Augenblick, bis die eben
  geöffnete Gruppe ihre Zeilen hat. `listRowBackground` erreicht Zeilen in einer
  `DisclosureGroup` nicht; die Hervorhebung liegt deshalb an der Zeile selbst (gesehen).
- **Die Farben-Frage** wird je Graph einmal gestellt, nicht je Tastendruck, und ohne die eigenen
  Änderungen außer denen eigener Variablen, wie dort (eine Zeile darf beim Tippen nicht aus dem
  Filter fallen).
- **Gemessen** an der gui-test-Kopie, Dunkel, 1400×860:
  - Ohne Theme: 64 Hauptvariablen, 151 weitere, 67 geänderte; `--secondary` im Inspektor mit
    „Von dir geändert. Ursprung: Letzter Build“, der Kette und sieben Abhängigen. Der Sprung zu
    `--link-color` landet dort.
  - `--dark` hell auf `#222222` geändert und mit ⌘S gespeichert: In `_quartzcontrol.scss` kommt
    genau eine Regel dazu, `:root:not([saved-theme="dark"]) { --dark: #222222; }` (umgestelltes
    Projekt, Hell und Dunkel verschieden: „nur hell“).
  - Mit Theme minimal: 1143 weitere Variablen, die Werte des Themes mit „Community-Theme“, die
    Präfixgruppen zugeklappt.
- **Nicht gemessen:** die Suche mit ihrer Grenze von 150 und das Entfernen einer eigenen Variablen
  in der laufenden App (beides über die Kernfunktionen getestet, nicht geklickt), die Zeit je
  Tastendruck mit allen Gruppen offen.

### Stile: SCSS und CSS im Code-Editor färben (`CodeColors`)

- **Zwei Sprachen mehr** für den Färber aus 4b: At-Regeln, Eigenschaftsnamen (nicht der Selektor
  `a:hover`: nach dem Doppelpunkt einer Eigenschaft steht keine `{` mehr), Sass- und
  CSS-Variablen, Hex-Farben, Strings, Kommentare zuletzt. `//` ist nur in `.scss` ein Kommentar,
  wie bei Sass, und nicht nach einem Doppelpunkt (`url(https://…)`; QuartzControls Lezer-Grammatik
  färbte eine protokollrelative URL grau, hier bleibt sie ungefärbt). Nach Zeilen und Mustern wie
  HTML und Markdown, kein Parser: Ein Blockkommentar über mehrere Zeilen ist nur an seinen Marken
  gefärbt.
- Gegenproben (4, jede lässt den Test scheitern).

### Stile: „Komponente wählen“ (`ComponentSelectors.list`)

- `componentSelectors` aus QuartzControls `src/data/componentSelectors.ts` für den CSS-Reiter: je
  platzierter Komponente ihr Wurzel-Selektor, und für eine Instanz mit eigener Klasse diese Klasse,
  mit und ohne ihre Kopien, wo sie welche hat. Gemessen im bestehenden `site-preview-golden.mjs`,
  das dieselben Einträge jetzt auch durch `componentSelectors` schickt (dazu ein Plugin ohne
  Layout-Block, das nicht erscheint). Gleich.
- Gegenproben (3, jede lässt den Test scheitern).

### Stile: Eigenes CSS, Editor und Dateien

- **In der Mitte der Editor**, wie dort: custom.scss als erster Reiter, der nicht schließt, jede
  geöffnete Datei als eigener Reiter mit Punkt für „ungespeichert“, `_quartzcontrol.scss` mit seiner
  Warnung. Darüber der Pfad mit „Code prüfen“ (die Datei im Editor, Entwurf eingeschlossen, allein
  kompiliert), „Extern öffnen“ und „Datei importieren…“, dann die Hinweise (Zusammenlegen der
  Vorlagen-Stylesheets von 1.0, ein Entwurf, unter dem etwas geschrieben hat, das Ergebnis der
  SCSS-Prüfung mit Sprung zur Zeile) und „Komponente wählen“. Die Entwürfe liegen im Modell der
  Seite, ein Reiterwechsel verliert nichts; was eine Datei auf der Platte hält, auch, damit
  „geändert“ ein Vergleich bleibt.
- **Die Ladereihenfolge steht im Inspektor** (in QuartzControl in der rechten Spalte): die
  geladenen Dateien mit Nummer, Nach oben, Nach unten, Umbenennen und Löschen (fragt), darunter
  `_quartzcontrol.scss` und custom.scss, „Vorhanden, aber nicht eingebunden“ mit „Einbinden“, und
  „Neue Datei“. Jede Dateiaktion liest custom.scss neu (ein Entwurf bleibt und wird markiert) und
  prüft wieder.
- **Der Code-Editor** kann jetzt zu einer Zeile springen (`CodeJump`), und sein Lineal schneidet ab:
  Seit macOS 14 tun Views das nicht mehr von selbst, und die Kante des Lineals lief vom oberen
  Fensterrand bis unten durch alles über dem Editor (gesehen; den Editor unter „Zusätzliche
  Inhalte“ hätte es genauso getroffen).
- **Gemessen** an der gui-test-Kopie, Dunkel, 1400×860: Die Prüfung beim Ankommen sagt
  „fehlerfrei“; `foundation.scss` aus der Ladereihenfolge geöffnet, eine Zeile getippt, ⌘S: genau
  diese Zeile in der Datei. Eine Zeile mit `@include nope;` und „Code prüfen“: „Undefined mixin“
  mit „In custom/foundation.scss, Zeile 290 öffnen“, der Sprung landet dort. „Neue Datei“ `probe`
  legt `custom/probe.scss` an und nimmt sie in die Ladereihenfolge; Löschen fragt und nimmt beides
  wieder weg.
- **Nicht gemessen:** Zusammenlegen (die Kopien sind schon zusammengelegt), Importieren über den
  Dateidialog, Umbenennen, Verschieben, der Hinweis eines veralteten Entwurfs in der App (das Modell
  ist an der Logik von QuartzControl entlang gebaut, aber nicht geklickt).
